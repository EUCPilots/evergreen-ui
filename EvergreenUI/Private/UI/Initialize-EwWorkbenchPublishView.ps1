Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchPublishView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $State.IntuneTenantId = ''
    $State.IntuneComparison = @()
    $State.IntuneComparisonRoot = ''
    $State.IntuneComparisonLoaded = $false
    $State.IntuneResults = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $State.IntunePublishResultsListView.ItemsSource = $State.IntuneResults
    $State.IntuneCancellation = $null
    $State.IntunePendingPublish = $null
    $State.IntuneUpdatingInspector = $false
    $State.CompareIntuneButton.IsEnabled = $false
    $State.IntuneComparisonListView.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Update-EwWorkbenchIntuneView' -Parameters @{ State = $State }
    }.GetNewClosure())
    $selectionChanged = [System.Windows.RoutedEventHandler]{
        param($Control, $RoutedArgs)
        if ($Control -ne $State.IntuneComparisonListView) { return }
        $source = $RoutedArgs.OriginalSource
        if ($source -is [System.Windows.Controls.CheckBox] -and $source.IsLoaded -and $null -ne $source.DataContext) {
            $source.DataContext.IsSelected = [bool]$source.IsChecked
            & $State.ModuleInvoker -Name 'Update-EwWorkbenchIntuneView' -Parameters @{ State = $State }
        }
    }.GetNewClosure()
    $State.IntuneComparisonListView.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $selectionChanged)
    $State.IntuneComparisonListView.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $selectionChanged)
    $State.CloseIntuneDefinitionDrawerButton.Add_Click({
        $State.IntuneComparisonListView.SelectedItem = $null
        $null = $State.IntuneComparisonListView.Focus()
    }.GetNewClosure())
    $State.IntuneInventoryViewCombo.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Update-EwWorkbenchIntuneView' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.IntuneDefinitionSearchBox.Add_TextChanged({
        $query = [string]$State.IntuneDefinitionSearchBox.Text
        foreach ($control in @($State.IntuneComparisonListView, $State.IntuneOnlyAppsListView)) {
            if ($null -eq $control.ItemsSource) { continue }
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($control.ItemsSource)
            $view.Filter = {
                param($Item)
                $name = if ($Item.RowType -eq 'Definition') { $Item.DefinitionName } else { $Item.IntuneDisplayName }
                [string]::IsNullOrWhiteSpace($query) -or $name.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0
            }.GetNewClosure()
        }
    }.GetNewClosure())
    $State.IntunePredecessorCombo.Add_SelectionChanged({
        if ($State.IntuneUpdatingInspector) { return }
        $row = $State.IntuneComparisonListView.SelectedItem
        if ($null -eq $row) { return }
        try {
            & $State.ModuleInvoker -Name 'Set-EwIntuneComparisonTarget' -Parameters @{
                Row = $row; AppId = [string]$State.IntunePredecessorCombo.SelectedValue
            }
            $State.IntuneComparisonListView.Items.Refresh()
            & $State.ModuleInvoker -Name 'Update-EwWorkbenchIntuneView' -Parameters @{ State = $State }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not select the Intune predecessor: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.IntunePublishResultsListView.Add_SelectionChanged({
        $selected = $State.IntunePublishResultsListView.SelectedItem
        $State.RetryIntuneSupersedenceButton.IsEnabled = $null -ne $selected -and
            $selected.Status -eq 'Supersedence failed' -and $null -eq $State.ActiveJobId -and
            $State.IntuneTenantId -eq $selected.TenantId
    }.GetNewClosure())

    $State.ConnectIntuneButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId)) {
            try {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                    State = $State
                    Kind = 'IntuneDisconnect'
                    Name = 'Disconnect from Intune'
                    ScriptBlock = { Disconnect-EwIntune }
                }
            }
            catch {
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State; Message = "Could not disconnect Intune: $($_.Exception.Message)"; Level = 'Error'
                }
            }
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'IntuneConnect'
                Name = 'Connect to Intune'
                ScriptBlock = {
                    param($TenantId, $DeviceCode)
                    Connect-EwIntune -TenantId $TenantId -UseDeviceCode:([bool]$DeviceCode)
                }
                ArgumentList = @([string]$State.IntuneTenantIdBox.Text, [bool]$State.UseIntuneDeviceCodeToggle.IsChecked)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not start Intune sign-in: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.CompareIntuneButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchIntuneComparison' -Parameters @{ State = $State }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not compare Intune apps: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.PublishSelectedIntuneButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchIntunePublish' -Parameters @{
                State = $State; ImportAsUpdate = $false
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not review the deployment import: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.PublishIntuneUpdateButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchIntunePublish' -Parameters @{
                State = $State; ImportAsUpdate = $true
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not review the update import: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.CancelIntuneBatchButton.Add_Click({
        if ($null -ne $State.IntuneCancellation) {
            $State.IntuneCancellation.Cancel()
            $State.CancelIntuneBatchButton.IsEnabled = $false
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = 'Cancellation requested. The current Definition will finish first.'; Level = 'Warning'
            }
        }
    }.GetNewClosure())

    $State.RetryIntuneSupersedenceButton.Add_Click({
        $item = $State.IntunePublishResultsListView.SelectedItem
        if ($null -eq $item -or $item.Status -ne 'Supersedence failed' -or
            $State.IntuneTenantId -ne $item.TenantId) { return }
        $answer = & $State.ModuleInvoker -Name 'Confirm-EwWorkbenchAction' -Parameters @{
            Window = $State.Window
            Message = "Tenant: $($item.TenantId)`nNew app: $($item.IntuneAppId)`nPrevious app: $($item.PreviousAppId)`n`nRetry the supersedence link?"
            Title = 'Confirm supersedence retry'
            DefaultYes = $true
        }
        if (-not $answer) { return }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State; Kind = 'IntuneRetry'; Name = 'Retry Intune supersedence'
                ScriptBlock = {
                    param($NewId, $PreviousId, $TenantId)
                    Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
                    $context = Get-MgContext -ErrorAction Stop
                    if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
                        throw 'The confirmed Intune connection is no longer active.'
                    }
                    Set-EwIntuneSupersedence -NewAppId $NewId -PreviousAppId $PreviousId -SkipIfExists -Confirm:$false
                }
                ArgumentList = @([string]$item.IntuneAppId, [string]$item.PreviousAppId, [string]$item.TenantId)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not retry supersedence: $($_.Exception.Message)"; Level = 'Error'
            }
        }
    }.GetNewClosure())
}
