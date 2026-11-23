Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchCacheClear {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][object]$Window)

    $message = "Clear Workbench catalog, application version and definition-Artifact caches?`n`nDownloads, Library contents, settings, provider recovery records and Evergreen application data are NOT removed."
    $answer = [System.Windows.MessageBox]::Show(
        $Window, $message, 'Confirm Workbench cache clearing',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No
    )
    return $answer -eq [System.Windows.MessageBoxResult]::Yes
}
