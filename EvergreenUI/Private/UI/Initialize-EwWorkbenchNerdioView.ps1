Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchNerdioView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    $State.NerdioPlan = $null
    $State.NerdioDestination = $null
    $State.NerdioAzureIdentity = $null
    $State.NerdioCancellation = $null
    $State.AllowNerdioEvents = $false
    $State.NerdioResults = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $State.NerdioPublishResultsListView.ItemsSource = $State.NerdioResults
    $State.NerdioBlockedOutcomes = @{}
    $State.NerdioPruningOffers = @()
    $State.NerdioRecoveryError = ''
    $State.NerdioSelectedPrunePlans = @()
    $State.NerdioPruneSelectionId = ''
    $State.NerdioSettingControls = @{
        NerdioTenantId = $State.NerdioTenantIdBox
        NmeSubscriptionId = $State.NmeSubscriptionIdBox
        NmeHost = $State.NmeHostBox
        NmeClientId = $State.NmeClientIdBox
        NmeApiScope = $State.NmeApiScopeBox
        NmeOAuthTokenUrl = $State.NmeOAuthTokenUrlBox
        NerdioDefinitionsPath = $State.NerdioDefinitionsPathBox
        NmeResourceGroup = $State.NmeResourceGroupCombo
        NmeStorageAccount = $State.NmeStorageAccountCombo
        NmeContainer = $State.NmeContainerCombo
    }
    foreach ($name in $State.NerdioSettingControls.Keys) {
        $control = $State.NerdioSettingControls[$name]
        if ($control -is [System.Windows.Controls.TextBox]) {
            $control.Text = [string]$State.Settings[$name]
            $azureChanged = $name -in @('NerdioTenantId', 'NmeSubscriptionId')
            $connectionChanged = $name -ne 'NerdioDefinitionsPath'
            $control.Add_TextChanged({
                if ($State.AllowNerdioEvents) {
                    & $State.ModuleInvoker -Name 'Clear-EwWorkbenchNerdioComparison' -Parameters @{ State = $State; AzureChanged = $azureChanged; ConnectionChanged = $connectionChanged }
                }
            }.GetNewClosure())
        }
    }
    $actions = @{
        ConnectNerdioAzureButton = 'AzureConnect'; DisconnectNerdioButton = 'Disconnect'
        ConnectNerdioButton = 'ApiConnect'; CompareNerdioButton = 'Compare'
        SaveNerdioSettingsButton = 'Save'; SaveNerdioSetupButton = 'Save'; BrowseNerdioDefinitionsButton = 'Browse'
        PublishSelectedNerdioButton = 'Publish'; CancelNerdioBatchButton = 'Cancel'
        ReviewNerdioOutcomeButton = 'Review'
        PruneNerdioVersionsButton = 'Prune'
        PruneSelectedNerdioVersionsButton = 'PruneExisting'
    }
    foreach ($name in $actions.Keys) {
        $action = $actions[$name]
        $State[$name].Add_Click({
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioAction' -Parameters @{ State = $State; Action = $action }
        }.GetNewClosure())
    }
    $State.NmeResourceGroupCombo.Add_SelectionChanged({
        if ($State.AllowNerdioEvents) {
            & $State.ModuleInvoker -Name 'Clear-EwWorkbenchNerdioComparison' -Parameters @{ State = $State }
            $State.AllowNerdioEvents = $false
            $State.NmeStorageAccountCombo.ItemsSource = @()
            $State.NmeContainerCombo.ItemsSource = @()
            $State.AllowNerdioEvents = $true
            if ($State.NmeResourceGroupCombo.SelectedItem) {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioAction' -Parameters @{ State = $State; Action = 'Storage' }
            }
        }
    }.GetNewClosure())
    $State.NmeStorageAccountCombo.Add_SelectionChanged({
        if ($State.AllowNerdioEvents) {
            & $State.ModuleInvoker -Name 'Clear-EwWorkbenchNerdioComparison' -Parameters @{ State = $State }
            $State.AllowNerdioEvents = $false
            $State.NmeContainerCombo.ItemsSource = @()
            $State.AllowNerdioEvents = $true
            if ($State.NmeStorageAccountCombo.SelectedItem) {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioAction' -Parameters @{ State = $State; Action = 'Containers' }
            }
        }
    }.GetNewClosure())
    $State.NmeContainerCombo.Add_SelectionChanged({
        if ($State.AllowNerdioEvents) {
            & $State.ModuleInvoker -Name 'Clear-EwWorkbenchNerdioComparison' -Parameters @{ State = $State }
        }
    }.GetNewClosure())
    $State.NerdioComparisonListView.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioBusyState' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.NerdioApiOnlyToggle.Add_Click({
        & $State.ModuleInvoker -Name 'Clear-EwWorkbenchNerdioComparison' -Parameters @{ State = $State; ConnectionChanged = $true }
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioBusyState' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.NerdioPublishResultsListView.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchNerdioBusyState' -Parameters @{ State = $State }
    }.GetNewClosure())
    Sync-EwWorkbenchNerdioRecoveryState -State $State | Out-Null
    $State.AllowNerdioEvents = $true
    Invoke-EwWorkbenchNerdioBusyState -State $State
}
