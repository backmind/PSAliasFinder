#
# Module manifest for module 'PSAliasFinder'
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'PSAliasFinder.psm1'

# Version number of this module.
ModuleVersion = '1.0.0'

# ID used to uniquely identify this module
GUID = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d'

# Author of this module
Author = 'Yass Fuentes'

# Company or vendor of this module
CompanyName = ''

# Copyright statement for this module
Copyright = '(c) 2025. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Intelligent alias discovery for PowerShell, inspired by oh-my-zsh alias-finder plugin. Automatically suggests shorter aliases for commonly used commands.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '5.1'

# Functions to export from this module
FunctionsToExport = @('Find-Alias', 'Test-CommandAlias', 'Set-AliasFinderHook', 'Set-AliasFinderConfig')

# Cmdlets to export from this module
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module
AliasesToExport = @('af', 'alias-finder')

# Private data to pass to the module specified in RootModule/ModuleToProcess
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Alias', 'Discovery', 'Productivity', 'PSReadLine', 'CLI', 'Shell', 'Terminal', 'Efficiency')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/backmind/PSAliasFinder/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/backmind/PSAliasFinder'

        # ReleaseNotes of this module
        ReleaseNotes = @'
# PSAliasFinder 1.0.0

## Features
- Intelligent alias discovery for PowerShell commands
- Automatic suggestions when entering long commands
- Multiple search modes: exact, longer, cheaper
- Smart filtering to avoid noise
- PSReadLine integration for seamless experience
- Inspired by oh-my-zsh alias-finder plugin

## Usage
- `Find-Alias <command>` or `af <command>` - Search for aliases
- `Set-AliasFinderHook -Enable` - Enable automatic suggestions
- `Set-AliasFinderHook -Disable` - Disable automatic suggestions
'@

    } # End of PSData hashtable

} # End of PrivateData hashtable

}
