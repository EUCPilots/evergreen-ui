Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchM365View {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    $State.M365Views = @{}
    $State.M365SuppressEvents = $true
    $State.M365Cancellation = $null
    $State.M365ActiveProvider = ''
    $State.M365ActiveAction = ''
    foreach ($provider in 'Intune', 'Nerdio') {
        $view = @{
            Provider = $provider; BuildPlan = $null; PublishPlan = $null
        }
        foreach ($suffix in 'Form', 'BrowseButton', 'PathBox', 'LoadButton', 'SaveButton', 'ConfigurationCombo',
            'ChannelCombo', 'CompanyBox', 'SessionCombo', 'TargetsButton', 'TargetCombo', 'PreviewBuildButton',
            'PreviewPublishButton', 'PreviewText', 'BuildButton', 'PublishButton', 'CancelButton', 'ResultText') {
            $view[$suffix] = $State["${provider}M365$suffix"]
        }
        $State.M365Views[$provider] = $view
        $view.PathBox.Text = [string]$State.Settings.M365DefinitionsPath
        $view.CompanyBox.Text = [string]$State.Settings.M365CompanyName
        $view.ChannelCombo.ItemsSource = [string[]]@(
            'Current', 'MonthlyEnterprise', 'SemiAnnual', 'SemiAnnualPreview', 'CurrentPreview',
            'PerpetualVL2019', 'PerpetualVL2021', 'PerpetualVL2024'
        )
        $view.ChannelCombo.SelectedItem = [string]$State.Settings.M365Channel
        $view.SessionCombo.ItemsSource = [string[]]@('Single session', 'Multi-session')
        $view.SessionCombo.SelectedItem = [string]$State.Settings.M365ImportFor
        $actions = @{
            BrowseButton = 'Browse'; LoadButton = 'Load'; SaveButton = 'Save'; TargetsButton = 'Targets'
            PreviewBuildButton = 'PreviewBuild'; PreviewPublishButton = 'PreviewPublish'
            BuildButton = 'Build'; PublishButton = 'Publish'; CancelButton = 'Cancel'
        }
        foreach ($suffix in $actions.Keys) {
            $action = $actions[$suffix]
            $view[$suffix].Add_Click({
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchM365Action' -Parameters @{
                    State = $State; Provider = $provider; Action = $action
                }
            }.GetNewClosure())
        }
        foreach ($suffix in 'PathBox', 'CompanyBox') {
            $view[$suffix].Add_TextChanged({
                & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = $provider }
            }.GetNewClosure())
        }
        foreach ($suffix in 'ChannelCombo', 'SessionCombo', 'TargetCombo') {
            $view[$suffix].Add_SelectionChanged({
                & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = $provider }
            }.GetNewClosure())
        }
        $view.ConfigurationCombo.Add_SelectionChanged({
            if (-not $State.M365SuppressEvents) {
                $selected = $State.M365Views[$provider].ConfigurationCombo.SelectedItem
                if ($null -ne $selected) {
                    if ($selected.Channel -in @($State.M365Views[$provider].ChannelCombo.ItemsSource)) {
                        $State.M365Views[$provider].ChannelCombo.SelectedItem = [string]$selected.Channel
                    }
                    $State.M365Views[$provider].SessionCombo.SelectedItem = if ($selected.IsVdi) { 'Multi-session' } else { 'Single session' }
                    if ($provider -eq 'Nerdio') { $State.NerdioM365NameBox.Text = [string]$selected.DisplayName }
                }
                & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = $provider }
            }
        }.GetNewClosure())
    }
    $State.NerdioM365OperationCombo.ItemsSource = [string[]]@('Create', 'Add version')
    $State.NerdioM365OperationCombo.SelectedItem = 'Create'
    $State.NerdioM365OperationCombo.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = 'Nerdio' }
    }.GetNewClosure())
    $State.NerdioM365NameBox.Add_TextChanged({
        & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = 'Nerdio' }
    }.GetNewClosure())
    $State.NerdioM365AttestToggle.Add_Click({
        & $State.ModuleInvoker -Name 'Clear-EwWorkbenchM365Preview' -Parameters @{ State = $State; Provider = 'Nerdio' }
    }.GetNewClosure())
    foreach ($entry in @(
            @{ Name = 'IntuneM365RecoveryLoadButton'; Action = 'Recovery' },
            @{ Name = 'IntuneM365ReviewButton'; Action = 'Review' }
        )) {
        $action = $entry.Action
        $State[$entry.Name].Add_Click({
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchM365Action' -Parameters @{
                State = $State; Provider = 'Intune'; Action = $action
            }
        }.GetNewClosure())
    }
    $State.M365SuppressEvents = $false
    Invoke-EwWorkbenchM365BusyState -State $State
}
