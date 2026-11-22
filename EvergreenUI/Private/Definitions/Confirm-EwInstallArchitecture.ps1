Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwInstallArchitecture {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Command,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Warning
    )

    $message = "Install '$Name' with these architecture warnings?`n`n$($Warning -join "`n")"
    return $Command.ShouldContinue($message, 'Confirm local installation architecture')
}
