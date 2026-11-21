Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwAppCatalogQuery {
    [CmdletBinding()]
    param()

    Find-EvergreenApp -ErrorAction Stop
}
