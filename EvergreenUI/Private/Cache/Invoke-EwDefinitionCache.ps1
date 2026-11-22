Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwDefinitionCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Read', 'Write')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter()]
        [string]$Epoch,

        [Parameter()]
        [psobject]$Entry
    )

    $cacheAction = $Action
    $expectedEpoch = $Epoch
    $cacheEntry = $Entry
    $cacheFile = Join-Path -Path $CachePath -ChildPath 'definition-artifact-cache.json'
    $epochFile = Join-Path -Path $CachePath -ChildPath 'definition-cache-epoch.json'
    Invoke-EwCacheLock -Path $epochFile -ScriptBlock {
        $currentEpoch = Get-EwCacheEpoch -Path $epochFile
        if ($cacheAction -eq 'Write' -and $expectedEpoch -ne $currentEpoch) {
            Write-Verbose -Message 'EvergreenUI: Definition cache write skipped; cache was cleared during lookup'
            return
        }
        $entries = @()
        if ((Test-Path -LiteralPath $cacheFile -ErrorAction Stop) -and
            -not (Test-Path -LiteralPath $cacheFile -PathType Leaf -ErrorAction Stop)) {
            throw "Owned cache payload is not a file: '$cacheFile'."
        }
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf -ErrorAction Stop) {
            $entries = @(Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
            $entries = @($entries | Where-Object {
                ($null -ne $_.PSObject.Properties['CacheEpoch'] -and $_.CacheEpoch -eq $currentEpoch)
            })
        }
        if ($cacheAction -eq 'Read') {
            return [PSCustomObject]@{ Epoch = $currentEpoch; Entries = $entries }
        }
        $entries = @($entries | Where-Object { [string]$_.DefinitionPath -ine [string]$cacheEntry.DefinitionPath })
        $cacheEntry | Add-Member -NotePropertyName CacheEpoch -NotePropertyValue $currentEpoch -Force
        $entries += $cacheEntry
        $null = New-Item -Path $CachePath -ItemType Directory -Force -ErrorAction Stop
        Write-EwJsonFile -Path $cacheFile -InputObject @($entries) -ErrorAction Stop
        Write-Verbose -Message "EvergreenUI: Definition artifact cache saved to '$cacheFile'"
    }
}
