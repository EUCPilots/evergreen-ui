Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-EwLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Cmd')]
        [string]$Level = 'Info'
    )

    $entry = [PSCustomObject]@{
        Timestamp = [DateTimeOffset]::Now
        Level = $Level
        Message = $Message
        Text = Format-LogEntry -Message $Message -Level $Level
    }
    Write-Information -MessageData $entry -Tags 'EvergreenUI' -InformationAction Continue
}
