Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('IntuneWin32App', 'Microsoft.Graph.Authentication', 'Az.Accounts', 'Az.Storage')]
        [string]$Name
    )

    Write-Verbose -Message "EvergreenUI: Checking optional module $Name"
    if (-not (Get-Module -ListAvailable -Name $Name -ErrorAction Stop)) {
        throw "The optional module '$Name' is required for this operation. Install it with Install-Module -Name $Name -Scope CurrentUser."
    }
    Import-Module -Name $Name -ErrorAction Stop
    Write-Verbose -Message "EvergreenUI: Optional module $Name loaded"
}
