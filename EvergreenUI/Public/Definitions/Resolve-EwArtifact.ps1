Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EwArtifact {
    <#
    .SYNOPSIS
        Resolves the latest Evergreen artifact for an App.json definition.
    .DESCRIPTION
        Evaluates the definition's supported Evergreen query without executing
        the stored PowerShell text. Results are cached using the definition's
        SHA256 hash and expire after 24 hours by default.
    .PARAMETER DefinitionPath
        Path to an App.json definition.
    .PARAMETER CachePath
        Cache directory. Defaults to the user's local EvergreenWorkbench cache.
    .PARAMETER CacheMaxAgeHours
        Maximum age of a cached result. Use zero to always query Evergreen.
    .PARAMETER NoCache
        Queries Evergreen and skips cache reads and writes.
    .EXAMPLE
        Resolve-EwArtifact -DefinitionPath .\Definitions\Example\App.json
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports only Get-EvergreenApp, Get-VcList, simple Where-Object predicates,
        and Select-Object -First 1 in Application.Filter.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [ValidateRange(0, 8760)]
        [int]$CacheMaxAgeHours = 24,

        [Parameter()]
        [switch]$NoCache
    )

    $fail = {
        param([string]$Message, [string]$Filter = '')
        [PSCustomObject]@{
            Succeeded        = $false
            Version          = ''
            URI              = ''
            ResolvedArtifact = $null
            FilterExpression = $Filter
            Error            = $Message
            IsFromCache      = $false
            CacheFile        = ''
        }
    }

    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition file was not found: $DefinitionPath")
    }

    $filter = ''
    try {
        $definition = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $filter = [string]$definition.Application.Filter
        if ([string]::IsNullOrWhiteSpace($filter)) {
            return (& $fail 'Application.Filter is empty or missing.')
        }
        $query = ConvertFrom-EwDefinitionFilter -Filter $filter
    }
    catch {
        return (& $fail "Failed to parse definition filter: $($_.Exception.Message)" $filter)
    }

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        }
        $CachePath = Join-Path -Path $localAppData -ChildPath 'EvergreenWorkbench\Cache'
    }
    $cacheFile = Join-Path -Path $CachePath -ChildPath 'definition-artifact-cache.json'
    $definitionHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath
    $resolvedPath = [System.IO.Path]::GetFullPath($DefinitionPath)

    if (-not $NoCache -and $CacheMaxAgeHours -gt 0 -and (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
        try {
            $entries = @(Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop)
            $entry = $entries | Where-Object {
                [string]$_.DefinitionPath -ieq $resolvedPath -and
                [string]$_.DefinitionHash -eq $definitionHash
            } | Select-Object -First 1
            if ($null -ne $entry) {
                $retrievedAt = [DateTimeOffset]::MinValue
                $timestampValid = $false
                if ($entry.RetrievedAt -is [DateTimeOffset]) {
                    $retrievedAt = [DateTimeOffset]$entry.RetrievedAt
                    $timestampValid = $true
                }
                elseif ($entry.RetrievedAt -is [DateTime]) {
                    $retrievedAt = [DateTimeOffset]([DateTime]$entry.RetrievedAt)
                    $timestampValid = $true
                }
                else {
                    $timestampValid = [DateTimeOffset]::TryParse(
                        [string]$entry.RetrievedAt,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind,
                        [ref]$retrievedAt
                    )
                }
                if ($timestampValid) {
                    $age = [DateTimeOffset]::UtcNow - $retrievedAt.ToUniversalTime()
                    if ($age.TotalHours -le $CacheMaxAgeHours -and $age.TotalMinutes -ge 0) {
                        Write-Verbose -Message "EvergreenUI: Definition artifact cache hit (age: $([Math]::Round($age.TotalMinutes, 1)) minutes)."
                        return [PSCustomObject]@{
                            Succeeded        = [bool]$entry.Succeeded
                            Version          = [string]$entry.Version
                            URI              = [string]$entry.URI
                            ResolvedArtifact = $entry.ResolvedArtifact
                            FilterExpression = $filter
                            Error            = [string]$entry.Error
                            IsFromCache      = $true
                            CacheFile        = $cacheFile
                        }
                    }
                }
            }
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Definition artifact cache could not be read; querying Evergreen: $($_.Exception.Message)"
        }
    }

    try {
        $artifacts = @(Invoke-EwDefinitionQuery -Query $query)
        if ($null -ne $query.Predicate) {
            $artifacts = @($artifacts | Where-Object {
                [bool](Get-EwFilterLiteralValue -Expression $query.Predicate -Artifact $_)
            })
        }

        $application = $definition.Application
        $preferredArchitecture = if ($null -ne $application.PSObject.Properties['Architecture']) {
            [string]$application.Architecture
        } else { '' }
        $preferredLanguage = if ($null -ne $application.PSObject.Properties['Language']) {
            [string]$application.Language
        } else { '' }
        foreach ($preference in @(
            @{ Property = 'Architecture'; Value = $preferredArchitecture }
            @{ Property = 'Language'; Value = $preferredLanguage }
        )) {
            if (-not [string]::IsNullOrWhiteSpace($preference.Value)) {
                $preferredMatches = @($artifacts | Where-Object {
                    $null -ne $_.PSObject.Properties[$preference.Property] -and
                    [string]$_.PSObject.Properties[$preference.Property].Value -ieq $preference.Value
                })
                if ($preferredMatches.Count -gt 0) {
                    $artifacts = $preferredMatches
                }
            }
        }

        if ($artifacts.Count -eq 0) {
            throw 'Application.Filter did not return any artifacts.'
        }

        $best = $null
        $bestVersion = [version]'0.0'
        foreach ($artifact in $artifacts) {
            $versionText = ([string]$artifact.Version) -replace '^[^0-9]*', '' -replace '[^0-9\.].*$', ''
            $candidateVersion = [version]'0.0'
            if ([version]::TryParse($versionText, [ref]$candidateVersion) -and
                ($null -eq $best -or $candidateVersion -gt $bestVersion)) {
                $best = $artifact
                $bestVersion = $candidateVersion
            }
            elseif ($null -eq $best) {
                $best = $artifact
            }
        }
        if ($null -eq $best) {
            throw 'No suitable artifact was found.'
        }

        $uri = ''
        foreach ($propertyName in @('URI', 'Uri', 'URL', 'Url', 'DownloadUri', 'DownloadUrl')) {
            $property = $best.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $uri = [string]$property.Value
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($uri)) {
            throw 'Resolved artifact does not contain a download URI.'
        }

        $result = [PSCustomObject]@{
            Succeeded        = $true
            Version          = [string]$best.Version
            URI              = $uri
            ResolvedArtifact = $best
            FilterExpression = $filter
            Error            = ''
            IsFromCache      = $false
            CacheFile        = $cacheFile
        }
    }
    catch {
        $result = & $fail "Artifact resolution failed: $($_.Exception.Message)" $filter
        $result.CacheFile = $cacheFile
    }

    if (-not $NoCache) {
        try {
            $null = New-Item -Path $CachePath -ItemType Directory -Force -ErrorAction Stop
            $entries = @()
            if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
                $entries = @(Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
            }
            $entries = @($entries | Where-Object {
                [string]$_.DefinitionPath -ine $resolvedPath
            })
            $entries += [PSCustomObject]@{
                DefinitionPath   = $resolvedPath
                DefinitionHash   = $definitionHash
                RetrievedAt      = [DateTimeOffset]::UtcNow.ToString('o')
                Succeeded        = $result.Succeeded
                Version          = $result.Version
                URI              = $result.URI
                ResolvedArtifact = $result.ResolvedArtifact
                Error            = $result.Error
            }
            Write-EwJsonFile -Path $cacheFile -InputObject @($entries)
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Definition artifact cache write failed: $($_.Exception.Message)"
        }
    }

    return $result
}
