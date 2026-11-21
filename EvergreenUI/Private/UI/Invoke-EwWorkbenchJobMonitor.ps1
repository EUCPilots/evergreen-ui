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
                    $State.LibraryDetailsText.Text = 'Select an application to view its library versions'
                    $State.LibraryVersionsListView.ItemsSource = @()
                    Write-EwWorkbenchLog -State $State -Message "Updated the library and loaded $(@($result.Items).Count) entries."
                }
            }
            'PackageDefinitions' {
                $result = $output | Select-Object -Last 1
                $State.PackageDefinitions.Clear()
                foreach ($definition in @($result.Items)) {
                    $State.PackageDefinitions.Add($definition)
                }
                $validCount = @($State.PackageDefinitions | Where-Object Status -eq 'Valid').Count
                $State.PackageDefinitionsCountLabel.Text = "$($State.PackageDefinitions.Count) definitions ($validCount valid)"
                $State.UpdatePackageDefinitionsButton.IsEnabled = $validCount -gt 0
                Write-EwWorkbenchLog -State $State -Message "Loaded $($State.PackageDefinitions.Count) Intune definitions ($validCount valid)."
            }
            'DefinitionUpdate' {
                $result = $output | Select-Object -Last 1
                foreach ($update in @($result.Results)) {
                    if ($update.Succeeded) {
                        $message = if ($update.NoUpdateNeeded) {
                            "$($update.Name) is already current at $($update.NewVersion)."
                        }
                        else {
                            "Updated $($update.Name) from $($update.OldVersion) to $($update.NewVersion)."
                        }
                        Write-EwWorkbenchLog -State $State -Message $message
                    }
                    else {
                        Write-EwWorkbenchLog -State $State -Message "Could not update $($update.Name): $($update.Error)" -Level Error
                    }
                }
                $State.PackageDefinitions.Clear()
                foreach ($definition in @($result.Items)) {
                    $State.PackageDefinitions.Add($definition)
                }
                $validCount = @($State.PackageDefinitions | Where-Object Status -eq 'Valid').Count
                $State.PackageDefinitionsCountLabel.Text = "$($State.PackageDefinitions.Count) definitions ($validCount valid)"
                $State.UpdatePackageDefinitionsButton.IsEnabled = $validCount -gt 0
            }
            'InstallDefinitions' {
                $State.InstallDefinitions.Clear()
                foreach ($definition in $output) {
                    $State.InstallDefinitions.Add($definition)
                }
                $validCount = @($State.InstallDefinitions | Where-Object DefinitionValid -eq 'Yes').Count
                $State.InstallDefinitionsCountLabel.Text = "$($State.InstallDefinitions.Count) definitions ($validCount valid)"
                $State.InstallActionStatusLabel.Text = 'Local detection complete. Find latest versions separately.'
                $State.ResolveInstallVersionsButton.IsEnabled = $validCount -gt 0
                Write-EwWorkbenchLog -State $State -Message "Checked local installation status for $validCount valid definitions."
            }
            'InstallVersions' {
                foreach ($versionResult in $output) {
                    $row = $State.InstallDefinitions |
                        Where-Object DefinitionPath -eq $versionResult.DefinitionPath |
                        Select-Object -First 1
                    if ($null -eq $row) {
                        continue
                    }
                    if (-not $versionResult.Succeeded) {
                        $row.LatestVersion = ''
                        $row.InstallStatus = 'Latest version unavailable'
                        $row.InstallAction = 'Retry lookup'
                        $row.Error = [string]$versionResult.Error
                        Write-EwWorkbenchLog -State $State -Message "Could not resolve latest version for $($row.Name): $($row.Error)" -Level Error
                        continue
                    }
                    $row.LatestVersion = [string]$versionResult.LatestVersion
                    if (-not $row.IsInstalled) {
                        $row.InstallStatus = 'Not installed'
                        $row.InstallAction = 'Install'
                    }
                    elseif ($versionResult.IsCurrent) {
                        $row.InstallStatus = 'Installed (up to date)'
                        $row.InstallAction = 'No action'
                    }
                    elseif (-not $versionResult.VersionsComparable) {
                        $row.InstallStatus = 'Installed (version not comparable)'
                        $row.InstallAction = 'Review'
                    }
                    else {
                        $row.InstallStatus = 'Installed (update available)'
                        $row.InstallAction = 'Update'
                    }
                }
                $State.InstallDefinitionsListView.Items.Refresh()
                $State.InstallActionStatusLabel.Text = 'Latest-version lookup complete.'
                Write-EwWorkbenchLog -State $State -Message 'Latest-version lookup completed.'
            }
            'InstallPackages' {
                foreach ($installResult in $output) {
                    $row = $State.InstallDefinitions |
                        Where-Object DefinitionPath -eq $installResult.DefinitionPath |
                        Select-Object -First 1
                    if ($null -ne $row) {
                        if ($installResult.Succeeded) {
                            $row.IsInstalled = $true
                            $row.InstalledVersion = [string]$installResult.DownloadedVersion
                            $row.InstallStatus = 'Installed'
                            $row.InstallAction = 'Installed'
                            $row.Error = ''
                        }
                        else {
                            $row.InstallStatus = 'Installation failed'
                            $row.InstallAction = 'Retry install'
                            $row.Error = [string]$installResult.Error
                        }
                    }
                    if ($installResult.Succeeded) {
                        Write-EwWorkbenchLog -State $State -Message "Installed $($installResult.Name) $($installResult.DownloadedVersion)."
                    }
                    else {
                        Write-EwWorkbenchLog -State $State -Message "Installation failed for $($installResult.Name): $($installResult.Error)" -Level Error
                    }
                }
                $State.InstallDefinitionsListView.Items.Refresh()
                $State.InstallActionStatusLabel.Text = 'Selected installation batch completed.'
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
