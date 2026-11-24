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
    $State.IntuneResults = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $State.IntunePublishResultsListView.ItemsSource = $State.IntuneResults
    $State.IntuneCancellation = $null
    $State.CompareIntuneButton.IsEnabled = $false
    $State.IntuneComparisonListView.Add_SelectionChanged({
        $State.PublishSelectedIntuneButton.IsEnabled = $State.IntuneComparisonListView.SelectedItems.Count -gt 0 -and
            $null -eq $State.ActiveJobId -and -not [string]::IsNullOrWhiteSpace($State.IntuneTenantId)
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
        $null = $State.IntuneComparisonListView.CommitEdit()
        $null = $State.IntuneComparisonListView.CommitEdit()
        $selection = @($State.IntuneComparisonListView.SelectedItems)
        if ($selection.Count -eq 0) { return }
        foreach ($item in $selection) {
            if ($item.MatchStatus -notin @('No matching Win32 app', 'Matched (current)', 'Matched (update required)') -or
                ([bool]$item.ImportAsUpdate -and [string]::IsNullOrWhiteSpace([string]$item.IntuneAppId))) {
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State; Message = "Cannot publish '$($item.DefinitionName)': review its match and update-app selection."; Level = 'Warning'
                }
                return
            }
        }
        $root = [string]$State.IntuneComparisonRoot
        $working = [string]$State.Settings.PackageOutputPath
        if ([string]::IsNullOrWhiteSpace($working)) { $working = [string]$State.Settings.OutputPath }
        if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($working)) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = 'Save the Definition and package output paths in Packages first.'; Level = 'Warning'
            }
            return
        }
        if ($root -ne [string]$State.Settings.IntuneDefinitionsPath) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = 'The saved Definitions folder changed. Compare again before publishing.'; Level = 'Warning'
            }
            return
        }
        $confirmed = & $State.ModuleInvoker -Name 'Confirm-EwWorkbenchIntuneBatch' -Parameters @{
            Window = $State.Window; Selection = [object[]]$selection; TenantId = [string]$State.IntuneTenantId
        }
        if (-not $confirmed) { return }
        $State.IntuneCancellation = [System.Threading.CancellationTokenSource]::new()
        $arguments = [object[]]::new(5)
        $arguments[0] = $root
        $arguments[1] = [object[]]$selection
        $arguments[2] = $working
        $arguments[3] = [string]$State.IntuneTenantId
        $arguments[4] = $State.IntuneCancellation.Token
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'IntunePublish'
                Name = 'Build and publish Intune apps'
                ScriptBlock = {
                    param($Root, $Selection, $WorkingPath, $TenantId, $CancellationToken)
                    Publish-EwIntuneBatch -DefinitionPath $Root -Selection $Selection -WorkingPath $WorkingPath `
                        -TenantId $TenantId -CancellationToken $CancellationToken -Confirm:$false
                }
                ArgumentList = $arguments
            }
        }
        catch {
            $State.IntuneCancellation.Dispose()
            $State.IntuneCancellation = $null
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State; Message = "Could not start Intune publishing: $($_.Exception.Message)"; Level = 'Error'
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
        $answer = [System.Windows.MessageBox]::Show($State.Window,
            "Tenant: $($item.TenantId)`nNew app: $($item.IntuneAppId)`nPrevious app: $($item.PreviousAppId)`n`nRetry the supersedence link?",
            'Confirm supersedence retry', [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
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
