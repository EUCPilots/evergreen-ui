Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchIntuneBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Window,

        [Parameter(Mandatory)]
        [object[]]$Selection,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $items = foreach ($item in $Selection) {
        $mode = if ($item.ImportAsUpdate) { 'UPDATE APP: required for All Devices' } else { 'Definition assignments' }
        $relationship = if ($item.IntuneAppId) { "supersedes $($item.IntuneAppId)" } else { 'new app' }
        "$($item.DefinitionName): $mode; $relationship"
    }
    $message = "Tenant: $TenantId`n`n$($items -join "`n")`n`n" +
        'The selected Definition and Source\Install.json files may be updated on disk. Continue?'
    [System.Windows.MessageBox]::Show($Window, $message, 'Confirm Intune publishing',
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -eq
        [System.Windows.MessageBoxResult]::Yes
}
