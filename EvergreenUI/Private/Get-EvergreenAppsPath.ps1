#Requires -Version 5.1

function Get-EvergreenAppsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Evergreen')
    }

    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return (Join-Path -Path $env:APPDATA -ChildPath 'Evergreen')
    }

    return (Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'Evergreen')
}