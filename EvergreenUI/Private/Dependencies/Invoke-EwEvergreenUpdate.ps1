Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwEvergreenUpdate {
    [CmdletBinding()]
    param()

    Write-Verbose -Message 'EvergreenUI: Calling Update-Evergreen'
    Update-Evergreen -ErrorAction Stop
}
