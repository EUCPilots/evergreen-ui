Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchJobMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    if ($null -eq $State.ActiveJobId) {
        return
    }
    try {
        $job = Get-EwJob -Id $State.ActiveJobId
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not read the active job: $($_.Exception.Message)" -Level Error
        $State.ActiveJobId = $null
        $State.ActiveJobKind = ''
        Invoke-EwWorkbenchBusyState -State $State -IsBusy $false
        return
    }

    while ($State.ProgressReadIndex -lt $job.Progress.Count) {
        $progress = $job.Progress[$State.ProgressReadIndex]
        $State.ProgressReadIndex++
        $State.StatusLabel.Text = $progress.Activity
        if ($progress.PercentComplete -ge 0) {
            $State.JobProgressBar.IsIndeterminate = $false
            $State.JobProgressBar.Value = $progress.PercentComplete
        }
        else {
            $State.JobProgressBar.IsIndeterminate = $true
        }
    }
    while ($State.InformationReadIndex -lt $job.Information.Count) {
        $information = $job.Information[$State.InformationReadIndex]
        $State.InformationReadIndex++
        Write-EwWorkbenchLog -State $State -Message ([string]$information.MessageData)
    }
    while ($State.ErrorReadIndex -lt $job.Errors.Count) {
        $errorRecord = $job.Errors[$State.ErrorReadIndex]
        $State.ErrorReadIndex++
        Write-EwWorkbenchLog -State $State -Message $errorRecord.Exception.Message -Level Error
    }
    if ($job.State -in @('NotStarted', 'Running', 'Stopping')) {
        return
    }

    $kind = [string]$State.ActiveJobKind
    $output = @($job.Output)
    if ($null -ne $job.TerminatingError) {
        if ($kind -eq 'Apps') {
            $State.AppsLoading = $false
        }
        if ($kind -eq 'Downloads') {
            foreach ($item in $State.Queue | Where-Object Status -eq 'Downloading') {
                $item.Status = 'Failed'
            }
            $State.DownloadQueueListView.Items.Refresh()
        }
        if ($job.Errors.Count -eq 0) {
            Write-EwWorkbenchLog -State $State -Message $job.TerminatingError.Exception.Message -Level Error
        }
    }
    elseif ($job.State -eq 'Completed') {
        switch ($kind) {
            'Apps' {
                $State.AppsLoading = $false
                $State.AppCatalog = @($output)
                Invoke-EwWorkbenchAppList -State $State
                Write-EwWorkbenchLog -State $State -Message "Loaded $($State.AppCatalog.Count) applications."
            }
            'Artifacts' {
                $State.AllArtifacts = @($output)
                $State.SelectedAppText.Text = "$($State.CurrentApp.FriendlyName) ($($State.CurrentApp.Name))"
                Invoke-EwWorkbenchArtifactList -State $State -RebuildFilters
                Write-EwWorkbenchLog -State $State -Message "Loaded $($State.AllArtifacts.Count) artifacts for $($State.CurrentApp.Name)."
            }
            'Downloads' {
                foreach ($result in $output) {
                    $item = $State.Queue | Where-Object { $_.Id -eq $result.QueueId } | Select-Object -First 1
                    if ($null -ne $item) {
                        $item.Status = if ($result.Succeeded) { 'Downloaded' } else { 'Failed' }
                        $item.SavedPath = [string]$result.Path
                    }
                    $level = if ($result.Succeeded) { 'Info' } else { 'Error' }
                    $message = if ($result.Succeeded) {
                        "Downloaded $($result.AppName) $($result.Version) to $($result.Path)."
                    }
                    else {
                        "Download failed for $($result.AppName) $($result.Version): $($result.Error)"
                    }
                    Write-EwWorkbenchLog -State $State -Message $message -Level $level
                }
                $State.DownloadQueueListView.Items.Refresh()
            }
            'Library' {
                $State.LibraryListView.ItemsSource = [object[]]$output
                Write-EwWorkbenchLog -State $State -Message "Loaded $($output.Count) library entries."
            }
            'LibraryUpdate' {
                $result = $output | Select-Object -Last 1
                if ($null -ne $result) {
                    $State.LibraryListView.ItemsSource = [object[]]@($result.Items)
                    Write-EwWorkbenchLog -State $State -Message "Updated the library and loaded $(@($result.Items).Count) entries."
                }
            }
        }
    }
    else {
        if ($kind -eq 'Apps') {
            $State.AppsLoading = $false
        }
        Write-EwWorkbenchLog -State $State -Message "Background operation finished with state '$($job.State)'." -Level Error
    }

    try {
        Remove-EwJob -Id $job.Id -Confirm:$false
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not remove completed job $($job.Id): $($_.Exception.Message)" -Level Warning
    }
    $State.ActiveJobId = $null
    $State.ActiveJobKind = ''
    Invoke-EwWorkbenchBusyState -State $State -IsBusy $false
}
