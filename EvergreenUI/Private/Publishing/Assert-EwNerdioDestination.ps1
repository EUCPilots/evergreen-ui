Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwNerdioDestination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Destination
    )

    $context = Get-EwNerdioSessionContext
    foreach ($name in 'SessionId', 'TenantId', 'SubscriptionId', 'NmeHost', 'ResourceGroupName', 'StorageAccountName', 'ContainerName') {
        if ([string]::IsNullOrWhiteSpace([string]$Destination.$name) -or
            [string]$context.$name -ine [string]$Destination.$name) {
            throw 'The confirmed Nerdio destination changed. Reconnect and compare again.'
        }
    }
    Assert-EwModule -Name Az.Accounts
    $azure = Get-AzContext -ErrorAction Stop
    if ($null -eq $azure -or [string]$azure.Tenant.Id -ine [string]$Destination.TenantId -or
        [string]$azure.Subscription.Id -ine [string]$Destination.SubscriptionId) {
        throw 'The confirmed Azure tenant and subscription are no longer active.'
    }
}
