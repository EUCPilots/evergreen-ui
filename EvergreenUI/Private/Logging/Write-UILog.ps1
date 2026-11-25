Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-UILog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Cmd', 'Info', 'Warning', 'Warn', 'Error')]
        [string]$Level,

        [Parameter()]
        [hashtable]$SyncHash = @{}
    )

    [void]$SyncHash
    $normalizedLevel = if ($Level -eq 'Warn') { 'Warning' } elseif ($Level -eq 'Debug') { 'Info' } else { $Level }
    Write-EwLog -Message $Message -Level $normalizedLevel
}
