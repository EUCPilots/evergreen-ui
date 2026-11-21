#Requires -Version 5.1
<#
.SYNOPSIS
    Resolves the latest installer artifact for an App.json definition via its
    Application.Filter expression.

.DESCRIPTION
    Invokes the Evergreen or VcRedist filter command stored in
    Application.Filter and returns the highest-version artifact that matches
    the optional Architecture and Language hints.  Only Get-EvergreenApp and
    Get-VcList filter expressions are executed; any other expression causes an
    early failure.

.PARAMETER DefinitionObject
    The parsed App.json object (PSCustomObject) containing at minimum an
    Application.Filter property.

.OUTPUTS
    PSCustomObject with:
        Succeeded        : bool
        Version          : string  - resolved version string
        URI              : string  - resolved download URI
        ResolvedArtifact : object  - the full artifact row from the filter
        FilterExpression : string  - the expression that was evaluated
        Error            : string  - populated on failure

.EXAMPLE
    $def = Get-Content '.\App.json' | ConvertFrom-Json
    $result = Get-IntunePackageLatestVersion -DefinitionObject $def
    if ($result.Succeeded) { Write-Host "Latest: $($result.Version)" }
#>
function Get-IntunePackageLatestVersion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$DefinitionObject
    )

    $fail = {
        param([string]$Msg)
        return [PSCustomObject]@{
            Succeeded        = $false
            Version          = ''
            URI              = ''
            ResolvedArtifact = $null
            FilterExpression = ''
            Error            = $Msg
        }
    }

    if ($null -eq $DefinitionObject -or $null -eq $DefinitionObject.Application) {
        return (& $fail 'Definition object is null or has no Application property.')
    }

    $filterExpr = [string]$DefinitionObject.Application.Filter
    if ([string]::IsNullOrWhiteSpace($filterExpr)) {
        return (& $fail 'Application.Filter is empty or missing.')
    }

    # Safety gate: only Evergreen and VcRedist commands are permitted
    if ($filterExpr -notmatch 'Get-EvergreenApp|Get-VcList') {
        return (& $fail "Unsupported filter expression. Only Get-EvergreenApp and Get-VcList are supported. Got: $filterExpr")
    }

    $results = $null
    try {
        $results = @(Invoke-Expression -Command $filterExpr -ErrorAction Stop)
    }
    catch {
        return (& $fail "Filter execution failed: $($_.Exception.Message)")
    }

    if ($null -eq $results -or $results.Count -eq 0) {
        return (& $fail "Filter returned no results for expression: $filterExpr")
    }

    # Apply optional architecture and language preference from definition
    $preferredArch = [string]$DefinitionObject.Application.Architecture
    $preferredLang = [string]$DefinitionObject.Application.Language

    $filtered = @($results)

    if (-not [string]::IsNullOrWhiteSpace($preferredArch)) {
        $archFiltered = @($filtered | Where-Object {
                $_.PSObject.Properties.Name -contains 'Architecture' -and
                [string]$_.Architecture -ieq $preferredArch
            })
        if ($archFiltered.Count -gt 0) {
            $filtered = $archFiltered
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($preferredLang)) {
        $langFiltered = @($filtered | Where-Object {
                $_.PSObject.Properties.Name -contains 'Language' -and
                [string]$_.Language -ieq $preferredLang
            })
        if ($langFiltered.Count -gt 0) {
            $filtered = $langFiltered
        }
    }

    # Select the highest version artifact
    $best = $null
    foreach ($item in $filtered) {
        if ($null -eq $best) {
            $best = $item
            continue
        }

        $candidateRaw = ([string]$item.Version) -replace '^[^0-9]*', '' -replace '[^0-9\.]', ''
        $bestRaw      = ([string]$best.Version) -replace '^[^0-9]*', '' -replace '[^0-9\.]', ''

        if ([string]::IsNullOrWhiteSpace($candidateRaw) -or [string]::IsNullOrWhiteSpace($bestRaw)) {
            continue
        }

        try {
            if ([version]$candidateRaw -gt [version]$bestRaw) {
                $best = $item
            }
        }
        catch {
            # Keep existing best if version parse fails
        }
    }

    if ($null -eq $best) {
        return (& $fail 'No suitable artifact found after applying architecture/language filters.')
    }

    $uriValue = ''
    foreach ($uriPropName in @('URI', 'Uri', 'uri', 'URL', 'Url', 'url', 'DownloadUri', 'DownloadUrl')) {
        if ($best.PSObject.Properties.Name -contains $uriPropName -and
            -not [string]::IsNullOrWhiteSpace([string]$best.$uriPropName)) {
            $uriValue = [string]$best.$uriPropName
            break
        }
    }

    return [PSCustomObject]@{
        Succeeded        = $true
        Version          = [string]$best.Version
        URI              = $uriValue
        ResolvedArtifact = $best
        FilterExpression = $filterExpr
        Error            = ''
    }
}
