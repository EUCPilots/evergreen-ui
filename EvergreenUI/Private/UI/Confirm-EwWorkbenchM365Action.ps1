Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchM365Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title
    )

    [System.Windows.MessageBox]::Show($Window, $Message, $Title,
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No) -eq [System.Windows.MessageBoxResult]::Yes
}
