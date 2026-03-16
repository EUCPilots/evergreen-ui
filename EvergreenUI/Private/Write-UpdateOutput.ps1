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
    if ($null -eq $SyncHash.UpdateOutputTextBox -or $null -eq $SyncHash.UpdateOutputScrollViewer) { return }

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error' { 'ERROR' }
        'Cmd' { 'CMD' }
        default { 'INFO' }
    }

    $line = "[$timestamp] [$prefix] $Message"

    $SyncHash.Window.Dispatcher.Invoke([action]{
            $SyncHash.UpdateOutputTextBox.AppendText("$line`r`n")
            $SyncHash.UpdateOutputScrollViewer.ScrollToEnd()
        }, 'Normal')
}
