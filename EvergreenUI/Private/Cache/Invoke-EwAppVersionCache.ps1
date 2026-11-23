Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwAppVersionCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Read', 'Write', 'Clear')]
        [string]$Action,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Epoch,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [Parameter()]
        [string]$CachePath
    )

    $cacheAction = $Action
    $expectedEpoch = $Epoch
    $appArtifacts = $Artifacts
    $directory = Get-EwAppVersionCachePath -CachePath $CachePath -ErrorAction Stop
    $epochFile = Join-Path -Path $directory -ChildPath 'app-cache-epoch.json'
    if ($cacheAction -ne 'Clear' -and $Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Application name '$Name' cannot be used as a cache file name."
    }
    $cacheFile = if ($cacheAction -ne 'Clear') { Join-Path -Path $directory -ChildPath "$Name.json" } else { '' }

    Invoke-EwCacheLock -Path $epochFile -ScriptBlock {
        if ($cacheAction -eq 'Clear') {
            $newEpoch = Invoke-EwCacheInvalidation -Path $epochFile -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Application version cache invalidated at '$directory'"
            $removed = 0
            $errors = [System.Collections.Generic.List[string]]::new()
            foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction Stop)) {
                if ($file.Name -ieq 'app-cache-epoch.json') { continue }
                try {
                    [System.IO.File]::Delete($file.FullName)
                    $removed++
                }
                catch {
                    $errors.Add("$($file.Name): $($_.Exception.Message)")
                    Write-Verbose -Message "EvergreenUI: Application version cache file could not be removed: '$($file.FullName)': $($_.Exception.Message)"
                }
            }
            Write-Verbose -Message "EvergreenUI: Application version cache removed $removed files"
            return [PSCustomObject]@{ Epoch = $newEpoch; RemovedCount = $removed; Errors = [string[]]$errors.ToArray() }
        }

        $currentEpoch = Get-EwCacheEpoch -Path $epochFile
        if ($cacheAction -eq 'Read') {
            $entry = $null
            if ((Test-Path -LiteralPath $cacheFile -ErrorAction Stop) -and
                -not (Test-Path -LiteralPath $cacheFile -PathType Leaf -ErrorAction Stop)) {
                throw "Owned cache payload is not a file: '$cacheFile'."
            }
            if (Test-Path -LiteralPath $cacheFile -PathType Leaf -ErrorAction Stop) {
                try {
                    $candidate = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop |
                        ConvertFrom-Json -DateKind String -ErrorAction Stop
                    if ($null -ne $candidate -and
                        $null -ne $candidate.PSObject.Properties['CacheEpoch'] -and
                        $candidate.CacheEpoch -eq $currentEpoch -and
                        $null -ne $candidate.PSObject.Properties['Artifacts']) {
                        $entry = $candidate
                    }
                    else {
                        Write-Verbose -Message "EvergreenUI: Application version cache for '$Name' belongs to an earlier cache generation; ignoring"
                    }
                }
                catch {
                    # A corrupt payload is treated as a miss and overwritten by the next successful lookup.
                    Write-Verbose -Message "EvergreenUI: Application version cache for '$Name' could not be parsed: $($_.Exception.Message)"
                }
            }
            return [PSCustomObject]@{ Epoch = $currentEpoch; Entry = $entry }
        }

        if ($expectedEpoch -ne $currentEpoch) {
            Write-Verbose -Message "EvergreenUI: Application version cache write for '$Name' skipped; cache was cleared during lookup"
            return
        }
        $payload = [PSCustomObject]@{
            Name        = $Name
            RetrievedAt = [DateTimeOffset]::UtcNow.ToString('o')
            CacheEpoch  = $currentEpoch
            Artifacts   = @($appArtifacts)
        }
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        Write-EwJsonFile -Path $cacheFile -InputObject $payload -ErrorAction Stop
        Write-Verbose -Message "EvergreenUI: Application version cache saved for '$Name' to '$cacheFile'"
    }
}
