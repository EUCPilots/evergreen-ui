#Requires -Version 5.1
<#
.SYNOPSIS
    EvergreenUI - WPF graphical frontend for the Evergreen PowerShell module.

.DESCRIPTION
    Root module file. Dot-sources all Private helper functions and then all
    Public functions. Only functions listed in FunctionsToExport in the manifest
    (Start-EvergreenWorkbench) are exposed to the caller.

.NOTES
    - Windows only. Requires WPF assemblies (PresentationFramework etc.).
    - Supports PowerShell 5.1 (Desktop) and PowerShell 7+ (Core on Windows).
    - Do not call Private functions directly; they are implementation details.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source Private functions 
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# Themes first - other helpers may reference theme functions
Get-ChildItem -Path (Join-Path -Path $privatePath -ChildPath 'themes') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }

# Remaining private helpers
Get-ChildItem -Path $privatePath -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }

# Dot-source Public functions 
$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }
