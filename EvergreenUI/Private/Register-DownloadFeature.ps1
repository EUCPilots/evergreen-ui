function Register-DownloadFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Download queue management feature.

    .DESCRIPTION
    Sets up event handlers for the Download navigation view, including queue display,
    item removal, queue clearing, and download execution. Manages the visual representation
    of pending, completed, and failed downloads.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Download feature.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls
    $removeQueueItemButton = $Controls.RemoveQueueItemButton
    $clearQueueButton = $Controls.ClearQueueButton
    $openDownloadFolderButton = $Controls.OpenDownloadFolderButton
    $outputPathBox = $Controls.OutputPathBox
    $SyncHash['NewWpfRunspace'] = ${function:New-WpfRunspace}.GetNewClosure()
    $SyncHash['SetListViewSort'] = ${function:Set-ListViewSort}.GetNewClosure()

    $downloadFeatureScriptPath = (Get-Command -Name Register-DownloadFeature -CommandType Function).ScriptBlock.File
    $privateRoot = if (-not [string]::IsNullOrWhiteSpace($downloadFeatureScriptPath)) {
        Split-Path -Path $downloadFeatureScriptPath -Parent
    }
    else {
        Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Private'
    }
    $formatLogEntryPath = Join-Path -Path $privateRoot -ChildPath 'Format-LogEntry.ps1'
    $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
    $invokeAppDownloadPath = Join-Path -Path $privateRoot -ChildPath 'Invoke-AppDownload.ps1'

    # Verify required controls exist
    if ($null -eq $SyncHash.DownloadQueueListView) {
        Write-Verbose 'EvergreenUI: DownloadQueueListView not found; Download feature registration skipped.'
        return
    }

    # Helper scriptblock: Normalize directory path (trim whitespace and quotes)
    $normalizeDirectoryPath = {
        param([string]$PathValue)

        if ([string]::IsNullOrWhiteSpace($PathValue)) {
            return ''
        }

        return $PathValue.Trim().Trim('"')
    }

    # Helper scriptblock: Refresh queue view display
    $refreshQueueView = {
        $SyncHash.DownloadQueueListView.ItemsSource = $null
        $SyncHash.DownloadQueueListView.ItemsSource = $SyncHash.DownloadQueue
        $SyncHash.DownloadQueueListView.Items.Refresh()

        $pending = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
        $done = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
        $failed = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
        $total = $SyncHash.DownloadQueue.Count
        $SyncHash.QueueCountLabel.Text = "Queue: $total items (Pending: $pending, Done: $done, Failed: $failed)"
    }

    # Helper scriptblock: Update DownloadAllButton enabled state
    $updateDownloadAllButtonState = {
        if ($null -eq $SyncHash.DownloadAllButton) {
            return
        }

        $pathValue = ''
        if ($null -ne $outputPathBox -and -not [string]::IsNullOrWhiteSpace([string]$outputPathBox.Text)) {
            $pathValue = [string]$outputPathBox.Text
        }
        elseif ($null -ne $SyncHash.Config -and $SyncHash.Config.PSObject.Properties.Name -contains 'OutputPath') {
            $pathValue = [string]$SyncHash.Config.OutputPath
        }

        $normalisedPathValue = if ([string]::IsNullOrWhiteSpace($pathValue)) { '' } else { $pathValue.Trim().Trim('"') }
        $hasOutputPath = -not [string]::IsNullOrWhiteSpace($normalisedPathValue)
        $hasQueueItems = $SyncHash.DownloadQueue.Count -gt 0

        $SyncHash.DownloadAllButton.IsEnabled = (-not $SyncHash.IsRunning) -and $hasQueueItems -and $hasOutputPath
    }

    # Helper scriptblock: Apply sort to download queue list
    $applyDownloadQueueSort = {
        [void](& ($SyncHash['SetListViewSort']) -ListView $SyncHash.DownloadQueueListView `
            -Property ([string]$SyncHash.DownloadQueueSortProperty) `
            -Direction ([string]$SyncHash.DownloadQueueSortDirection))
    }

    # Store helper scriptblocks in SyncHash for access by other features
    $SyncHash['RefreshQueueView'] = $refreshQueueView.GetNewClosure()
    $SyncHash['UpdateDownloadAllButtonState'] = $updateDownloadAllButtonState.GetNewClosure()
    $SyncHash['NormalizeDirectoryPath'] = $normalizeDirectoryPath.GetNewClosure()
    $SyncHash['ApplyDownloadQueueSort'] = $applyDownloadQueueSort.GetNewClosure()

    # Event handler: Remove selected queue item
    if ($null -ne $removeQueueItemButton) {
        $removeQueueItemButton.add_Click({
                if ($SyncHash.IsRunning) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Cannot remove queue items while downloads are running.' -Level Warning
                    return
                }

                $selectedQueueItem = $SyncHash.DownloadQueueListView.SelectedItem
                if ($null -eq $selectedQueueItem) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Select one queue item to remove.' -Level Warning
                    return
                }

                [void]$SyncHash.DownloadQueue.Remove($selectedQueueItem)
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Removed selected item from queue.' -Level Info
                & ($SyncHash['RefreshQueueView'])
            }.GetNewClosure())
    }

    # Event handler: Clear entire queue
    if ($null -ne $clearQueueButton) {
        $clearQueueButton.add_Click({
                if ($SyncHash.IsRunning) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Cannot clear queue while downloads are running.' -Level Warning
                    return
                }

                $SyncHash.DownloadQueue.Clear()
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Queue cleared.' -Level Info
                & ($SyncHash['RefreshQueueView'])
            }.GetNewClosure())
    }

    # Event handler: Open download output folder
    if ($null -ne $openDownloadFolderButton) {
        $openDownloadFolderButton.add_Click({
                $folderPath = $SyncHash.Config.OutputPath
                if ([string]::IsNullOrWhiteSpace($folderPath)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'No download output path configured.' -Level Warning
                    return
                }
                if (-not (Test-Path -LiteralPath $folderPath)) {
                    $null = New-Item -ItemType Directory -Path $folderPath -Force
                }
                Start-Process -FilePath 'explorer.exe' -ArgumentList $folderPath | Out-Null
            }.GetNewClosure())
    }

    # Event handler: Start queue download
    if ($null -ne $SyncHash.DownloadAllButton) {
        $SyncHash.DownloadAllButton.add_Click({
                if ($SyncHash.IsRunning) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'A queue operation is already running.' -Level Warning
                    return
                }

                if ($SyncHash.DownloadQueue.Count -eq 0) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Queue is empty. Add items from Apps view first.' -Level Warning
                    return
                }

                $outputPath = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $SyncHash.Config.OutputPath
                if ([string]::IsNullOrWhiteSpace($outputPath)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Set a download output path in Settings before starting queue downloads.' -Level Warning
                    return
                }

                if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
                    try {
                        [void](New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop)
                    }
                    catch {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Could not create output path '$outputPath': $_" -Level Error
                        return
                    }
                }

                $SyncHash.Config.OutputPath = $outputPath
                if ($null -ne $outputPathBox) {
                    $outputPathBox.Text = $outputPath
                }
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

                $SyncHash.IsRunning = $true
                $SyncHash.DownloadAllButton.IsEnabled = $false
                if ($null -ne $SyncHash.DownloadProgressBar) {
                    $SyncHash.DownloadProgressBar.Visibility = [System.Windows.Visibility]::Visible
                    $SyncHash.DownloadProgressBar.IsIndeterminate = $true
                }

                $rs = & ($SyncHash['NewWpfRunspace']) -SyncHash $SyncHash
                $ps = [powershell]::Create()
                $ps.Runspace = $rs

                [void]$ps.AddScript({
                        param(
                            [string]$FormatLogEntryPath,
                            [string]$WriteUILogPath,
                            [string]$InvokeAppDownloadPath,
                            [string]$OutputPath
                        )

                        . $FormatLogEntryPath
                        . $WriteUILogPath
                        . $InvokeAppDownloadPath

                        try {
                            $syncHash.Config.OutputPath = $OutputPath
                            foreach ($queueItem in @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' })) {
                                Invoke-AppDownload -SyncHash $syncHash -QueueItem $queueItem
                            }
                        }
                        catch {
                            & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Queue download run failed: $_" -Level Error
                        }
                        finally {
                            $syncHash.Window.Dispatcher.Invoke([action] {
                                    $syncHash.IsRunning = $false
                                    if ($null -ne $syncHash.DownloadAllButton) {
                                        $syncHash.DownloadAllButton.IsEnabled = $true
                                    }
                                    if ($null -ne $syncHash.DownloadProgressBar) {
                                        $syncHash.DownloadProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
                                    }
                                    & ($syncHash['RefreshQueueView'])
                                    & ($syncHash['UpdateDownloadAllButtonState'])
                                }, 'Normal')
                        }
                    }).AddArgument($formatLogEntryPath).AddArgument($writeUILogPath).AddArgument($invokeAppDownloadPath).AddArgument($outputPath)

                [void]$ps.BeginInvoke()
            }.GetNewClosure())
    }

    # Event handler: Download queue ListView column sorting
    if ($null -ne $SyncHash.DownloadQueueListView) {
        $SyncHash.DownloadQueueListView.AddHandler(
            [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
            [System.Windows.RoutedEventHandler]({
                param($eventSender, $routedEventArgs)
                [void]$eventSender

                $header = $routedEventArgs.OriginalSource -as [System.Windows.Controls.GridViewColumnHeader]
                if ($null -eq $header -or $null -eq $header.Column) {
                    return
                }

                if ($header.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Padding) {
                    return
                }

                $property = [string]$header.Content
                if ([string]::IsNullOrWhiteSpace($property)) {
                    return
                }

                $newDirection = 'Ascending'
                if ($SyncHash.DownloadQueueSortProperty -eq $property -and $SyncHash.DownloadQueueSortDirection -eq 'Ascending') {
                    $newDirection = 'Descending'
                }

                $SyncHash.DownloadQueueSortProperty = $property
                $SyncHash.DownloadQueueSortDirection = $newDirection

                & ($SyncHash['ApplyDownloadQueueSort'])
            }.GetNewClosure())
        )
    }

    Write-Verbose 'EvergreenUI: Download feature registration complete.'
}
