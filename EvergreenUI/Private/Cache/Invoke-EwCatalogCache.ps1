Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwCatalogCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Read', 'Write', 'Clear')]
        [string]$Action,

        [Parameter()]
        [string]$Epoch,

        [Parameter()]
        [object[]]$Items
    )

    $cacheAction = $Action
    $expectedEpoch = $Epoch
    $catalogItems = $Items
    $path = Get-EwCatalogEpochPath
    Invoke-EwCacheLock -Path $path -ScriptBlock {
        if ($cacheAction -eq 'Clear') {
            $newEpoch = Invoke-EwCacheInvalidation -Path $path -ErrorAction Stop
            $script:ewAppCatalogCache = @{ RetrievedAt = $null; Items = @(); Epoch = $newEpoch }
            Write-Verbose -Message 'EvergreenUI: All Workbench catalog caches invalidated'
            return
        }
        $currentEpoch = Get-EwCacheEpoch -Path $path
        if ($cacheAction -eq 'Read') {
            $cache = $script:ewAppCatalogCache
            if (-not $cache.ContainsKey('Epoch') -or $cache.Epoch -ne $currentEpoch) {
                $cache = @{ RetrievedAt = $null; Items = @(); Epoch = $currentEpoch }
                $script:ewAppCatalogCache = $cache
            }
            return [PSCustomObject]@{ Epoch = $currentEpoch; RetrievedAt = $cache.RetrievedAt; Items = $cache.Items }
        }
        if ($expectedEpoch -eq $currentEpoch) {
            $script:ewAppCatalogCache = @{ RetrievedAt = [DateTimeOffset]::Now; Items = $catalogItems; Epoch = $currentEpoch }
        }
        else {
            Write-Verbose -Message 'EvergreenUI: Catalog cache write skipped; cache was cleared during lookup'
        }
    }
}
