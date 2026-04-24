# PSAliasFinder — PowerShell-side public surface.
# Backend (feedback provider + alias cache + config I/O) lives in the
# PSAliasFinder.dll loaded as RootModule.

function CountActualPipes {
    [CmdletBinding()]
    param([string]$Command)

    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Command, [ref]$null, [ref]$null)
        $pipelines = $ast.FindAll({
            param($node) $node -is [System.Management.Automation.Language.PipelineAst]
        }, $true)
        if ($pipelines.Count -gt 0) {
            return ($pipelines[0].PipelineElements.Count - 1)
        }
        return 0
    } catch {
        return 0
    }
}

function ShouldShowAliasSuggestion {
    [CmdletBinding()]
    param(
        [string]$OriginalCommand,
        [PSCustomObject]$Alias
    )

    $cfg = [PSAliasFinder.ProviderConfig]::Current
    $firstCommand = ($OriginalCommand -split '\|')[0].Trim()

    if ($firstCommand.Length -lt $cfg.MinCommandLength) { return $false }

    $pipeCount = CountActualPipes $OriginalCommand
    $argumentCount = ($OriginalCommand -split '\s+').Count
    if ($pipeCount -gt $cfg.MaxPipes -or $argumentCount -gt $cfg.MaxArguments) { return $false }

    $absoluteSaving = $firstCommand.Length - $Alias.Name.Length
    if ($absoluteSaving -lt $cfg.MinCharsSaved) { return $false }

    return $true
}

function Find-Alias {
    <#
    .SYNOPSIS
        Finds aliases for a given PowerShell command.

    .DESCRIPTION
        Explicit lookup surface preserved from 1.0.0. Independent of the IFeedbackProvider
        subsystem: searches the current session's alias table directly and applies the
        same default filter as the feedback provider (reading PSAliasFinder config for
        thresholds). Use -Force to bypass the filter.

    .PARAMETER Command
        The command to search aliases for. Accepts multiple tokens.

    .PARAMETER Exact
        Only exact matches.

    .PARAMETER Longer
        Include aliases whose definition contains the command (broader than Exact).

    .PARAMETER Cheaper
        Only aliases strictly shorter than the full command.

    .PARAMETER Quiet
        Suppress console output; emit objects only.

    .PARAMETER Force
        Bypass the default filter (MinCommandLength / MaxPipes / MaxArguments / MinCharsSaved).

    .EXAMPLE
        Find-Alias Get-ChildItem
    #>
    [CmdletBinding()]
    [Alias('af','alias-finder')]
    param (
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$Command,
        [switch]$Exact,
        [switch]$Longer,
        [switch]$Cheaper,
        [switch]$Quiet,
        [switch]$Force
    )

    $fullCommand = ($Command -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($fullCommand)) { return @() }

    $foundAliases = @()
    $currentCmd = $fullCommand

    while (-not [string]::IsNullOrWhiteSpace($currentCmd)) {
        $matchingAliases = Get-Alias | Where-Object {
            if ($Exact) {
                $_.Definition -eq $currentCmd
            } elseif ($Longer) {
                $_.Definition -like "*$currentCmd*"
            } else {
                $_.Definition -eq $currentCmd -or
                ($currentCmd.StartsWith($_.Definition) -and
                 $currentCmd.Length -gt $_.Definition.Length -and
                 $currentCmd[$_.Definition.Length] -match '\s')
            }
        } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Definition = $_.Definition
            }
        }

        if ($Cheaper) {
            $matchingAliases = $matchingAliases | Where-Object {
                $_.Name.Length -lt $fullCommand.Length
            }
        }

        foreach ($alias in $matchingAliases) {
            if ($foundAliases.Name -notcontains $alias.Name) {
                $foundAliases += $alias
            }
        }

        if ($Exact -or $Longer) { break }

        $words = $currentCmd.Trim() -split '\s+'
        if ($words.Count -le 1) { break }
        $currentCmd = ($words[0..($words.Count-2)] -join ' ').Trim()
    }

    if (-not $Force) {
        $foundAliases = $foundAliases | Where-Object { ShouldShowAliasSuggestion $fullCommand $_ }
    }

    if (-not $Quiet -and $foundAliases.Count -gt 0) {
        foreach ($alias in $foundAliases) {
            Write-Host "$($alias.Name) -> $($alias.Definition)" -ForegroundColor Green
        }
    }

    return $foundAliases
}

