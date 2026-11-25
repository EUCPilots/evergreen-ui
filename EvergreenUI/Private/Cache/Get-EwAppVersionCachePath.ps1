Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAppVersionCachePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$CachePath
    )

    $root = Get-EwCachePath -CachePath $CachePath -ErrorAction Stop
    return (Join-Path -Path $root -ChildPath 'Apps')
}
