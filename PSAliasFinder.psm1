# ============================================
# PSAliasFinder - PowerShell Alias Discovery Module
# Based on the oh-my-zsh alias-finder plugin
# ============================================

# ----------------------------
# Function: CountActualPipes
# ----------------------------
function CountActualPipes {
    <#
    .SYNOPSIS
        Counts the actual number of pipes in a PowerShell command.

    .DESCRIPTION
        Uses the PowerShell Abstract Syntax Tree (AST) to accurately count
        pipes in a command, ignoring pipes within strings.

    .PARAMETER Command
        The command string to analyze.

    .EXAMPLE
        CountActualPipes "Get-Process | Where-Object Name -eq 'pwsh'"
        Returns: 1
    #>
    [CmdletBinding()]
    param([string]$Command)

    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$null, [ref]$null)
        $pipelineAsts = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.PipelineAst]
        }, $true)

        if ($pipelineAsts.Count -gt 0) {
            return ($pipelineAsts[0].PipelineElements.Count - 1)
        }
        return 0
    }
    catch {
        return 0
    }
}

# ----------------------------
# Function: ShouldShowAliasSuggestion
# ----------------------------
function ShouldShowAliasSuggestion {
    <#
    .SYNOPSIS
        Determines if an alias suggestion should be shown.

    .DESCRIPTION
        Applies intelligent filtering to avoid showing suggestions for:
        - Short commands (less than 8 characters)
        - Complex commands (multiple pipes or many arguments)
        - Aliases that don't save enough characters

    .PARAMETER OriginalCommand
        The original command entered by the user.

    .PARAMETER Alias
        The alias object to evaluate.

    .EXAMPLE
        ShouldShowAliasSuggestion "Get-Process" $aliasObject
    #>
    [CmdletBinding()]
    param(
        [string]$OriginalCommand,
        [PSCustomObject]$Alias
    )

    $firstCommand = ($OriginalCommand -split '\|')[0].Trim()

    # Selective criteria
    if ($firstCommand.Length -lt 8) { return $false }

    $pipeCount = CountActualPipes $OriginalCommand
    $argumentCount = ($OriginalCommand -split '\s+').Count
    if ($pipeCount -gt 1 -or $argumentCount -gt 10) { return $false }

    $absoluteSaving = $firstCommand.Length - $Alias.Name.Length
    if ($absoluteSaving -lt 4) { return $false }

    return $true
}

# ----------------------------
# Function: Find-Alias
# ----------------------------
function Find-Alias {
    <#
    .SYNOPSIS
        Finds aliases for a given PowerShell command.

    .DESCRIPTION
        Searches for existing aliases that match the specified command.
        Supports multiple search modes and filtering options.

    .PARAMETER Command
        The command to search aliases for. Accepts multiple words.

    .PARAMETER Exact
        Find only exact matches for the command.

    .PARAMETER Longer
        Include aliases that are longer than the original command.

    .PARAMETER Cheaper
        Only show aliases that are shorter than the original command.

    .PARAMETER Quiet
        Suppress console output, only return results.

    .PARAMETER Force
        Bypass intelligent filtering and show all matches.

    .EXAMPLE
        Find-Alias Get-ChildItem
        Finds aliases for Get-ChildItem (e.g., gci, ls, dir)

    .EXAMPLE
        Find-Alias "Get-Process" -Exact
        Finds only exact matches for Get-Process

    .EXAMPLE
        Find-Alias "docker ps" -Force
        Shows all aliases for docker ps, bypassing filters
    #>
    [CmdletBinding()]
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
        # Search for matching aliases
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

    # Apply selective criteria
    if (-not $Force) {
        $foundAliases = $foundAliases | Where-Object { ShouldShowAliasSuggestion $fullCommand $_ }
    }

    # Display results
    if (-not $Quiet -and $foundAliases.Count -gt 0) {
        $foundAliases | ForEach-Object {
            Write-Host "$($_.Name) -> $($_.Definition)" -ForegroundColor Green
        }
    }

    return $foundAliases
}

