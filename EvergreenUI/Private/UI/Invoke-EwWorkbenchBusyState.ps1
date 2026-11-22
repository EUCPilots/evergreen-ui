Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchBusyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [bool]$IsBusy
    )

    foreach ($button in @(
            $State.RefreshAppsButton,
            $State.FavoriteAppButton,
            $State.QueueDownloadButton,
            $State.BrowseOutputPathButton,
            $State.SetOutputPathButton,
            $State.RemoveQueuedDownloadButton,
            $State.ClearQueueButton,
            $State.StartDownloadButton,
            $State.BrowseLibraryPathButton,
            $State.SetLibraryPathButton,
            $State.LoadLibraryButton,
            $State.UpdateLibraryButton,
            $State.BrowseIntuneDefinitionsButton,
            $State.SaveIntuneDefinitionsPathButton,
            $State.LoadPackageDefinitionsButton,
            $State.UpdatePackageDefinitionsButton,
            $State.BrowsePackageOutputPathButton,
            $State.SavePackageOutputPathButton,
            $State.ReloadInstallDefinitionsButton,
            $State.ResolveInstallVersionsButton,
            $State.InstallSelectedPackagesButton,
            $State.ConnectIntuneButton,
            $State.DisconnectIntuneButton,
            $State.CompareIntuneButton,
            $State.PublishSelectedIntuneButton,
            $State.RetryIntuneSupersedenceButton
        )) {
        if ($null -ne $button) {
            $button.IsEnabled = -not $IsBusy
        }
    }
    $State.AppsListView.IsEnabled = -not $IsBusy
    $State.PackageDefinitionsListView.IsEnabled = -not $IsBusy
    $State.InstallDefinitionsListView.IsEnabled = -not $IsBusy
    $State.IntuneComparisonListView.IsEnabled = -not $IsBusy
    $State.IntuneTenantIdBox.IsEnabled = -not $IsBusy
    $State.UseIntuneDeviceCodeToggle.IsEnabled = -not $IsBusy
    $State.CancelIntuneBatchButton.IsEnabled = $IsBusy -and $State.ActiveJobKind -eq 'IntunePublish'
    $State.JobProgressBar.Visibility = if ($IsBusy) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    if (-not $IsBusy) {
        $State.JobProgressBar.IsIndeterminate = $false
        $State.JobProgressBar.Value = 0
        $State.FavoriteAppButton.IsEnabled = $null -ne $State.AppsListView.SelectedItem
        $State.QueueDownloadButton.IsEnabled = $State.ArtifactsGrid.SelectedItems.Count -gt 0
        $State.StartDownloadButton.IsEnabled = @($State.Queue | Where-Object Status -eq 'Pending').Count -gt 0
        $State.LoadPackageDefinitionsButton.IsEnabled = -not [string]::IsNullOrWhiteSpace([string]$State.IntuneDefinitionsPathBox.Text)
        $State.UpdatePackageDefinitionsButton.IsEnabled = @($State.PackageDefinitions | Where-Object Status -eq 'Valid').Count -gt 0
        $validInstallDefinitions = @($State.InstallDefinitions | Where-Object DefinitionValid -eq 'Yes')
        $State.ResolveInstallVersionsButton.IsEnabled = $validInstallDefinitions.Count -gt 0
        $selectedInstallDefinitions = @($State.InstallDefinitionsListView.SelectedItems |
            Where-Object DefinitionValid -eq 'Yes')
        $State.InstallSelectedPackagesButton.IsEnabled = $selectedInstallDefinitions.Count -gt 0
        $connected = -not [string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId)
        $State.DisconnectIntuneButton.IsEnabled = $connected
        $State.CompareIntuneButton.IsEnabled = $connected
        $State.PublishSelectedIntuneButton.IsEnabled = $connected -and $State.IntuneComparisonListView.SelectedItems.Count -gt 0
        $selectedResult = $State.IntunePublishResultsListView.SelectedItem
        $State.RetryIntuneSupersedenceButton.IsEnabled = $connected -and $null -ne $selectedResult -and
            $selectedResult.Status -eq 'Supersedence failed' -and $selectedResult.TenantId -eq $State.IntuneTenantId
    }
    Invoke-EwWorkbenchNerdioBusyState -State $State
}
