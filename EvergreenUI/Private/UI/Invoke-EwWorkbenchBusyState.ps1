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
            $State.UpdateLibraryButton
        )) {
        if ($null -ne $button) {
            $button.IsEnabled = -not $IsBusy
        }
    }
    $State.AppsListView.IsEnabled = -not $IsBusy
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
    }
}
