Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntunePublishReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [object[]]$Selection,

        [Parameter(Mandatory)]
        [bool]$ImportAsUpdate
    )

    Write-Information -MessageData "Reviewing $($Selection.Count) selected Intune definitions before confirmation." -InformationAction Continue
    $comparison = @(Compare-EwIntuneApp -DefinitionPath $DefinitionPath -DefinitionView -NoCache -SelectedDefinitionPath @($Selection.DefinitionPath))
    $items = [System.Collections.Generic.List[object]]::new()
    $changed = $false
    foreach ($item in $Selection) {
        $fresh = @($comparison | Where-Object { $_.RowType -eq 'Definition' -and $_.DefinitionPath -eq $item.DefinitionPath })
        if ($fresh.Count -ne 1) { throw "Definition '$($item.DefinitionName)' is no longer a unique local definition." }
        $row = $fresh[0]
        if (-not $row.RelationshipsVerified -and $item.IntuneAppId -and $item.IntuneAppId -in @($row.MatchingApps | ForEach-Object IntuneAppId)) {
            Set-EwIntuneComparisonTarget -Row $row -AppId $item.IntuneAppId
        }
        $blocker = if ($ImportAsUpdate) { $row.UpdateBlocker } else { $row.DeploymentBlocker }
        if ($blocker) { throw "Cannot import '$($row.DefinitionName)': $blocker Refresh the comparison and review it." }
        foreach ($property in @('DefinitionHash', 'InstallHash', 'AvailableVersion', 'AvailableURI', 'MatchSnapshot', 'IntuneAppId')) {
            if ([string]$row.$property -cne [string]$item.$property) { $changed = $true }
        }
        $row.ImportAsUpdate = $ImportAsUpdate
        $row.IsSelected = $true
        $items.Add($row)
    }
    [PSCustomObject]@{ Items = @($items); Comparison = $comparison; Changed = $changed }
}
