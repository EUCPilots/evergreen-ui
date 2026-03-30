#Requires -Version 5.1
<#
.SYNOPSIS
    Formats a log message with a timestamp and level prefix.

.DESCRIPTION
    Returns a string in the form "[HH:mm:ss] [PREFIX] Message" used by
    Write-UILog and Write-UpdateOutput to produce consistent log lines.

.PARAMETER Message
    The message text to format.

.PARAMETER Level
    Log level. Determines the prefix string. Defaults to 'Info'.

.OUTPUTS
    string - formatted log line, ready to append to a log control.

.EXAMPLE
    Format-LogEntry -Message 'Download complete.' -Level Info
    # Returns: "[14:32:01] [INFO] Download complete."
#>
function Format-LogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Cmd')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        'Cmd'     { 'CMD' }
        default   { 'INFO' }
    }

    return "[$timestamp] [$prefix] $Message"
}