# ----------------------------
# Function: Test-CommandAlias
# ----------------------------
function Test-CommandAlias {
    <#
    .SYNOPSIS
        Tests if a command has an available alias and suggests it.

    .DESCRIPTION
        Internal function used by the Enter key hook to automatically
        suggest aliases when commands are entered.

    .PARAMETER Command
        The command to test for available aliases.

    .EXAMPLE
        Test-CommandAlias "Get-ChildItem"
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Command)

    try {
        $cleanCommand = $Command.Trim() -replace '\s+', ' '
        if ([string]::IsNullOrWhiteSpace($cleanCommand)) { return }

        $firstToken = ($cleanCommand -split '\s+')[0]

        # Count real pipes (not inside strings)
        $pipeCount = CountActualPipes $cleanCommand

        # Criteria: long command, max 1 pipe, not already an alias
        if ($firstToken.Length -ge 8 -and
            $pipeCount -le 1 -and
            -not (Get-Alias -Name $firstToken -ErrorAction SilentlyContinue)) {

            $aliasMatches = Get-Alias | Where-Object { $_.Definition -eq $firstToken }

            if ($aliasMatches -and ($firstToken.Length - $aliasMatches[0].Name.Length) -ge 4) {
                Write-Host "`nFound existing alias for `"$firstToken`". You should use: " -NoNewline -ForegroundColor Yellow
                $aliasNames = $aliasMatches | ForEach-Object { "`"$($_.Name)`"" }
                Write-Host ($aliasNames -join ", ") -ForegroundColor Magenta
            }
        }
    }
    catch {
        Write-Debug "Error in Test-CommandAlias: $_"
    }
}

# ----------------------------
# Function: Set-AliasFinderHook
# ----------------------------
function Set-AliasFinderHook {
    <#
    .SYNOPSIS
        Enables or disables the automatic alias detection hook.

    .DESCRIPTION
        Configures PSReadLine to automatically detect and suggest aliases
        when the Enter key is pressed.

    .PARAMETER Enable
        Explicitly enable the hook and show confirmation message.

    .PARAMETER Disable
        Disable the hook and restore default Enter key behavior.

    .EXAMPLE
        Set-AliasFinderHook -Enable
        Enables automatic alias detection

    .EXAMPLE
        Set-AliasFinderHook -Disable
        Disables automatic alias detection
    #>
    [CmdletBinding()]
    param(
        [switch]$Enable,
        [switch]$Disable
    )

    if ($Disable) {
        Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine
        Write-Host "Alias finder disabled." -ForegroundColor Yellow
        return
    }

    if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Key Enter -BriefDescription "AliasFinder" -ScriptBlock {
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Test-CommandAlias -Command $line
            }

            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }

        if ($Enable) {
            Write-Host "Alias finder enabled." -ForegroundColor Green
        }
    } else {
        Write-Warning "PSReadLine module not found. Alias finder hook requires PSReadLine."
    }
}

# ----------------------------
# Function: Set-AliasFinderConfig
# ----------------------------
function Set-AliasFinderConfig {
    <#
    .SYNOPSIS
        Configures the PSAliasFinder module behavior.

    .DESCRIPTION
        Sets global configuration for automatic alias detection.

    .PARAMETER AutoLoad
        Enable automatic alias detection on module load.

    .EXAMPLE
        Set-AliasFinderConfig -AutoLoad
        Enables automatic alias detection

    .EXAMPLE
        Set-AliasFinderConfig
        Disables automatic alias detection
    #>
    [CmdletBinding()]
    param([switch]$AutoLoad)

    $global:PSAliasFinderConfig = @{ AutoLoad = $AutoLoad.IsPresent }

    if ($AutoLoad) {
        Set-AliasFinderHook -Enable
    } else {
        Set-AliasFinderHook -Disable
    }
}

# ----------------------------
# Module Initialization
# ----------------------------

# Create aliases for Find-Alias function
Set-Alias -Name af -Value Find-Alias -ErrorAction SilentlyContinue
Set-Alias -Name alias-finder -Value Find-Alias -ErrorAction SilentlyContinue

# Initialize configuration
if (-not $global:PSAliasFinderConfig) {
    $global:PSAliasFinderConfig = @{ AutoLoad = $false }
}

# Auto-enable hook if configured
if ($global:PSAliasFinderConfig.AutoLoad -and (Get-Module PSReadLine -ErrorAction SilentlyContinue)) {
    Set-AliasFinderHook
}

# Export module members
Export-ModuleMember -Function Find-Alias, Test-CommandAlias, Set-AliasFinderHook, Set-AliasFinderConfig
Export-ModuleMember -Alias af, alias-finder
