Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchCacheClear {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][object]$Window)

    $message = "Clear Workbench catalog, application version and definition-Artifact caches?`n`nDownloads, Library contents, settings, provider recovery records and Evergreen application data are NOT removed."
    return Confirm-EwWorkbenchAction -Window $Window -Title 'Confirm Workbench cache clearing' -Message $message -DefaultYes $false
}
