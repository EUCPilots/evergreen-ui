Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Compare-EwIntuneApp {
    <#
    .SYNOPSIS
        Compares local App.json definitions with Intune Win32 apps.
    .DESCRIPTION
        Matches definitions to PSPackageFactory Win32 apps by the definition
        GUID stored in the app notes, then compares versions. Definitions with
        no matching app are returned as new import candidates.
    .PARAMETER DefinitionPath
        Folder containing App.json definitions.
    .PARAMETER IntuneApp
        Apps returned by Get-EwIntuneApp. When omitted, Intune is queried.
    .PARAMETER DefinitionView
        Returns one row per definition, with resolved import versions, all GUID
        matches, supersedence details and import blockers, plus Intune-only rows.
    .PARAMETER NoCache
        Refreshes artifact resolution for DefinitionView.
    .PARAMETER SelectedDefinitionPath
        Limits DefinitionView to these definition files while checking duplicate
        GUIDs across the root folder. Omits Intune-only inventory rows.
    .EXAMPLE
        Compare-EwIntuneApp -DefinitionPath C:\Packages\Apps
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        MatchStatus values: Matched (current), Matched (update required),
        Matched (needs review), No matching Win32 app, No local definition,
        Duplicate definition GUID, Duplicate Intune app GUID, Invalid notes JSON, Missing GUID in notes,
        Update app (managed), Superseded app (managed), or the definition validation status.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$IntuneApp,

        [Parameter()]
        [switch]$DefinitionView,

        [Parameter()]
        [switch]$NoCache,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$SelectedDefinitionPath
    )

    if ($DefinitionView) {
        if (-not $PSBoundParameters.ContainsKey('IntuneApp')) {
            $IntuneApp = @(Get-EwIntuneApp -IncludeUnmanaged)
        }
        $comparisonParameters = @{ DefinitionPath = $DefinitionPath; IntuneApp = $IntuneApp; NoCache = $NoCache }
        if ($PSBoundParameters.ContainsKey('SelectedDefinitionPath')) { $comparisonParameters.SelectedDefinitionPath = $SelectedDefinitionPath }
        return Get-EwIntuneDefinitionComparison @comparisonParameters
    }
    if ($PSBoundParameters.ContainsKey('SelectedDefinitionPath')) { throw 'SelectedDefinitionPath requires DefinitionView.' }
    $definitions = @(Get-EwDefinition -Path $DefinitionPath)
    if (-not $PSBoundParameters.ContainsKey('IntuneApp')) {
        $IntuneApp = @(Get-EwIntuneApp)
    }
    Write-Verbose -Message "EvergreenUI: Comparing $($definitions.Count) definitions with $(@($IntuneApp).Count) Intune apps"

    $lookup = @{}
    foreach ($definition in $definitions) {
        if ($definition.Status -ne 'Valid') {
            continue
        }
        $key = ([string]$definition.PSPackageFactoryGuid).Trim().ToLowerInvariant()
        if (-not $lookup.ContainsKey($key)) {
            $lookup[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $lookup[$key].Add($definition)
    }
    $groups = @{}
    foreach ($app in @($IntuneApp)) {
        if ($null -eq $app -or [bool]$app.IsUpdateApp -or [string]$app.NotesValid -ne 'Yes') {
            continue
        }
        $key = ([string]$app.NotesGuid).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            if (-not $groups.ContainsKey($key)) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
            $groups[$key].Add($app)
        }
    }
    $supersededIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $groups.Values) {
        if ($group.Count -lt 2) { continue }
        $chain = Get-EwIntuneSupersedenceState -App @($group)
        foreach ($id in $chain.SupersededAppIds) {
            $null = $supersededIds.Add([string]$id)
        }
    }
    $appCounts = @{}
    foreach ($key in $groups.Keys) {
        $appCounts[$key] = @($groups[$key] | Where-Object {
                -not $supersededIds.Contains([string]$_.IntuneAppId)
            }).Count
    }

    $architectureOf = {
        param([object]$Definition)
        $application = if ($null -ne $Definition.DefinitionObject) { $Definition.DefinitionObject.PSObject.Properties['Application'] } else { $null }
        if ($null -eq $application -or $null -eq $application.Value) { return '' }
        $architecture = $application.Value.PSObject.Properties['Architecture']
        if ($null -eq $architecture) { '' } else { [string]$architecture.Value }
    }
    $newRow = {
        param([string]$RowType, [object]$App, [object]$Definition, [string]$Status, [string]$UpdateRequired = 'Unknown', [string]$Action = '')
        [PSCustomObject]@{
            RowType = $RowType
            MatchStatus = $Status
            UpdateRequired = $UpdateRequired
            ImportAction = $Action
            IntuneAppId = if ($App) { [string]$App.IntuneAppId } else { '' }
            IntuneDisplayName = if ($App) { [string]$App.DisplayName } else { '' }
            IntuneVersion = if ($App) { [string]$App.DisplayVersion } else { '' }
            DefinitionName = if ($Definition) { [string]$Definition.Name } else { '' }
            DefinitionVersion = if ($Definition) { [string]$Definition.Version } else { '' }
            Publisher = if ($App -and -not [string]::IsNullOrWhiteSpace([string]$App.Publisher)) { [string]$App.Publisher } elseif ($Definition) { [string]$Definition.Publisher } else { '' }
            Architecture = if ($Definition) { & $architectureOf -Definition $Definition } else { '' }
            PSPackageFactoryGuid = if ($Definition) { [string]$Definition.PSPackageFactoryGuid } elseif ($App) { [string]$App.NotesGuid } else { '' }
            DefinitionPath = if ($Definition) { [string]$Definition.DefinitionPath } else { '' }
        }
    }

    $matchedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($app in @($IntuneApp)) {
        if ($null -eq $app) {
            continue
        }
        $key = ([string]$app.NotesGuid).Trim().ToLowerInvariant()
        if ([bool]$app.IsUpdateApp) {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'Update app (managed)'))
            continue
        }
        if ($supersededIds.Contains([string]$app.IntuneAppId)) {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'Superseded app (managed)'))
            continue
        }
        if ([string]$app.NotesValid -ne 'Yes') {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'Invalid notes JSON'))
            continue
        }
        if ([string]::IsNullOrWhiteSpace($key)) {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'Missing GUID in notes'))
            continue
        }
        $candidates = @(if ($lookup.ContainsKey($key)) { $lookup[$key] })
        if ($candidates.Count -eq 0) {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'No local definition'))
            continue
        }
        if ($candidates.Count -gt 1) {
            $rows.Add((& $newRow -RowType 'Intune' -App $app -Status 'Duplicate definition GUID' -Action 'Fix in definition'))
            continue
        }

        $definition = $candidates[0]
        $null = $matchedPaths.Add([string]$definition.DefinitionPath)
        if ($appCounts[$key] -gt 1) {
            $rows.Add((& $newRow -RowType 'Matched' -App $app -Definition $definition -Status 'Duplicate Intune app GUID' -Action 'Review Intune apps'))
            continue
        }
        $intuneVersion = ConvertTo-EwComparableVersion -Version ([string]$app.DisplayVersion)
        $definitionVersion = ConvertTo-EwComparableVersion -Version ([string]$definition.Version)
        if (-not $intuneVersion.Success -or -not $definitionVersion.Success) {
            $rows.Add((& $newRow -RowType 'Matched' -App $app -Definition $definition -Status 'Matched (needs review)'))
        }
        elseif ($definitionVersion.Parsed -gt $intuneVersion.Parsed) {
            $rows.Add((& $newRow -RowType 'Matched' -App $app -Definition $definition -Status 'Matched (update required)' `
                        -UpdateRequired 'Yes' -Action 'Import new version and supersede'))
        }
        else {
            $rows.Add((& $newRow -RowType 'Matched' -App $app -Definition $definition -Status 'Matched (current)' -UpdateRequired 'No'))
        }
    }

    foreach ($definition in $definitions) {
        if ($matchedPaths.Contains([string]$definition.DefinitionPath)) {
            continue
        }
        if ($definition.Status -ne 'Valid') {
            $rows.Add((& $newRow -RowType 'Definition' -Definition $definition -Status ([string]$definition.Status)))
            continue
        }
        $key = ([string]$definition.PSPackageFactoryGuid).Trim().ToLowerInvariant()
        if (@($lookup[$key]).Count -gt 1) {
            $rows.Add((& $newRow -RowType 'Definition' -Definition $definition -Status 'Duplicate definition GUID' -Action 'Fix in definition'))
        }
        else {
            $rows.Add((& $newRow -RowType 'Definition' -Definition $definition -Status 'No matching Win32 app' -Action 'Import new app'))
        }
    }

    $summary = $rows | Group-Object -Property MatchStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Verbose -Message "EvergreenUI: Intune comparison complete; $($summary -join ', ')"
    $rows | Sort-Object -Property @{ Expression = {
            if ($_.ImportAction -eq 'Import new app') { 0 }
            elseif ($_.UpdateRequired -eq 'Yes') { 1 }
            elseif ($_.UpdateRequired -eq 'Unknown' -and $_.RowType -eq 'Matched') { 2 }
            elseif ($_.RowType -eq 'Intune') { 3 }
            else { 4 }
        }
    }, Publisher, DefinitionName, IntuneDisplayName, PSPackageFactoryGuid
}
