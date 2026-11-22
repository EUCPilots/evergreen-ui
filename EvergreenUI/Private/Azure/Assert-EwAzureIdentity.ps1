Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwAzureIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Identity)

    Assert-EwModule -Name Az.Accounts
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or [string]$context.Tenant.Id -ine [string]$Identity.TenantId -or
        [string]$context.Subscription.Id -ine [string]$Identity.SubscriptionId) {
        throw 'The selected Azure tenant or subscription changed. Connect Azure again.'
    }
}
