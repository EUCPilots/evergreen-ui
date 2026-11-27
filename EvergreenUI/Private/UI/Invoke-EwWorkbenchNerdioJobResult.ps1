Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchNerdioJobResult {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][object]$Job
    )
    $output = @($Job.Output)
    $result = $output | Select-Object -Last 1
    $next = ''
    if ($Kind -eq 'NerdioPublish') {
        $known = @($output | ForEach-Object DefinitionPath)
        if ($Job.State -ne 'Completed' -or $null -ne $Job.TerminatingError) {
            foreach ($item in $State.NerdioInFlightSelections) {
                if ($item.DefinitionPath -notin $known) {
                    $output += [PSCustomObject]@{
                        Name = $item.AppName; DefinitionPath = $item.DefinitionPath; Version = $item.SourceVersion
                        Operation = $item.Operation; Succeeded = $false; Status = 'Unknown'
                        AppId = ''; JobId = ''; BlobName = ''; Error = 'Worker ended without a final result. Inspect Nerdio before another write.'
                    }
                }
            }
        }
        foreach ($item in $output) {
            $State.NerdioResults.Add($item)
            Write-EwWorkbenchLog -State $State -Message "$($item.Name): $($item.Status). $($item.Error)" `
                -Level $(if ($item.Succeeded) { 'Info' } else { 'Warning' })
        }
        $State.NerdioInFlightSelections = @()
        $State.NerdioPlan = $null
        $State.NerdioComparisonListView.ItemsSource = @()
        if ($null -ne $State.NerdioCancellation) {
            $State.NerdioCancellation.Dispose()
            $State.NerdioCancellation = $null
        }
        if ($null -ne $State.NerdioDestination) { $next = 'Compare' }
    }
    elseif ($Job.State -eq 'Completed' -and $null -eq $Job.TerminatingError) {
        $State.AllowNerdioEvents = $false
        try {
            switch ($Kind) {
                'NerdioAzureConnect' {
                    $State.NerdioAzureIdentity = $result.Identity
                    $State.NerdioConnectionStatusLabel.Text = if (
                        $null -ne $State.NerdioDestination -and
                        [bool](Get-EwFirstPropertyValue -InputObject $State.NerdioDestination -Name 'ApiOnly')
                    ) {
                        "Nerdio API connected: $($State.NerdioDestination.NmeHost). Azure: $($result.Identity.AccountId) / $($result.Identity.SubscriptionName). Select storage for Shell Apps."
                    } else {
                        "Azure: $($result.Identity.AccountId) / $($result.Identity.SubscriptionName). Select storage and connect the Nerdio API."
                    }
                    $State.NmeResourceGroupCombo.ItemsSource = [string[]]$result.Items
                    if ([string]$State.Settings.NmeResourceGroup -in @($result.Items)) {
                        $State.NmeResourceGroupCombo.SelectedItem = [string]$State.Settings.NmeResourceGroup
                        $next = 'Storage'
                    }
                }
                'NerdioStorage' {
                    $State.NmeStorageAccountCombo.ItemsSource = [string[]]$result.Items
                    if ([string]$State.Settings.NmeStorageAccount -in @($result.Items)) {
                        $State.NmeStorageAccountCombo.SelectedItem = [string]$State.Settings.NmeStorageAccount
                        $next = 'Containers'
                    }
                }
                'NerdioContainers' {
                    $State.NmeContainerCombo.ItemsSource = [string[]]$result.Items
                    if ([string]$State.Settings.NmeContainer -in @($result.Items)) {
                        $State.NmeContainerCombo.SelectedItem = [string]$State.Settings.NmeContainer
                        if ($null -ne $State.NerdioDestination -and $null -ne $State.NerdioAzureIdentity) { $next = 'BindStorage' }
                    }
                }
                'NerdioApiConnect' {
                    $State.NerdioPlan = $null
                    $State.NerdioComparisonListView.ItemsSource = @()
                    if ($null -ne $result -and $result.Succeeded) {
                        $State.NerdioDestination = $result
                        $State.NerdioConnectionStatusLabel.Text = if ([bool](Get-EwFirstPropertyValue -InputObject $result -Name 'ApiOnly')) {
                            if ($null -ne $State.NerdioAzureIdentity) {
                                "Nerdio API connected: $($result.NmeHost). Select Azure storage for Shell Apps."
                            } else {
                                "Nerdio API connected: $($result.NmeHost). Connect Azure and select storage for Shell Apps."
                            }
                        } else {
                            "Connected: $($result.NmeHost) / $($result.StorageAccountName) / $($result.ContainerName)"
                        }
                        if ($null -ne $State.NerdioAzureIdentity -and $State.NmeResourceGroupCombo.SelectedItem -and
                            $State.NmeStorageAccountCombo.SelectedItem -and $State.NmeContainerCombo.SelectedItem) { $next = 'BindStorage' }
                    }
                    else {
                        $State.NerdioDestination = $null
                        $State.NerdioConnectionStatusLabel.Text = 'Nerdio API connection failed'
                        $message = if ($null -eq $result) { 'No connection result.' } else { [string]$result.Error }
                        Write-EwWorkbenchLog -State $State -Message ($message -replace 'https?://\S+', '[URL omitted]') -Level Error
                    }
                }
                'NerdioBindStorage' {
                    $State.NerdioDestination = $result
                    $State.NerdioConnectionStatusLabel.Text = "Connected: $($result.NmeHost) / $($result.StorageAccountName) / $($result.ContainerName)"
                    Write-EwWorkbenchLog -State $State -Message 'Nerdio API and Azure storage are ready for Shell Apps.'
                }
                'NerdioCompare' {
                    $State.NerdioPlan = $result
                    foreach ($row in $result.Items) {
                        $publishBlocked = @($State.NerdioBlockedOutcomes.Values | Where-Object Type -eq 'Publish').Count -gt 0
                        $deleteBlocked = @($State.NerdioBlockedOutcomes.Values | Where-Object {
                                $_.Type -eq 'Delete' -and $_.AppId -eq [string]$row.NerdioAppId
                            }).Count -gt 0
                        if ($publishBlocked -or $deleteBlocked -or -not [string]::IsNullOrWhiteSpace($State.NerdioRecoveryError)) {
                            $row.Eligible = $false
                            $row.Operation = ''
                            $row.Message = 'Review the previous pending/unknown outcome in Nerdio before writing to this app.'
                        }
                    }
                    $State.NerdioComparisonListView.ItemsSource = [object[]]$result.Items
                    if ($State.NerdioPruneSelectionId) {
                        $selectedRow = $result.Items | Where-Object {
                            $_.NerdioAppId -eq $State.NerdioPruneSelectionId
                        } | Select-Object -First 1
                        if ($null -ne $selectedRow) { $State.NerdioComparisonListView.SelectedItem = $selectedRow }
                    }
                    Write-EwWorkbenchLog -State $State -Message "Loaded $(@($result.Items).Count) Nerdio comparison rows."
                }
                'NerdioDisconnect' {
                    if ($null -ne $result -and -not $result.Succeeded) {
                        Write-EwWorkbenchLog -State $State -Message $result.Error -Level Error
                    }
                }
                'NerdioReview' {
                    if ($null -ne $result -and $result.Succeeded) {
                        $State.NerdioPlan = $null
                        $State.NerdioComparisonListView.ItemsSource = @()
                        Clear-EwWorkbenchM365Preview -State $State -Provider 'Nerdio'
                        Write-EwWorkbenchLog -State $State -Message "Reviewed Nerdio outcome as $($result.Outcome); compare again before another publish."
                    }
                }
                'NerdioPrunePreview' {
                    if ($output.Count -eq 0) {
                        Write-EwWorkbenchLog -State $State -Message 'No Nerdio pruning previews were returned.' -Level Warning
                    }
                    else {
                        $selection = @(Show-EwWorkbenchNerdioPruneDialog -Owner $State.Window -Plans $output)
                        if ($selection.Count -gt 0) {
                            $State.NerdioSelectedPrunePlans = $selection
                            $next = 'PruneSelected'
                        }
                    }
                }
                'NerdioPruneSelected' {
                    foreach ($pruneResult in $output) {
                        Write-EwWorkbenchLog -State $State -Message (
                            "Pruned Shell App $($pruneResult.Id): removed $($pruneResult.RemovedCount), " +
                            "failed $($pruneResult.FailedCount), pending $(@($pruneResult.PendingVersions).Count), " +
                            "unknown $(@($pruneResult.UnknownVersions).Count)."
                        ) -Level $(if ($pruneResult.PendingVersions.Count -gt 0 -or $pruneResult.UnknownVersions.Count -gt 0 -or
                                $pruneResult.FailedCount -gt 0) { 'Warning' } else { 'Info' })
                    }
                }
            }
        }
        finally { $State.AllowNerdioEvents = $true }
    }
    if ($Kind -eq 'NerdioBindStorage' -and ($Job.State -ne 'Completed' -or $null -ne $Job.TerminatingError)) {
        $State.NerdioConnectionStatusLabel.Text = 'Could not connect the selected Azure storage. Check the activity log.'
    }
    if ($Kind -eq 'NerdioPruneSelected' -and $State.NerdioPruneSelectionId -and $null -ne $State.NerdioDestination) {
        $State.NerdioPlan = $null
        $State.NerdioComparisonListView.ItemsSource = @()
        $next = 'Compare'
    }
    if ($Kind -eq 'NerdioCompare') { $State.NerdioPruneSelectionId = '' }
    if ($Kind -in @('NerdioPublish', 'NerdioReview', 'NerdioPrunePreview', 'NerdioPruneSelected')) {
        Sync-EwWorkbenchNerdioRecoveryState -State $State | Out-Null
        Invoke-EwWorkbenchNerdioBusyState -State $State
    }
    return $next
}
