Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchDownloadTray {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    $pending = @($State.Queue | Where-Object Status -eq 'Pending').Count
    $downloading = @($State.Queue | Where-Object Status -eq 'Downloading').Count
    $finished = @($State.Queue | Where-Object Status -in @('Downloaded', 'Failed')).Count
    $activeDownload = $null -ne $State.ActiveJobId -and $State.ActiveJobKind -eq 'Downloads'
    $activeCount = $pending + $downloading

    $State.AppsQueueCountText.Text = [string]$activeCount
    $State.AppsQueueCountBadge.Visibility = if ($activeCount -gt 0) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    [System.Windows.Automation.AutomationProperties]::SetName(
        $State.NavApps,
        "Apps view, $activeCount pending or running downloads"
    )

    $State.DownloadDestinationText.Text = [string]$State.Settings.OutputPath
    $State.DownloadDestinationText.ToolTip = [string]$State.Settings.OutputPath
    $summary = @(
        if ($pending -gt 0) { "$pending pending" }
        if ($downloading -gt 0) { "$downloading downloading" }
        if ($finished -gt 0) { "$finished completed or failed" }
    ) -join ', '
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = 'empty'
    }
    $verb = if ([bool]$State.DownloadTrayToggleButton.IsChecked) { 'Hide' } else { 'Show' }
    $State.DownloadTrayToggleButton.Content = "$verb queue ($summary)"
    if ($State.Queue.Count -gt 0) {
        $State.DownloadTrayPanel.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $State.DownloadTrayPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $State.DownloadTrayToggleButton.IsChecked = $false
    }
    $trayExpanded = $State.Queue.Count -gt 0 -and [bool]$State.DownloadTrayToggleButton.IsChecked
    $State.DownloadTrayContent.Visibility = if ($trayExpanded) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    $State.DownloadTrayGridSplitter.Visibility = if ($trayExpanded) {
        [System.Windows.Visibility]::Visible
    }
    elseif ($State.Queue.Count -gt 0) {
        # Retain the splitter's spacing above the tray header while the table is hidden.
        [System.Windows.Visibility]::Hidden
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    if ($State.Queue.Count -eq 0) {
        $State.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::new(0)
    }
    elseif ($trayExpanded) {
        $trayRow = $State.AppsPanel.RowDefinitions[3]
        if ($trayRow.Height.IsAuto -or $trayRow.Height.Value -le 0) {
            $height = [int]$State.Settings.DownloadTrayHeight
            $trayRow.Height = [System.Windows.GridLength]::new($height)
        }
    }
    else {
        $State.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::Auto
    }
    $State.DownloadTrayActionButton.Content = if ($activeDownload) { 'Stop' } else { 'Download' }
    $State.DownloadTrayActionButton.IsEnabled = $activeDownload -or
        ($null -eq $State.ActiveJobId -and $pending -gt 0)
    $State.ClearCompletedQueueButton.IsEnabled = $finished -gt 0
    $canAddArtifacts = $State.ArtifactsGrid.SelectedItems.Count -gt 0 -and $null -eq $State.ActiveJobId
    $State.QueueDownloadButton.IsEnabled = $canAddArtifacts
    $State.DownloadNowButton.IsEnabled = $canAddArtifacts
}
