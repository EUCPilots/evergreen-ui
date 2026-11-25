Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwSettingsPath {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'APPDATA is not set; the Evergreen Workbench settings path cannot be resolved.'
    }
    Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\settings.json'
}
