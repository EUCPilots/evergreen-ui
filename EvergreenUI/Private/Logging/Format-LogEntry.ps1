Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-LogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Cmd')]
        [string]$Level = 'Info'
    )

    $prefix = switch ($Level) {
        'Warning' { 'WARN' }
        'Error' { 'ERROR' }
        'Cmd' { 'CMD' }
        default { 'INFO' }
    }
    return '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $prefix, $Message
}
