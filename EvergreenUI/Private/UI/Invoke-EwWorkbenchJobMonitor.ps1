Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchJobMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    if ($State.InstallPromptActive -or $State.MaintenancePromptActive) {
        return
    }
    Invoke-EwWorkbenchInfoJobMonitor -State $State
    if ($null -eq $State.ActiveJobId) {
        return
    }
    try {
        $job = Get-EwJob -Id $State.ActiveJobId
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not read the active job: $($_.Exception.Message)" -Level Error
        if ($State.ActiveJobKind -in @('NerdioPublish', 'M365', 'EvergreenUpdate', 'CacheClear')) {
            return
        }
        if ($State.ActiveJobKind -in @('MaintenanceCatalog', 'MaintenanceArtifacts')) {
            $unavailableJobId = $State.ActiveJobId
            $unavailableJob = [PSCustomObject]@{ State = 'Unknown'; TerminatingError = $_; Output = @() }
            try {
                $null = Invoke-EwWorkbenchMaintenanceJobResult -State $State -Kind $State.ActiveJobKind -Job $unavailableJob
                Write-EwWorkbenchLog -State $State -Message "Stopping and removing unusable read-only refresh job $unavailableJobId."
                try {
                    $null = Stop-EwJob -Id $unavailableJobId -Confirm:$false -ErrorAction Stop
                }
                catch {
                    Write-EwWorkbenchLog -State $State -Message "Could not stop unusable refresh job ${unavailableJobId}: $($_.Exception.Message)" -Level Warning
                }
                try {
                    Remove-EwJob -Id $unavailableJobId -Confirm:$false -ErrorAction Stop
                    Write-EwWorkbenchLog -State $State -Message "Removed unusable refresh job $unavailableJobId."
                }
                catch {
                    Write-EwWorkbenchLog -State $State -Message "Could not remove unusable refresh job ${unavailableJobId}: $($_.Exception.Message)" -Level Warning
                }
            }
            finally {
                $State.ActiveJobId = $null
                $State.ActiveJobKind = ''
                Invoke-EwWorkbenchBusyState -State $State -IsBusy $false
            }
            return
        }
        if ($State.ActiveJobKind -in @('InstallReview', 'InstallPackages') -and $State.InstallBatchActive) {
            $unavailableJob = [PSCustomObject]@{ State = 'Unknown'; TerminatingError = $null; Output = @() }
            $null = Invoke-EwWorkbenchInstallJobResult -State $State -Kind $State.ActiveJobKind -Job $unavailableJob
        }
        $State.ActiveJobId = $null
        $State.ActiveJobKind = ''
        Invoke-EwWorkbenchBusyState -State $State -IsBusy $false
        return
    }

    while ($State.ProgressReadIndex -lt $job.Progress.Count) {
        $progress = $job.Progress[$State.ProgressReadIndex]
        $State.ProgressReadIndex++
        $State.StatusLabel.Text = $progress.Activity
        if ($State.ActiveJobKind -in @('EvergreenUpdate', 'CacheClear', 'MaintenanceCatalog', 'MaintenanceArtifacts')) {
            Write-EwWorkbenchLog -State $State -Message "$($progress.Activity): $($progress.StatusDescription)"
        }
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
        $message = [string]$information.MessageData
        if ($State.ActiveJobKind -like 'Nerdio*' -or $State.ActiveJobKind -eq 'M365') { $message = $message -replace 'https?://\S+', '[URL omitted]' }
        Write-EwWorkbenchLog -State $State -Message $message
    }
    while ($State.ErrorReadIndex -lt $job.Errors.Count) {
        $errorRecord = $job.Errors[$State.ErrorReadIndex]
        $State.ErrorReadIndex++
        $message = $errorRecord.Exception.Message
        if ($State.ActiveJobKind -like 'Nerdio*' -or $State.ActiveJobKind -eq 'M365') { $message = $message -replace 'https?://\S+', '[URL omitted]' }
        Write-EwWorkbenchLog -State $State -Message $message -Level Error
    }
    if ($job.State -in @('NotStarted', 'Running', 'Stopping')) {
        return
    }

    $kind = [string]$State.ActiveJobKind
    $output = @($job.Output)
    $refreshIntune = $kind -in @('IntunePublish', 'IntuneRetry')
    $nextMaintenanceAction = ''
    if ($kind -in @('EvergreenUpdate', 'CacheClear', 'MaintenanceCatalog', 'MaintenanceArtifacts')) {
        $nextMaintenanceAction = Invoke-EwWorkbenchMaintenanceJobResult -State $State -Kind $kind -Job $job
    }
    elseif ($null -ne $job.TerminatingError) {
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
            $message = $job.TerminatingError.Exception.Message
            if ($kind -like 'Nerdio*' -or $kind -eq 'M365') { $message = $message -replace 'https?://\S+', '[URL omitted]' }
            Write-EwWorkbenchLog -State $State -Message $message -Level Error
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
                    if ($null -ne $versionResult.PSObject.Properties['Compatibility'] -and
                        $null -ne $versionResult.Compatibility) {
                        Set-EwWorkbenchInstallArchitecture -Row $row -Compatibility $versionResult.Compatibility -ArtifactResolved
                        if ($versionResult.Compatibility.Status -eq 'Blocked') {
                            $row.InstallStatus = 'Architecture blocked'
                            $row.InstallAction = 'Unavailable'
                            $row.Error = [string]$versionResult.Compatibility.Error
                            Write-EwWorkbenchLog -State $State -Message "Blocked installation for $($row.Name): $($row.Error)" -Level Warning
                            continue
                        }
                        $row.Error = ''
                    }
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
                [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.InstallDefinitions).Refresh()
                $State.InstallActionStatusLabel.Text = 'Latest-version lookup complete.'
                Write-EwWorkbenchLog -State $State -Message 'Latest-version lookup completed.'
            }
            'IntuneConnect' {
                $result = $output | Select-Object -Last 1
                if ($null -ne $result -and $result.Succeeded) {
                    $State.IntuneTenantId = [string]$result.TenantId
                    $State.IntuneConnectionStatusLabel.Text = "Connected: $($result.AccountId) / $($result.TenantId)"
                    Write-EwWorkbenchLog -State $State -Message "Connected to Intune tenant $($result.TenantId)."
                }
                else {
                    $State.IntuneTenantId = ''
                    $State.IntuneConnectionStatusLabel.Text = 'Not connected'
                    $message = if ($null -ne $result) { [string]$result.Error } else { 'No connection result returned.' }
                    Write-EwWorkbenchLog -State $State -Message "Intune sign-in failed: $message" -Level Error
                }
                $State.IntuneComparisonListView.ItemsSource = @()
            }
            'IntuneDisconnect' {
                $result = $output | Select-Object -Last 1
                if ($null -ne $result -and $result.Succeeded) {
                    $State.IntuneTenantId = ''
                    $State.IntuneConnectionStatusLabel.Text = 'Not connected'
                    $State.IntuneComparisonListView.ItemsSource = @()
                    Write-EwWorkbenchLog -State $State -Message 'Disconnected from Intune.'
                }
                else {
                    $message = if ($null -ne $result) { [string]$result.Error } else { 'No disconnect result returned.' }
                    Write-EwWorkbenchLog -State $State -Message "Intune disconnect failed: $message" -Level Error
                }
            }
            'IntuneCompare' {
                $result = $output | Select-Object -Last 1
                if ($null -ne $result) {
                    $State.IntuneComparisonRoot = [string]$result.DefinitionRoot
                    $State.IntuneComparison = @($result.Items)
                    $State.IntuneComparisonListView.ItemsSource = [object[]]$State.IntuneComparison
                    Write-EwWorkbenchLog -State $State -Message "Compared $($State.IntuneComparison.Count) Intune and Definition rows."
                }
            }
            'IntunePublish' {
                foreach ($result in $output) {
                    $result | Add-Member -NotePropertyName TenantId -NotePropertyValue ([string]$State.IntuneTenantId)
                    $State.IntuneResults.Add($result)
                    $level = if ($result.Succeeded) { 'Info' } elseif ($result.Status -eq 'Cancelled') { 'Warning' } else { 'Error' }
                    $details = if ($result.Error) { ": $($result.Error)" } else { '' }
                    Write-EwWorkbenchLog -State $State -Message "$($result.Name): $($result.Status)$details New app ID: $($result.IntuneAppId)" -Level $level
                    if (@($result.ChangedPaths).Count -gt 0) {
                        Write-EwWorkbenchLog -State $State -Message "Updated local files: $($result.ChangedPaths -join ', ')"
                    }
                }
                if ($null -ne $State.IntuneCancellation -and $State.IntuneCancellation.IsCancellationRequested) {
                    Write-EwWorkbenchLog -State $State -Message 'Intune batch stopped between Definitions.' -Level Warning
                }
            }
            'IntuneRetry' {
                $result = $output | Select-Object -Last 1
                if ($null -ne $result -and $result.Succeeded) {
                    $row = $State.IntuneResults | Where-Object {
                        $_.IntuneAppId -eq $result.NewAppId -and $_.PreviousAppId -eq $result.PreviousAppId
                    } | Select-Object -First 1
                    if ($null -ne $row) {
                        $row.Status = 'Published'
                        $row.Succeeded = $true
                        $row.Error = ''
                        $State.IntunePublishResultsListView.Items.Refresh()
                    }
                    Write-EwWorkbenchLog -State $State -Message "Supersedence linked for $($result.NewAppId)."
                }
                else {
                    $message = if ($null -ne $result) { [string]$result.Error } else { 'No retry result returned.' }
                    Write-EwWorkbenchLog -State $State -Message "Supersedence retry failed: $message" -Level Error
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

    $nextInstallAction = ''
    if ($kind -in @('InstallReview', 'InstallPackages') -and $State.InstallBatchActive) {
        $nextInstallAction = Invoke-EwWorkbenchInstallJobResult -State $State -Kind $kind -Job $job
    }
    $nextNerdioAction = ''
    if ($kind -eq 'M365') {
        Invoke-EwWorkbenchM365JobResult -State $State -Job $job
    }
    if ($kind -like 'Nerdio*') {
        $nextNerdioAction = Invoke-EwWorkbenchNerdioJobResult -State $State -Kind $kind -Job $job
    }
    try {
        Remove-EwJob -Id $job.Id -Confirm:$false
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not remove completed job $($job.Id): $($_.Exception.Message)" -Level Warning
        if ($nextMaintenanceAction) {
            Invoke-EwWorkbenchMaintenanceStale -State $State -Message "Could not clean up the completed maintenance job: $($_.Exception.Message)"
            $nextMaintenanceAction = ''
        }
    }
    $State.ActiveJobId = $null
    $State.ActiveJobKind = ''
    if ($kind -eq 'IntunePublish' -and $null -ne $State.IntuneCancellation) {
        $State.IntuneCancellation.Dispose()
        $State.IntuneCancellation = $null
    }
    Invoke-EwWorkbenchBusyState -State $State -IsBusy $false
    if ($nextMaintenanceAction) {
        Invoke-EwWorkbenchMaintenanceAction -State $State -Action $nextMaintenanceAction
    }
    if ($nextInstallAction) {
        try {
            Invoke-EwWorkbenchInstallAction -State $State -Action $nextInstallAction
        }
        catch {
            Write-EwWorkbenchLog -State $State -Message "Could not continue the installation batch: $($_.Exception.Message)" -Level Error
            $failedJob = [PSCustomObject]@{ State = 'Failed'; TerminatingError = $null; Output = @() }
            $failedKind = if ($nextInstallAction -eq 'Review') { 'InstallReview' } else { 'InstallPackages' }
            $null = Invoke-EwWorkbenchInstallJobResult -State $State -Kind $failedKind -Job $failedJob
        }
    }
    if ($nextNerdioAction) {
        Invoke-EwWorkbenchNerdioAction -State $State -Action $nextNerdioAction
    }
    if ($refreshIntune -and -not [string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId)) {
        try {
            Invoke-EwWorkbenchIntuneComparison -State $State
        }
        catch {
            Write-EwWorkbenchLog -State $State -Message "Could not refresh the Intune comparison: $($_.Exception.Message)" -Level Error
        }
    }
}
