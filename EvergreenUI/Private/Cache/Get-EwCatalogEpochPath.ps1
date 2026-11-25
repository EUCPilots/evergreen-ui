Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwCatalogEpochPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $directory = Split-Path -Path (Get-EwCachePath) -Parent
    return (Join-Path -Path $directory -ChildPath 'catalog-cache-epoch.json')
}
