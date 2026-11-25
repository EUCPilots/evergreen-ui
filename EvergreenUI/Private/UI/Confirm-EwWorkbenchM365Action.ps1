Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchM365Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title
    )

    return Confirm-EwWorkbenchAction -Window $Window -Message $Message -Title $Title -DefaultYes $false
}
