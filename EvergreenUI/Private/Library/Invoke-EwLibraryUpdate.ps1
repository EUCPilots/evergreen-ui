Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwLibraryUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Start-EvergreenLibraryUpdate -Path $Path -ErrorAction Stop
}
