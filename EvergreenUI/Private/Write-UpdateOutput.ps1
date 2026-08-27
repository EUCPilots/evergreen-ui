#Requires -Version 5.1
<#
.SYNOPSIS
    Appends timestamped output to the Update tab output control in a thread-safe way.

.DESCRIPTION
    Marshals updates to the WPF UI thread via Dispatcher.Invoke so it can be
    called from background runspaces.

.PARAMETER Message
    Message text to append.

.PARAMETER Level
    Message level used for prefix formatting.

.PARAMETER SyncHash
    Shared synchronized hashtable that holds UpdateOutputTextBox and
    UpdateOutputScrollViewer control references.
#>
function Write-UpdateOutput {
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
    $textBox = $SyncHash.UpdateOutputTextBox
    $scrollViewer = $SyncHash.UpdateOutputScrollViewer
    if ($null -eq $window -or $null -eq $textBox -or $null -eq $scrollViewer) { return }

    $dispatcher = $window.Dispatcher
    if ($null -eq $dispatcher -or $dispatcher.HasShutdownStarted -or $dispatcher.HasShutdownFinished) { return }

    try {
        $formatLogEntryCommand = Get-Command -Name Format-LogEntry -CommandType Function -ErrorAction Stop
        $line = & $formatLogEntryCommand -Message $Message -Level $Level
    }
    catch {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $prefix = switch ($Level) {
            'Warning' { 'WARN' }
            'Error'   { 'ERROR' }
            'Cmd'     { 'CMD' }
            default   { 'INFO' }
        }
        $line = "[$timestamp] [$prefix] $Message"
    }

    try {
        $dispatcher.Invoke([action]{
            if ($SyncHash.ContainsKey('IsClosing') -and [bool]$SyncHash.IsClosing) { return }
                $SyncHash.UpdateOutputTextBox.AppendText("$line`r`n")
                $SyncHash.UpdateOutputScrollViewer.ScrollToEnd()
            }, 'Normal')
    }
    catch {
        # best-effort - dispatcher shutdown must not abort background work
        Write-Verbose -Message "EvergreenUI: update output dispatch failed during shutdown: $($_.Exception.Message)"
    }
}
