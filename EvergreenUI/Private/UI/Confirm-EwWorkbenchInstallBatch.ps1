Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchInstallBatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Window,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]]$Definition
    )

    $applicationNames = @($Definition | ForEach-Object { [string]$_.Name })
    $message = "Install $($applicationNames.Count) selected application(s)?`n`n$($applicationNames -join "`n")"
    $answer = [System.Windows.MessageBox]::Show(
        $Window,
        $message,
        'Confirm local installation',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No
    )
    return $answer -eq [System.Windows.MessageBoxResult]::Yes
}
