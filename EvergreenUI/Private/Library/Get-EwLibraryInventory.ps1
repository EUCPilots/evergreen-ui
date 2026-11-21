Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwLibraryInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Get-EvergreenLibrary -Path $Path -ErrorAction Stop
}
