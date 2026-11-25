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
    return Confirm-EwWorkbenchAction -Window $Window -Message $message -Title 'Confirm Nerdio publishing' -DefaultYes $false
}
