Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAppVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    Get-EvergreenApp -Name $Name -ErrorAction Stop
}
