Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-EwWorkbenchLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Cmd')]
        [string]$Level = 'Info'
    )

    $entry = Format-LogEntry -Message $Message -Level $Level
    $State.ActivityLog.AppendText($entry + [Environment]::NewLine)
    $State.ActivityLog.ScrollToEnd()
    $State.StatusLabel.Text = $Message
}
