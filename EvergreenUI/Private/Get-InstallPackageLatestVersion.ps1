#Requires -Version 5.1
<#!
.SYNOPSIS
    Resolves latest package artifact for Install workflow with local JSON cache.

.DESCRIPTION
    Wraps Get-IntunePackageLatestVersion and stores per-definition resolution
    results in a cache JSON file. Cached entries are reused when still fresh.

.PARAMETER DefinitionPath
    Full path to App.json definition file.

.PARAMETER DefinitionObject
    Parsed App.json object.

.PARAMETER CacheRootPath
    Directory where the cache file is written.

.PARAMETER CacheMaxAgeHours
    Maximum cache age before refresh. Default: 24.

.PARAMETER CacheState
    Optional mutable batch cache state. When supplied, cache entries are loaded
    and updated in memory; the caller is responsible for saving the state.

.OUTPUTS
    PSCustomObject with:
        Succeeded    : bool
        Version      : string
        URI          : string
        ResolvedArtifact : object
        FilterExpression: string
        Error        : string
        IsFromCache  : bool
        CacheFile    : string
!#>
function Get-InstallPackageLatestVersion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$DefinitionObject,

        [Parameter(Mandatory)]
        [string]$CacheRootPath,

        [int]$CacheMaxAgeHours = 24,

        [hashtable]$CacheState
    )

    $fail = {
        param([string]$Message)
        return [PSCustomObject]@{
            Succeeded        = $false
            Version          = ''
            URI              = ''
            ResolvedArtifact = $null
            FilterExpression = ''
            Error            = $Message
            IsFromCache      = $false
            CacheFile        = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($DefinitionPath)) {
        return (& $fail 'DefinitionPath is empty.')
    }

    if ($null -eq $DefinitionObject) {
        return (& $fail 'DefinitionObject is null.')
    }

    if ([string]::IsNullOrWhiteSpace($CacheRootPath)) {
        return (& $fail 'CacheRootPath is empty.')
    }

    try {
        if (-not (Test-Path -LiteralPath $CacheRootPath -PathType Container)) {
            $null = New-Item -Path $CacheRootPath -ItemType Directory -Force -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Created cache directory '$CacheRootPath'."
        }
    }
    catch {
        return (& $fail "Failed to create cache directory '$CacheRootPath': $($_.Exception.Message)")
    }

    $cacheFile = Join-Path -Path $CacheRootPath -ChildPath 'install-latest-cache.json'
    $ownsCacheState = $null -eq $CacheState
    if ($ownsCacheState) {
        $CacheState = Initialize-InstallLatestCache -CacheFile $cacheFile
    }
    elseif (-not $CacheState.ContainsKey('Entries')) {
        $CacheState.Entries = @()
    }
    $cacheEntries = @($CacheState.Entries)

    $nowUtc = [DateTime]::UtcNow
    $definitionKey = $DefinitionPath.Trim().ToLowerInvariant()
    $matchedEntry = $null

    foreach ($entry in $cacheEntries) {
        if ($null -eq $entry) { continue }
        $entryPath = [string]$entry.DefinitionPath
        if ([string]::IsNullOrWhiteSpace($entryPath)) { continue }
        if ($entryPath.Trim().ToLowerInvariant() -eq $definitionKey) {
            $matchedEntry = $entry
            break
        }
    }

    if ($null -ne $matchedEntry) {
        [DateTime]$retrievedUtc = [DateTime]::MinValue
        $rawTimestamp = $matchedEntry.RetrievedUtc
        $timestampOk = $false
        if ($rawTimestamp -is [DateTime]) {
            $retrievedUtc = [DateTime]$rawTimestamp
            $timestampOk = $true
        }
        elseif ([DateTime]::TryParseExact(
                [string]$rawTimestamp,
                'o',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$retrievedUtc
            )) {
            $timestampOk = $true
        }
        elseif ([DateTime]::TryParse(
                [string]$rawTimestamp,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$retrievedUtc
            )) {
            $timestampOk = $true
        }
        if ($timestampOk) {
            $maxAge = [TimeSpan]::FromHours([Math]::Max(1, $CacheMaxAgeHours))
            $cacheAge = $nowUtc - $retrievedUtc.ToUniversalTime()
            if ($cacheAge -le $maxAge) {
                Write-Verbose -Message "EvergreenUI: Cache hit for '$DefinitionPath' (age: $([Math]::Round($cacheAge.TotalMinutes, 1)) min, max: $($maxAge.TotalHours) hr)."
                return [PSCustomObject]@{
                    Succeeded        = [bool]$matchedEntry.Succeeded
                    Version          = [string]$matchedEntry.Version
                    URI              = [string]$matchedEntry.URI
                    ResolvedArtifact = $matchedEntry.ResolvedArtifact
                    FilterExpression = [string]$matchedEntry.FilterExpression
                    Error            = [string]$matchedEntry.Error
                    IsFromCache      = $true
                    CacheFile        = $cacheFile
                }
            }
        }
    }

    $liveResult = Get-IntunePackageLatestVersion -DefinitionObject $DefinitionObject
    $cacheRecord = [PSCustomObject]@{
        DefinitionPath   = $definitionKey
        RetrievedUtc     = $nowUtc.ToString('o')
        Succeeded        = [bool]$liveResult.Succeeded
        Version          = [string]$liveResult.Version
        URI              = [string]$liveResult.URI
        ResolvedArtifact = $liveResult.ResolvedArtifact
        FilterExpression = [string]$liveResult.FilterExpression
        Error            = [string]$liveResult.Error
    }

    $newEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $cacheEntries) {
        if ($null -eq $entry) { continue }
        $entryPath = [string]$entry.DefinitionPath
        if ([string]::IsNullOrWhiteSpace($entryPath)) { continue }
        if ($entryPath.Trim().ToLowerInvariant() -eq $definitionKey) { continue }
        $newEntries.Add($entry)
    }
    $newEntries.Add($cacheRecord)
    $CacheState.Entries = @($newEntries)
    $CacheState.Dirty = $true

    if ($ownsCacheState) {
        $null = Save-InstallLatestCache -CacheState $CacheState
    }

    return [PSCustomObject]@{
        Succeeded        = [bool]$liveResult.Succeeded
        Version          = [string]$liveResult.Version
        URI              = [string]$liveResult.URI
        ResolvedArtifact = $liveResult.ResolvedArtifact
        FilterExpression = [string]$liveResult.FilterExpression
        Error            = [string]$liveResult.Error
        IsFromCache      = $false
        CacheFile        = $cacheFile
    }
}

function Initialize-InstallLatestCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheFile
    )

    $entries = @()
    if (Test-Path -LiteralPath $CacheFile -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $CacheFile -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                if ($parsed -is [System.Array]) { $entries = @($parsed) }
                elseif ($null -ne $parsed) { $entries = @($parsed) }
            }
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to read/parse cache file '$CacheFile' (will query live): $($_.Exception.Message)"
        }
    }

    return @{
        CacheFile = $CacheFile
        Entries   = $entries
        Dirty     = $false
    }
}

function Save-InstallLatestCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CacheState
    )

    if (-not [bool]$CacheState.Dirty) { return $false }

    $cacheFile = [string]$CacheState.CacheFile
    $tempFile = "$cacheFile.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = @($CacheState.Entries) | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempFile -Destination $cacheFile -Force -ErrorAction Stop
        $CacheState.Dirty = $false
        Write-Verbose -Message "EvergreenUI: Cache updated: '$cacheFile'."
        return $true
    }
    catch {
        # best-effort - cache write failure must not fail version resolution
        Write-Verbose -Message "EvergreenUI: Cache write failed for '$cacheFile' (ignored): $($_.Exception.Message)"
        if (Test-Path -LiteralPath $tempFile -PathType Leaf) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}
