#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads a single queued application using Get-EvergreenApp + Save-EvergreenApp.

.DESCRIPTION
    Processes one item from $syncHash.DownloadQueue. Calls Get-EvergreenApp to
    resolve the download URI for the named app, matches the item's filter criteria
    (Architecture, Channel, Platform, Version), then calls Save-EvergreenApp to
    write the file to the configured output path.

    Status is updated in-place on the queue item via Dispatcher.Invoke so the
    bound ListView updates live without needing a collection change event.

    Designed to run inside a runspace created by New-WpfRunspace. Pass $syncHash
    in via the runspace's SessionStateProxy or InitialSessionState variable.

.PARAMETER SyncHash
    Shared synchronised hashtable. Reads:
        DownloadQueue  - List[PSCustomObject] of pending items
        Config         - PSCustomObject with OutputPath property

.PARAMETER QueueItem
    A single PSCustomObject from DownloadQueue matching the Download Queue Item
    Schema (AppName, Version, Architecture, Channel, Platform, Uri, Status, Path).

.NOTES
    Queue item Status values:
        'Pending'     - not yet started
        'Downloading' - in progress
        'Done'        - completed successfully
        'Failed'      - error occurred (check log for details)
#>
function Invoke-AppDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash,

        [Parameter(Mandatory)]
        [PSCustomObject]$QueueItem
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Helper: update Status on the queue item from the UI thread.
    # PSCustomObject has no WPF thread affinity, so the Status assignment and the
    # Where-Object counts are computed here on the background thread.  Only the
    # pure UI-property writes are dispatched, keeping the [action] delegate free of
    # PS cmdlet pipelines (which deadlock when executed via Dispatcher.Invoke).
    $setStatus = {
        param([string]$NewStatus)

        # Update the data object on the background thread.
        $QueueItem.Status = $NewStatus

        # Pre-compute queue counts on the background thread.
        $pending = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
        $done = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
        $failed = @($SyncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
        $total = $SyncHash.DownloadQueue.Count
        $queueText = "Queue: $total items (Pending: $pending, Done: $done, Failed: $failed)"

        # Dispatch only simple .NET property writes to the UI thread.
        $SyncHash.Window.Dispatcher.Invoke([action] {
                if ($null -ne $SyncHash.DownloadQueueListView) {
                    $SyncHash.DownloadQueueListView.Items.Refresh()
                }
                if ($null -ne $SyncHash.QueueCountLabel) {
                    $SyncHash.QueueCountLabel.Text = $queueText
                }
            }, 'Normal')
    }

    & $setStatus 'Downloading'
    Write-UILog -SyncHash $SyncHash -Message "Downloading: $($QueueItem.AppName) $($QueueItem.Version)..." -Level Info

    try {
        if ([string]::IsNullOrWhiteSpace($QueueItem.Uri)) {
            throw "No download URI stored for $($QueueItem.AppName) $($QueueItem.Version)."
        }

        $baseOutput = if ($SyncHash.Config.OutputPath) { $SyncHash.Config.OutputPath } else { $env:TEMP }
        $outputPath = Join-Path -Path $baseOutput -ChildPath $QueueItem.AppName
        Write-UILog -SyncHash $SyncHash -Message "Get-EvergreenApp -Name '$($QueueItem.AppName)' | Save-EvergreenApp -Path '$outputPath'" -Level Cmd

        $downloadObj = if ($null -ne $QueueItem.PSObject.Properties['SourceProperties'] -and $null -ne $QueueItem.SourceProperties) {
            $QueueItem.SourceProperties
        } else {
            [PSCustomObject]@{
                URI          = $QueueItem.Uri
                Version      = $QueueItem.Version
                Architecture = $QueueItem.Architecture
                Channel      = $QueueItem.Channel
                Platform     = $QueueItem.Platform
            }
        }

        $saved = $downloadObj | Save-EvergreenApp -Path $outputPath -ErrorAction Stop

        $savedPath = if ($saved -and $saved.FullName) { $saved.FullName } else { $outputPath }
        Write-UILog -SyncHash $SyncHash -Message "Saved: $savedPath" -Level Info

        $QueueItem.Path = $savedPath
        & $setStatus 'Done'
    }
    catch {
        Write-UILog -SyncHash $SyncHash -Message "Download failed for $($QueueItem.AppName): $_" -Level Error
        & $setStatus 'Failed'
    }
}
