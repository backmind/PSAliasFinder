@{

# Binary module (compiled DLL) with a small nested PowerShell script module for public functions.
RootModule = 'bin/PSAliasFinder.dll'
NestedModules = @('PSAliasFinder.psm1')

ModuleVersion = '2.0.0'

# Fresh GUID for 2.0.0 — distinct from the provider's internal GUID.
GUID = '7f15a70a-de01-4091-aa0f-339a5a1a6060'

Author = 'Yass Fuentes'
CompanyName = ''
Copyright = '(c) 2025-2026 Yass Fuentes. All rights reserved.'

Description = 'Intelligent alias discovery for PowerShell, inspired by the oh-my-zsh alias-finder plugin. Suggests shorter aliases for long commands you just ran via the native IFeedbackProvider subsystem.'

# 7.4 minimum (experimental feature flags required); 7.6+ works out of the box.
PowerShellVersion = '7.4'
CompatiblePSEditions = @('Core')

FunctionsToExport = @('Find-Alias', 'Set-AliasFinderConfig', 'Get-AliasFinderConfig')
CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @('af', 'alias-finder')

PrivateData = @{

    PSData = @{

        Tags = @('alias','discovery','productivity','powershell','feedback-provider','subsystem','shell','terminal','efficiency')

        LicenseUri = 'https://github.com/backmind/PSAliasFinder/blob/main/LICENSE'
        ProjectUri = 'https://github.com/backmind/PSAliasFinder'

        ReleaseNotes = @'
# PSAliasFinder 2.0.0

BREAKING: minimum PowerShell version raised to 7.4. Alias suggestions now use
the IFeedbackProvider subsystem instead of a PSReadLine key hook. Output is
rendered in the native [Feedback] block and styleable via $PSStyle.

Set-AliasFinderHook and Test-CommandAlias have been removed — no shims. Legacy
users should stay on 1.0.0 (Install-Module PSAliasFinder -RequiredVersion 1.0.0).

## New

- IFeedbackProvider integration (fires on success, aggressive filters).
- Persistent per-user config at $env:APPDATA\PSAliasFinder\config.json.
- Cooldown (default 30 min), ignore list, MaxSuggestions (default 1).
- Get-AliasFinderConfig returns current settings as PSCustomObject.

## PowerShell version notes

- 7.6+: works out of the box. No flags.
- 7.4 / 7.5: requires BOTH experimental features enabled + restart:
    Enable-ExperimentalFeature PSFeedbackProvider
    Enable-ExperimentalFeature PSSubsystemPluginModel
- 7.0-7.3 / 5.1: not supported. Stay on 1.0.0.
'@

    }

}

}
