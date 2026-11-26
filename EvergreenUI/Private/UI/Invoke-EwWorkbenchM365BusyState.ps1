Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchM365BusyState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    if (-not $State.Contains('M365Views')) { return }
    $idle = $null -eq $State.ActiveJobId
    foreach ($provider in 'Intune', 'Nerdio') {
        $view = $State.M365Views[$provider]
        foreach ($suffix in 'BrowseButton', 'PathBox', 'LoadButton', 'SaveButton', 'ConfigurationCombo',
            'ChannelCombo', 'CompanyBox', 'SessionCombo', 'TargetsButton', 'TargetCombo',
            'PreviewBuildButton', 'PreviewPublishButton') {
            $view[$suffix].IsEnabled = $idle
        }
        $view.BuildButton.IsEnabled = $idle -and $null -ne $view.BuildPlan
        $view.PublishButton.IsEnabled = $idle -and $null -ne $view.PublishPlan
        $view.CancelButton.IsEnabled = -not $idle -and $State.M365ActiveProvider -eq $provider -and
            $null -ne $State.M365Cancellation -and -not $State.M365Cancellation.IsCancellationRequested
    }
    foreach ($name in 'NerdioM365OperationCombo', 'NerdioM365NameBox', 'NerdioM365AttestToggle',
        'IntuneM365RecoveryCombo', 'IntuneM365RecoveryLoadButton', 'IntuneM365ReviewButton') {
        $State[$name].IsEnabled = $idle
    }
    $selected = $State.NerdioM365RecoveryList.SelectedItem
    $key = if ($null -ne $selected) { [string](Get-EwFirstPropertyValue -InputObject $selected -Name 'OutcomeKey') } else { '' }
    $State.NerdioM365AcknowledgeButton.IsEnabled = $idle -and $key -and $State.NerdioBlockedOutcomes.ContainsKey($key)
}
