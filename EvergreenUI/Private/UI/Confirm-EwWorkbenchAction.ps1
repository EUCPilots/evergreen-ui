Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchAction {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][bool]$DefaultYes
    )

    $dialog = New-EwWorkbenchConfirmationDialog -Owner $Window -Title $Title -Message $Message -DefaultYes $DefaultYes
    return $dialog.ShowDialog() -eq $true
}
