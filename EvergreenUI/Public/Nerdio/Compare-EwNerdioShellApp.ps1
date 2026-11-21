Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Compare-EwNerdioShellApp {
    <#
    .SYNOPSIS
        Compares Nerdio Shell App definitions with Nerdio Manager.
    .DESCRIPTION
        Matches local Definition.json files to Nerdio Manager Shell Apps by
        publisher and name. For matched Evergreen definitions, it resolves the
        latest source version and reports whether a new Shell App version is
        needed.
    .PARAMETER DefinitionPath
        Folder containing Shell App definition folders.
    .PARAMETER ShellApp
        Shell Apps from Get-EwNerdioShellApp. Queried when not supplied.
    .EXAMPLE
        Compare-EwNerdioShellApp -DefinitionPath C:\Packages\ShellApps
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Action is Import for unmatched definitions and Update when a newer
        source version is available.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [psobject[]]$ShellApp
    )

    $definitions = @(Get-EwNerdioDefinition -Path $DefinitionPath)
    if (-not $PSBoundParameters.ContainsKey('ShellApp')) {
        $ShellApp = @(Get-EwNerdioShellApp)
    }
    $shellApps = @($ShellApp | Where-Object { $null -ne $_ })

    $keyOf = {
        param([string]$Publisher, [string]$Name)
        ('{0}|{1}' -f $Publisher.Trim(), $Name.Trim()).ToLowerInvariant()
    }
    $lookup = @{}
    foreach ($app in $shellApps) {
        $key = & $keyOf ([string]$app.Publisher) ([string]$app.Name)
        if (-not $lookup.ContainsKey($key)) {
            $lookup[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $lookup[$key].Add($app)
    }

    $sourceCache = @{}
    $matchedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($definition in $definitions) {
        $row = [PSCustomObject]@{
            RowType = 'Definition'
            DefinitionPath = $definition.DefinitionPath
            Publisher = $definition.Publisher
            AppName = $definition.AppName
            NerdioAppName = ''
            NerdioAppId = ''
            VersionCount = $null
            DefinitionValid = $definition.DefinitionValid
            MatchStatus = ''
            NerdioVersion = ''
            SourceVersion = ''
            UpdateRequired = ''
            Action = ''
            Message = ''
        }
        $rows.Add($row)

        if ($definition.DefinitionValid -ne 'Yes') {
            $row.MatchStatus = 'Invalid definition'
            continue
        }
        if ($definition.SourceType -ine 'Evergreen') {
            $row.MatchStatus = 'Unsupported source type'
            $row.Message = "Source type '$($definition.SourceType)' is not supported for compare."
            continue
        }

        $key = & $keyOf ([string]$definition.Publisher) ([string]$definition.AppName)
        $candidates = @(if ($lookup.ContainsKey($key)) { $lookup[$key] })
        if ($candidates.Count -eq 0) {
            $row.MatchStatus = 'No matching Shell App'
            $row.Action = 'Import'
            $row.Message = 'Definition has no match in Nerdio Manager.'
            continue
        }
        if ($candidates.Count -gt 1) {
            $row.MatchStatus = 'Duplicate matches'
            $row.Message = 'More than one Nerdio Shell App matched by publisher and name.'
            continue
        }

        $match = $candidates[0]
        $null = $matchedIds.Add([string]$match.Id)
        $row.NerdioAppName = [string]$match.Name
        $row.NerdioAppId = [string]$match.Id
        $row.VersionCount = $match.VersionCount
        $row.NerdioVersion = [string]$match.LatestVersion

        $cacheKey = '{0}|{1}' -f $definition.SourceApp.Trim(), $definition.SourceFilter.Trim()
        try {
            if (-not $sourceCache.ContainsKey($cacheKey)) {
                $sourceCache[$cacheKey] = Resolve-EwNerdioSource -Source $definition.DefinitionObject.source
            }
            $row.SourceVersion = [string]$sourceCache[$cacheKey].Version
        }
        catch {
            $row.MatchStatus = 'Matched (compare unavailable)'
            $row.UpdateRequired = 'Compare unavailable'
            $row.Message = "Source lookup failed: $($_.Exception.Message)"
            continue
        }

        $nerdioVersion = ConvertTo-EwComparableVersion -Version $row.NerdioVersion
        $sourceVersion = ConvertTo-EwComparableVersion -Version $row.SourceVersion
        if (-not $nerdioVersion.Success -or -not $sourceVersion.Success) {
            $row.MatchStatus = 'Matched (compare unavailable)'
            $row.UpdateRequired = 'Compare unavailable'
            $row.Message = "Unable to parse versions. Nerdio='$($row.NerdioVersion)' Source='$($row.SourceVersion)'"
            continue
        }
        if ($sourceVersion.Parsed -gt $nerdioVersion.Parsed) {
            $row.MatchStatus = 'Matched (update available)'
            $row.UpdateRequired = 'Yes'
            $row.Action = 'Update'
            $row.Message = 'Source version is newer than the Nerdio latest version.'
        }
        else {
            $row.MatchStatus = 'Matched (No update required)'
            $row.UpdateRequired = 'No'
            $row.Message = 'Nerdio latest version is current.'
        }
    }

    foreach ($app in $shellApps) {
        if ($matchedIds.Contains([string]$app.Id)) {
            continue
        }
        $rows.Add([PSCustomObject]@{
                RowType = 'Nerdio'
                DefinitionPath = ''
                Publisher = [string]$app.Publisher
                AppName = ''
                NerdioAppName = [string]$app.Name
                NerdioAppId = [string]$app.Id
                VersionCount = $app.VersionCount
                DefinitionValid = ''
                MatchStatus = 'No local definition'
                NerdioVersion = [string]$app.LatestVersion
                SourceVersion = ''
                UpdateRequired = ''
                Action = ''
                Message = 'Nerdio Shell App was not matched to a local definition.'
            })
    }

    $updates = @($rows | Where-Object { $_.Action -eq 'Update' }).Count
    $imports = @($rows | Where-Object { $_.Action -eq 'Import' }).Count
    Write-Verbose -Message "EvergreenUI: Nerdio compare complete: rows=$($rows.Count), update=$updates, import=$imports"

    $rows | Sort-Object -Property @{ Expression = {
            if ($_.Action -eq 'Import') { return 0 }
            if ($_.UpdateRequired -eq 'Yes') { return 1 }
            if ($_.UpdateRequired -eq 'Compare unavailable') { return 2 }
            if ($_.MatchStatus -eq 'Duplicate matches') { return 3 }
            if ($_.MatchStatus -eq 'Invalid definition') { return 4 }
            if ($_.MatchStatus -eq 'Unsupported source type') { return 5 }
            if ($_.RowType -eq 'Nerdio') { return 6 }
            return 7
        }
    }, Publisher, AppName, RowType, NerdioAppId
}
