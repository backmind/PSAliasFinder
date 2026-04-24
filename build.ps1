#Requires -Version 7.4
<#
.SYNOPSIS
    Build the PSAliasFinder binary module.

.DESCRIPTION
    Runs `dotnet publish` on src/PSAliasFinder.csproj and lands the output in ./bin/.
    The published layout is what `Import-Module ./PSAliasFinder.psd1` expects.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$srcProject = Join-Path $repoRoot 'src' 'PSAliasFinder.csproj'
$binDir = Join-Path $repoRoot 'bin'

if (Test-Path $binDir) {
    Remove-Item $binDir -Recurse -Force
}

dotnet publish $srcProject -c $Configuration -o $binDir
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

Write-Host "Built: $binDir\PSAliasFinder.dll" -ForegroundColor Green
