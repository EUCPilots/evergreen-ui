Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EwAzure {
    <#
    .SYNOPSIS
        Signs in to Azure for Nerdio storage discovery.
    .DESCRIPTION
        Signs in to Azure with Az.Accounts and selects a subscription so that
        resource groups, storage accounts, and containers can be discovered
        before Connect-EwNerdio is called. An existing Azure context for the
        same tenant and subscription is reused.
    .PARAMETER SubscriptionId
        Azure subscription ID to select.
    .PARAMETER TenantId
        Optional Entra tenant ID.
    .PARAMETER UseDeviceAuthentication
        Uses device authentication instead of a browser sign-in.
    .EXAMPLE
        Connect-EwAzure -SubscriptionId $subscriptionId -TenantId $tenantId
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Az.Accounts. Tokens remain in the Az process context.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$UseDeviceAuthentication
    )

    $script:ewNerdioSession.Context = $null
    try {
        $context = Connect-EwAzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId `
            -UseDeviceAuthentication:$UseDeviceAuthentication
        [PSCustomObject]@{
            Succeeded = $true
            AccountId = $context.AccountId
            TenantId = $context.TenantId
            SubscriptionId = $context.SubscriptionId
            SubscriptionName = $context.SubscriptionName
            Error = ''
        }
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Azure sign-in failed: $($_.Exception.Message)"
        [PSCustomObject]@{
            Succeeded = $false
            AccountId = ''
            TenantId = ''
            SubscriptionId = ''
            SubscriptionName = ''
            Error = $_.Exception.Message
        }
    }
}
