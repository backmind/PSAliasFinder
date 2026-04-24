#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

# Use a throwaway config location so we don't stomp on the real one
$tempRoot = Join-Path $env:TEMP "PSAliasFinderTest-$(Get-Random)"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$env:PSALIASFINDER_CONFIG_DIR = $tempRoot

function Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function FAIL($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:failed++ }
$script:failed = 0

try {
    Step "Import-Module via .psd1"
    Import-Module $PSScriptRoot/../PSAliasFinder.psd1 -Force
    OK  "import"

    Step "Exports"
    $mod = Get-Module PSAliasFinder
    if ($mod.Version -ne '2.0.0') { FAIL "version = $($mod.Version), expected 2.0.0" } else { OK "version 2.0.0" }
    $expectedFns = 'Find-Alias','Get-AliasFinderConfig','Set-AliasFinderConfig' | Sort-Object
    $actualFns = ($mod.ExportedFunctions.Keys | Sort-Object) -join ','
    if ($actualFns -eq ($expectedFns -join ',')) { OK "functions: $actualFns" } else { FAIL "functions: $actualFns" }
    $expectedAliases = 'af','alias-finder' | Sort-Object
    $actualAliases = ($mod.ExportedAliases.Keys | Sort-Object) -join ','
    if ($actualAliases -eq ($expectedAliases -join ',')) { OK "aliases: $actualAliases" } else { FAIL "aliases: $actualAliases" }
    if ($null -eq (Get-Command Test-CommandAlias -ErrorAction SilentlyContinue -Module PSAliasFinder)) { OK "Test-CommandAlias not exported (clean break)" } else { FAIL "Test-CommandAlias leaked" }
    if ($null -eq (Get-Command Set-AliasFinderHook -ErrorAction SilentlyContinue -Module PSAliasFinder)) { OK "Set-AliasFinderHook not exported (clean break)" } else { FAIL "Set-AliasFinderHook leaked" }

    Step "Subsystem registration"
    $fps = Get-PSSubsystem -Kind FeedbackProvider
    if ($fps.Implementations.Name -contains 'PSAliasFinder') { OK "FeedbackProvider includes PSAliasFinder" } else { FAIL "FeedbackProvider missing PSAliasFinder: $($fps.Implementations.Name -join ',')" }

    Step "Get-AliasFinderConfig default"
    $cfg = Get-AliasFinderConfig
    if ($cfg.Enabled -eq $true -and $cfg.MinCommandLength -eq 8 -and $cfg.MaxSuggestions -eq 1) {
        OK "defaults look right"
    } else { FAIL "defaults off: $($cfg | ConvertTo-Json -Compress)" }
    if ($cfg.ConfigFile -like "$tempRoot*") { OK "ConfigFile routes to tempRoot" } else { FAIL "ConfigFile = $($cfg.ConfigFile)" }

    Step "Set-AliasFinderConfig persists + reloads in-memory"
    Set-AliasFinderConfig -MinCommandLength 12 -MaxSuggestions 3 -AddIgnored 'Get-ChildItem','Get-Process'
    $cfg2 = Get-AliasFinderConfig
    if ($cfg2.MinCommandLength -eq 12) { OK "MinCommandLength = 12" } else { FAIL "MinCommandLength = $($cfg2.MinCommandLength)" }
    if ($cfg2.MaxSuggestions -eq 3) { OK "MaxSuggestions = 3" } else { FAIL "MaxSuggestions = $($cfg2.MaxSuggestions)" }
    if ($cfg2.IgnoredCommands -contains 'Get-ChildItem' -and $cfg2.IgnoredCommands -contains 'Get-Process') { OK "AddIgnored merged both" } else { FAIL "IgnoredCommands = $($cfg2.IgnoredCommands -join ',')" }

    Step "RemoveIgnored"
    Set-AliasFinderConfig -RemoveIgnored 'Get-Process'
    $cfg3 = Get-AliasFinderConfig
    if ($cfg3.IgnoredCommands -contains 'Get-ChildItem' -and $cfg3.IgnoredCommands -notcontains 'Get-Process') { OK "Get-Process removed, Get-ChildItem retained" } else { FAIL "IgnoredCommands = $($cfg3.IgnoredCommands -join ',')" }

    Step "On-disk persistence"
    $jsonPath = $cfg.ConfigFile
    if (Test-Path $jsonPath) { OK "config.json exists at $jsonPath" } else { FAIL "config.json not written at $jsonPath" }
    $onDisk = Get-Content $jsonPath -Raw | ConvertFrom-Json
    if ($onDisk.MinCommandLength -eq 12) { OK "on-disk MinCommandLength = 12" } else { FAIL "on-disk: $($onDisk | ConvertTo-Json -Compress)" }

    Step "Reset"
    Set-AliasFinderConfig -Reset
    $cfg4 = Get-AliasFinderConfig
    if ($cfg4.MinCommandLength -eq 8 -and $cfg4.MaxSuggestions -eq 1 -and $cfg4.IgnoredCommands.Count -eq 0) { OK "defaults restored" } else { FAIL "reset failed: $($cfg4 | ConvertTo-Json -Compress)" }

    Step "Find-Alias surface"
    $res = Find-Alias Get-ChildItem -Quiet
    if ($res.Count -ge 1 -and $res.Name -contains 'ls') { OK "Find-Alias returns aliases" } else { FAIL "Find-Alias returned: $($res | Out-String)" }

    Step "PassThru"
    $returned = Set-AliasFinderConfig -MinCommandLength 10 -PassThru
    if ($returned -and $returned.MinCommandLength -eq 10) { OK "PassThru returns updated config" } else { FAIL "PassThru returned: $($returned | Out-String)" }

    Step "Re-import in same session is idempotent"
    Import-Module $PSScriptRoot/../PSAliasFinder.psd1 -Force
    Import-Module $PSScriptRoot/../PSAliasFinder.psd1 -Force
    $fpsRe = Get-PSSubsystem -Kind FeedbackProvider
    $count = ($fpsRe.Implementations.Name | Where-Object { $_ -eq 'PSAliasFinder' }).Count
    if ($count -eq 1) { OK "exactly one PSAliasFinder registration after double Import" } else { FAIL "count = $count after re-import" }

    Step "Performance: GetFeedback < 5 ms/call with warm cache"
    $provider = [PSAliasFinder.PSAliasFeedback]::new()
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    $errors = $null; $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput('Get-ChildItem C:\Windows', [ref]$tokens, [ref]$errors)
    $ctx = [System.Management.Automation.Subsystem.Feedback.FeedbackContext]::new(
        [System.Management.Automation.Subsystem.Feedback.FeedbackTrigger]::Success,
        $ast, $tokens, $loc, $null)
    # warm the cache + bypass cooldown for measurement
    Set-AliasFinderConfig -CooldownSeconds 0
    $null = $provider.GetFeedback($ctx, [System.Threading.CancellationToken]::None)
    $iters = 1000
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $iters; $i++) {
        $null = $provider.GetFeedback($ctx, [System.Threading.CancellationToken]::None)
    }
    $sw.Stop()
    $avgMs = $sw.Elapsed.TotalMilliseconds / $iters
    if ($avgMs -lt 5) { OK ("avg {0:N3} ms/call over {1} iters (budget < 5 ms, engine budget 1000 ms)" -f $avgMs, $iters) }
    else              { FAIL ("avg {0:N3} ms/call over {1} iters — over budget" -f $avgMs, $iters) }

    Step "Remove-Module cleanup"
    Remove-Module PSAliasFinder
    $fpsAfter = Get-PSSubsystem -Kind FeedbackProvider
    if ($fpsAfter.Implementations.Name -notcontains 'PSAliasFinder') { OK "provider unregistered on Remove-Module" } else { FAIL "provider still registered after Remove" }

    Step "Cross-session persistence"
    # Write distinctive values in one child pwsh, read them back from another.
    $psd1 = "$PSScriptRoot/../PSAliasFinder.psd1"
    $writeScript = @"
`$env:PSALIASFINDER_CONFIG_DIR = '$tempRoot'
Import-Module '$psd1' -Force
Set-AliasFinderConfig -MinCommandLength 17 -MaxSuggestions 2 -AddIgnored 'Get-CimInstance'
Remove-Module PSAliasFinder
"@
    pwsh -NoProfile -Command $writeScript | Out-Null

    $readScript = @"
`$env:PSALIASFINDER_CONFIG_DIR = '$tempRoot'
Import-Module '$psd1' -Force
`$c = Get-AliasFinderConfig
"`$(`$c.MinCommandLength)|`$(`$c.MaxSuggestions)|`$(`$c.IgnoredCommands -join ',')"
"@
    $readOut = (pwsh -NoProfile -Command $readScript).Trim()
    if ($readOut -eq '17|2|Get-CimInstance') { OK "config survives pwsh restart: $readOut" }
    else                                      { FAIL "expected '17|2|Get-CimInstance', got '$readOut'" }
}
finally {
    Remove-Item Env:\PSALIASFINDER_CONFIG_DIR -ErrorAction SilentlyContinue
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed -gt 0) {
    Write-Host "`n$($script:failed) FAILURES" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll checks passed" -ForegroundColor Green
}
