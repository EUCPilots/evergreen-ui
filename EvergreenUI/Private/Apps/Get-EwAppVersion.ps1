Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAppVersion {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [switch]$NoCache,

        [Parameter()]
        [ValidateRange(0, 8760)]
        [int]$CacheMaxAgeHours = 24
    )

    $cacheEpoch = $null
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        Write-Verbose -Message "EvergreenUI: Application name '$Name' is not cacheable; querying Evergreen"
    }
    else {
        try {
            $snapshot = Invoke-EwAppVersionCache -Action Read -Name $Name -ErrorAction Stop
            $cacheEpoch = $snapshot.Epoch
            if ($NoCache) {
                Write-Verbose -Message "EvergreenUI: Application version cache bypassed for '$Name'"
            }
            elseif ($null -eq $snapshot.Entry) {
                Write-Verbose -Message "EvergreenUI: Application version cache miss for '$Name'"
            }
            else {
                $retrievedAt = [DateTimeOffset]::MinValue
                $valid = [DateTimeOffset]::TryParse(
                    [string]$snapshot.Entry.RetrievedAt,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind,
                    [ref]$retrievedAt
                )
                $age = [DateTimeOffset]::UtcNow - $retrievedAt.ToUniversalTime()
                if ($valid -and $CacheMaxAgeHours -gt 0 -and $age.TotalMinutes -ge 0 -and $age.TotalHours -le $CacheMaxAgeHours) {
                    Write-Verbose -Message "EvergreenUI: Application version cache hit for '$Name' (age: $([Math]::Round($age.TotalMinutes, 1)) minutes)"
                    return @($snapshot.Entry.Artifacts)
                }
                Write-Verbose -Message "EvergreenUI: Application version cache for '$Name' expired or has an invalid timestamp; querying Evergreen"
            }
        }
        catch {
            $cacheEpoch = $null
            Write-Verbose -Message "EvergreenUI: Application version cache could not be read for '$Name'; querying Evergreen: $($_.Exception.Message)"
        }
    }

    $artifacts = @(Get-EvergreenApp -Name $Name -ErrorAction Stop)
    Write-Verbose -Message "EvergreenUI: Evergreen returned $($artifacts.Count) artifacts for '$Name'"
    if ($null -ne $cacheEpoch -and $artifacts.Count -gt 0) {
        try {
            Invoke-EwAppVersionCache -Action Write -Name $Name -Epoch $cacheEpoch -Artifacts $artifacts -ErrorAction Stop
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Application version cache write failed for '$Name': $($_.Exception.Message)"
        }
    }
    return $artifacts
}
