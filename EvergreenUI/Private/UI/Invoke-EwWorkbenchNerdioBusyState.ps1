Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchNerdioBusyState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    $idle = $null -eq $State.ActiveJobId
    foreach ($control in $State.NerdioSettingControls.Values) { $control.IsEnabled = $idle }
    foreach ($name in 'UseNerdioDeviceCodeToggle', 'NmeClientSecretBox', 'ConnectNerdioAzureButton',
        'BrowseNerdioDefinitionsButton', 'SaveNerdioSettingsButton', 'NerdioComparisonListView') {
        $State[$name].IsEnabled = $idle
    }
    $State.NmeResourceGroupCombo.IsEnabled = $idle -and $null -ne $State.NerdioAzureIdentity
    $State.NmeStorageAccountCombo.IsEnabled = $idle -and $null -ne $State.NmeResourceGroupCombo.SelectedItem
    $State.NmeContainerCombo.IsEnabled = $idle -and $null -ne $State.NmeStorageAccountCombo.SelectedItem
    $State.ConnectNerdioButton.IsEnabled = $idle -and $null -ne $State.NerdioAzureIdentity -and
        $null -ne $State.NmeContainerCombo.SelectedItem
    $State.DisconnectNerdioButton.IsEnabled = $idle -and $null -ne $State.NerdioAzureIdentity
    $State.CompareNerdioButton.IsEnabled = $idle -and $null -ne $State.NerdioDestination
    $selection = @($State.NerdioComparisonListView.SelectedItems)
    $eligible = $selection.Count -gt 0 -and $State.NerdioBlockedOutcomes.Count -eq 0
    foreach ($row in $selection) {
        if (-not $row.Eligible) { $eligible = $false }
    }
    $State.PublishSelectedNerdioButton.IsEnabled = $idle -and $null -ne $State.NerdioPlan -and $eligible
    $State.CancelNerdioBatchButton.IsEnabled = -not $idle -and $State.ActiveJobKind -eq 'NerdioPublish' -and
        $null -ne $State.NerdioCancellation -and -not $State.NerdioCancellation.IsCancellationRequested
    $result = $State.NerdioPublishResultsListView.SelectedItem
    $State.ReviewNerdioOutcomeButton.IsEnabled = $idle -and $null -ne $result -and
        $result.Status -in @('Pending', 'Unknown') -and $State.NerdioBlockedOutcomes.ContainsKey($result.OutcomeKey)
}
