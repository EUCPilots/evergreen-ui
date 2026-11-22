Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchNerdioBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][object[]]$Selection,
        [Parameter(Mandatory)][psobject]$Destination
    )
    $items = foreach ($item in $Selection) { "$($item.AppName) $($item.SourceVersion): $($item.Operation) $($item.NerdioAppId)" }
    $message = "Nerdio: $($Destination.NmeHost)`nTenant: $($Destination.TenantId)`nSubscription: $($Destination.SubscriptionId)`n" +
        "Storage: $($Destination.ResourceGroupName) / $($Destination.StorageAccountName) / $($Destination.ContainerName)`n`n" +
        ($items -join "`n") + "`n`nDownload and publish these installers? Local definitions will not be changed."
    [System.Windows.MessageBox]::Show($Window, $message, 'Confirm Nerdio publishing',
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No) -eq [System.Windows.MessageBoxResult]::Yes
}