function Get-AliasFinderConfig {
    <#
    .SYNOPSIS
        Returns the current PSAliasFinder configuration.

    .DESCRIPTION
        Emits the live ProviderConfig snapshot as a PSCustomObject, including the
        on-disk config file path. Reflects the state the feedback provider is
        actually using — after Set-AliasFinderConfig, the in-memory copy is
        updated without reimporting.
    #>
    [CmdletBinding()]
    param()

    $c = [PSAliasFinder.ProviderConfig]::Current
    [pscustomobject]@{
        Enabled          = $c.Enabled
        MinCommandLength = $c.MinCommandLength
        MaxPipes         = $c.MaxPipes
        MaxArguments     = $c.MaxArguments
        MinCharsSaved    = $c.MinCharsSaved
        CooldownSeconds  = $c.CooldownSeconds
        MaxSuggestions   = $c.MaxSuggestions
        IgnoredCommands  = $c.IgnoredCommands
        ConfigFile       = [PSAliasFinder.ProviderConfig]::ConfigFile
    }
}

function Set-AliasFinderConfig {
    <#
    .SYNOPSIS
        Updates and persists PSAliasFinder configuration.

    .DESCRIPTION
        Changes apply live: the JSON file at $env:APPDATA\PSAliasFinder\config.json
        is rewritten and the in-memory ProviderConfig.Current is swapped, so the
        feedback provider uses the new values on the next command without
        reimporting the module.

    .PARAMETER Reset
        Restore all defaults before applying any other parameters.

    .PARAMETER PassThru
        Emit the resulting config object after saving.
    #>
    [CmdletBinding()]
    param(
        [bool]$Enabled,
        [int]$MinCommandLength,
        [int]$MaxPipes,
        [int]$MaxArguments,
        [int]$MinCharsSaved,
        [int]$CooldownSeconds,
        [int]$MaxSuggestions,
        [string[]]$IgnoredCommands,
        [string[]]$AddIgnored,
        [string[]]$RemoveIgnored,
        [switch]$Reset,
        [switch]$PassThru
    )

    $current = [PSAliasFinder.ProviderConfig]::Current

    if ($Reset) {
        $config = [PSAliasFinder.ProviderConfig]::new()
    } else {
        $config = [PSAliasFinder.ProviderConfig]::new()
        $config.Enabled          = $current.Enabled
        $config.MinCommandLength = $current.MinCommandLength
        $config.MaxPipes         = $current.MaxPipes
        $config.MaxArguments     = $current.MaxArguments
        $config.MinCharsSaved    = $current.MinCharsSaved
        $config.CooldownSeconds  = $current.CooldownSeconds
        $config.MaxSuggestions   = $current.MaxSuggestions
        $config.IgnoredCommands  = $current.IgnoredCommands
    }

    if ($PSBoundParameters.ContainsKey('Enabled'))          { $config.Enabled          = $Enabled }
    if ($PSBoundParameters.ContainsKey('MinCommandLength')) { $config.MinCommandLength = $MinCommandLength }
    if ($PSBoundParameters.ContainsKey('MaxPipes'))         { $config.MaxPipes         = $MaxPipes }
    if ($PSBoundParameters.ContainsKey('MaxArguments'))     { $config.MaxArguments     = $MaxArguments }
    if ($PSBoundParameters.ContainsKey('MinCharsSaved'))    { $config.MinCharsSaved    = $MinCharsSaved }
    if ($PSBoundParameters.ContainsKey('CooldownSeconds'))  { $config.CooldownSeconds  = $CooldownSeconds }
    if ($PSBoundParameters.ContainsKey('MaxSuggestions'))   { $config.MaxSuggestions   = $MaxSuggestions }
    if ($PSBoundParameters.ContainsKey('IgnoredCommands'))  { $config.IgnoredCommands  = $IgnoredCommands }

    if ($PSBoundParameters.ContainsKey('AddIgnored')) {
        $merged = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$config.IgnoredCommands,
            [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $AddIgnored) { [void]$merged.Add($item) }
        $config.IgnoredCommands = [string[]]@($merged)
    }

    if ($PSBoundParameters.ContainsKey('RemoveIgnored')) {
        $toRemove = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$RemoveIgnored,
            [System.StringComparer]::OrdinalIgnoreCase)
        $config.IgnoredCommands = [string[]]@($config.IgnoredCommands | Where-Object { -not $toRemove.Contains($_) })
    }

    $config.Save()

    if ($PassThru) {
        Get-AliasFinderConfig
    }
}

Export-ModuleMember -Function Find-Alias, Get-AliasFinderConfig, Set-AliasFinderConfig -Alias af, alias-finder
