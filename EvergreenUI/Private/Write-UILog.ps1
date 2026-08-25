#Requires -Version 5.1
<#
.SYNOPSIS
    Appends a timestamped entry to the UI log panel in a thread-safe manner.

.DESCRIPTION
    Uses Dispatcher.Invoke to marshal the UI update back to the WPF UI thread,
    making it safe to call from any runspace. If the message is null or
    whitespace it is silently ignored.

.PARAMETER Message
    The text to append. A [HH:mm:ss] timestamp is prepended automatically.

.PARAMETER Level
    Log level. Affects the CSS-style class applied to the log entry for
    colour-coding. Defaults to 'Info'.

.PARAMETER SyncHash
    The shared synchronised hashtable. Must contain:
      - Window          : the WPF Window object
      - LogTextBox      : the TextBox control used for log output
      - LogScrollViewer : the ScrollViewer wrapping the TextBox

.EXAMPLE
    Write-UILog -Message 'Download complete.' -Level Info -SyncHash $syncHash
    Write-UILog -Message "ERROR: $($_.Exception.Message)" -Level Error -SyncHash $syncHash
#>
function Write-UILog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Cmd')]
        [string]$Level = 'Info',

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    if ($null -eq $SyncHash -or ($SyncHash.ContainsKey('IsClosing') -and [bool]$SyncHash.IsClosing)) { return }

    $window = $SyncHash.Window
    $textBox = $SyncHash.LogTextBox
    $scrollViewer = $SyncHash.LogScrollViewer
    if ($null -eq $window -or $null -eq $textBox -or $null -eq $scrollViewer) { return }

    $dispatcher = $window.Dispatcher
    if ($null -eq $dispatcher -or $dispatcher.HasShutdownStarted -or $dispatcher.HasShutdownFinished) { return }

    $logEntry = Format-LogEntry -Message $Message -Level $Level

    if (-not [string]::IsNullOrEmpty($SyncHash.LogFilePath)) {
        try {
            [System.IO.File]::AppendAllText(
                $SyncHash.LogFilePath,
                "$logEntry`r`n",
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        catch {
            # best-effort - file logging failure must not abort the caller
            Write-Verbose -Message "EvergreenUI: log file write failed: $($_.Exception.Message)"
        }
    }

    try {
        $dispatcher.Invoke([action] {
            if ($SyncHash.ContainsKey('IsClosing') -and [bool]$SyncHash.IsClosing) { return }
                $SyncHash.LogTextBox.AppendText("$logEntry`r`n")
                $SyncHash.LogScrollViewer.ScrollToEnd()
            }, 'Normal')
    }
    catch {
        # best-effort - dispatcher shutdown must not abort background work
        Write-Verbose -Message "EvergreenUI: UI log dispatch failed during shutdown: $($_.Exception.Message)"
    }
}
