#Requires -Version 7.4
# Isolate from any real on-disk config
$tempRoot = Join-Path $env:TEMP "PSAliasFinderFeedbackTest-$(Get-Random)"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$env:PSALIASFINDER_CONFIG_DIR = $tempRoot

try {
Import-Module $PSScriptRoot/../bin/PSAliasFinder.dll -Force

$provider = [PSAliasFinder.PSAliasFeedback]::new()

$loc = $ExecutionContext.SessionState.Path.CurrentLocation

function Test-Feedback([string]$cmdline, [string]$label) {
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $cmdline, [ref]$tokens, [ref]$errors)
    $ctx = [System.Management.Automation.Subsystem.Feedback.FeedbackContext]::new(
        [System.Management.Automation.Subsystem.Feedback.FeedbackTrigger]::Success,
        $ast, $tokens, $loc, $null)
    $item = $provider.GetFeedback($ctx, [System.Threading.CancellationToken]::None)
    if ($null -ne $item) {
        $actions = $item.RecommendedActions -join ', '
        Write-Host "PASS [$label] => $($item.Header) | actions: $actions" -ForegroundColor Green
    } else {
        Write-Host "NULL [$label] => <no feedback>" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Feedback algorithm tests ===" -ForegroundColor Cyan
Test-Feedback 'Get-ChildItem C:\Windows' 'Long command (expect shortest alias: ls on Windows default)'
Test-Feedback 'Get-ChildItem C:\Windows' 'Same again (cooldown should suppress)'
Test-Feedback 'Get-Acl foo'               '7-char command (should null: MinCommandLength filter)'
Test-Feedback 'Get-Date'                  '8-char command with no alias matching savings (should null)'
Test-Feedback 'gci C:\Windows'            'Already an alias (should null: IsAlias filter)'
Test-Feedback 'Get-ChildItem | Where-Object Name -like *.dll | Select-Object -First 3' 'Two pipes (should null: MaxPipes filter)'
Test-Feedback 'Get-ChildItem -Path C:\ -Recurse -File -Force -Hidden -Depth 2 -ErrorAction SilentlyContinue -ErrorVariable e -OutVariable o' 'Many args >10 (should null: MaxArguments filter)'

Write-Host "`n=== IsAlias / cache sanity ===" -ForegroundColor Cyan
$ps = [System.Management.Automation.PowerShell]::Create()
$cacheType = [PSAliasFinder.PSAliasFeedback].Assembly.GetType('PSAliasFinder.AliasCache')
$cache = [Activator]::CreateInstance($cacheType, @($ps))
$shortest = $cache.GetShortestAliasFor('Get-ChildItem')
$isAliasGci = $cache.IsAlias('gci')
$isAliasFoo = $cache.IsAlias('not-a-real-alias-xyz')
# Accept either ls (2) or gci (3) — depends on the default Windows alias set
$shortestOk = $shortest -in @('ls','gci','dir')
Write-Host "GetShortestAliasFor('Get-ChildItem') = '$shortest' (expected one of ls/gci/dir)" -ForegroundColor $(if ($shortestOk) { 'Green' } else { 'Red' })
Write-Host "IsAlias('gci')   = $isAliasGci (expected True)" -ForegroundColor $(if ($isAliasGci) { 'Green' } else { 'Red' })
Write-Host "IsAlias('xyz..') = $isAliasFoo (expected False)" -ForegroundColor $(if (-not $isAliasFoo) { 'Green' } else { 'Red' })
$ps.Dispose()

Write-Host "`n=== Config sanity ===" -ForegroundColor Cyan
$cfg = [PSAliasFinder.ProviderConfig]::Current
Write-Host "Enabled=$($cfg.Enabled) MinCmdLen=$($cfg.MinCommandLength) MinSaved=$($cfg.MinCharsSaved) Cooldown=$($cfg.CooldownSeconds) MaxSuggestions=$($cfg.MaxSuggestions)"

Write-Host "`n=== MaxSuggestions = 3 (expect multiple aliases for Get-ChildItem) ===" -ForegroundColor Cyan
$cfg.MaxSuggestions = 3
$cfg.CooldownSeconds = 0
$provider2 = [PSAliasFinder.PSAliasFeedback]::new()
$errors = $null; $tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput('Get-ChildItem C:\Windows', [ref]$tokens, [ref]$errors)
$ctx = [System.Management.Automation.Subsystem.Feedback.FeedbackContext]::new(
    [System.Management.Automation.Subsystem.Feedback.FeedbackTrigger]::Success,
    $ast, $tokens, $loc, $null)
$item = $provider2.GetFeedback($ctx, [System.Threading.CancellationToken]::None)
if ($null -ne $item) {
    Write-Host "Header : $($item.Header)" -ForegroundColor Green
    $item.RecommendedActions | ForEach-Object { Write-Host "Action : $_" -ForegroundColor Green }
} else {
    Write-Host "NULL (unexpected)" -ForegroundColor Red
}

Remove-Module PSAliasFinder
}
finally {
    Remove-Item Env:\PSALIASFINDER_CONFIG_DIR -ErrorAction SilentlyContinue
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
