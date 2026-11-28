Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwIntunePublishPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [object]$Item,

        [Parameter()]
        [switch]$AfterBuild
    )

    $rows = @(Compare-EwIntuneApp -DefinitionPath $DefinitionPath -DefinitionView -NoCache -SelectedDefinitionPath @($Item.DefinitionPath) |
        Where-Object { $_.RowType -eq 'Definition' -and $_.DefinitionPath -eq $Item.DefinitionPath })
    if ($rows.Count -ne 1) { throw 'The Intune match changed. Refresh the comparison and confirm a new import plan.' }
    $row = $rows[0]
    if (-not $row.RelationshipsVerified -and $Item.IntuneAppId -and $Item.IntuneAppId -in @($row.MatchingApps | ForEach-Object IntuneAppId)) {
        Set-EwIntuneComparisonTarget -Row $row -AppId $Item.IntuneAppId
    }
    $properties = @('AvailableVersion', 'AvailableURI', 'MatchSnapshot', 'IntuneAppId', 'IntuneVersion', 'PSPackageFactoryGuid', 'Architecture', 'RequirementArchitecture', 'AssignmentSummary')
    if (-not $AfterBuild) { $properties += 'DefinitionVersion' }
    foreach ($property in $properties) {
        if ([string]$row.$property -cne [string]$Item.$property) {
            throw "The Intune match or resolved artifact changed ($property). Refresh the comparison and confirm a new import plan."
        }
    }
    $blocker = if ($Item.ImportAsUpdate) { $row.UpdateBlocker } else { $row.DeploymentBlocker }
    if ($blocker) { throw "The import plan is no longer eligible: $blocker" }
}
