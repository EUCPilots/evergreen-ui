Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwWorkbenchIntuneView {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates in-memory UI controls without changing provider or persistent state.')]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $inventory = $State.IntuneInventoryViewCombo.SelectedIndex -eq 1
    $connected = -not [string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId)
    $loaded = $connected -and $State.IntuneComparisonLoaded
    $State.IntuneComparisonInstructionText.Text = if (-not $connected) {
        'Connect to Intune, then select Compare definitions to see your apps.'
    } elseif ($State.ActiveJobKind -eq 'IntuneCompare' -and -not $loaded) {
        'Comparing definitions with Intune apps. This may take a few moments.'
    } elseif (-not $loaded) {
        'Select Compare definitions to see your definitions and Intune apps.'
    } else { '' }
    $State.IntuneComparisonInstructionText.Visibility = if ($loaded) { 'Collapsed' } else { 'Visible' }
    $State.IntuneBatchResultsPanel.Visibility = if ($State.IntuneResults.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $State.IntuneComparisonListView.Visibility = if ($loaded -and -not $inventory) { 'Visible' } else { 'Collapsed' }
    $State.IntuneOnlyAppsListView.Visibility = if ($loaded -and $inventory) { 'Visible' } else { 'Collapsed' }
    $row = $State.IntuneComparisonListView.SelectedItem
    $State.IntuneUpdatingInspector = $true
    try {
        $State.IntuneDefinitionDrawer.DataContext = $null
        $State.IntuneDefinitionDrawer.DataContext = $row
        $State.IntuneDefinitionDrawer.Visibility = if ($loaded -and $null -ne $row -and -not $inventory) { 'Visible' } else { 'Collapsed' }
        $State.IntunePredecessorCombo.ItemsSource = @(if ($null -ne $row) { $row.MatchingApps })
        $State.IntunePredecessorCombo.SelectedValue = if ($null -ne $row) { $row.IntuneAppId } else { $null }
        $State.IntunePredecessorPanel.Visibility = if ($null -ne $row -and $row.MatchingAppCount -gt 1 -and -not $row.RelationshipsVerified) { 'Visible' } else { 'Collapsed' }
        $State.IntuneNoMatchingAppsText.Visibility = if ($null -ne $row -and $row.MatchingAppCount -eq 0) { 'Visible' } else { 'Collapsed' }
    }
    finally {
        $State.IntuneUpdatingInspector = $false
    }
    $selection = @($State.IntuneComparison | Where-Object { $_.RowType -eq 'Definition' -and $_.IsSelected })
    $deployment = @($selection | Where-Object { -not [string]::IsNullOrWhiteSpace($_.DeploymentBlocker) })
    $updates = @($selection | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UpdateBlocker) })
    $ready = $null -eq $State.ActiveJobId -and -not [string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId) -and
        $selection.Count -gt 0 -and -not $inventory
    $State.PublishSelectedIntuneButton.IsEnabled = $ready -and $deployment.Count -eq 0
    $State.PublishIntuneUpdateButton.IsEnabled = $ready -and $updates.Count -eq 0
    $State.IntuneSelectionSummaryText.Text = if ($selection.Count) {
        "$($selection.Count) selected: $($selection.DefinitionName -join ', ')"
    } else { 'Select definitions using their checkboxes. Click a row to inspect all matching versions.' }
    $messages = @(
        foreach ($item in $deployment) { "Deployment import blocked for $($item.DefinitionName): $($item.DeploymentBlocker)" }
        foreach ($item in $updates) { "Update import blocked for $($item.DefinitionName): $($item.UpdateBlocker)" }
    )
    $State.IntuneImportBlockersText.Text = $messages -join "`n"
}
