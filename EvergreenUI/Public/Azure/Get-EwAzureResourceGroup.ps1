Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAzureResourceGroup {
    <#
    .SYNOPSIS
        Lists resource groups in the selected Azure subscription.
    .DESCRIPTION
        Returns resource group names, sorted, for choosing the Nerdio storage
        account location.
    .EXAMPLE
        Connect-EwAzure -SubscriptionId $subscriptionId
        Get-EwAzureResourceGroup
    .OUTPUTS
        System.String
    .NOTES
        Requires Az.Resources and an Azure context from Connect-EwAzure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Assert-EwModule -Name Az.Resources
    Write-Verbose -Message 'EvergreenUI: Listing Azure resource groups'
    $names = @(Get-AzResourceGroup -ErrorAction Stop | ForEach-Object { [string]$_.ResourceGroupName } | Sort-Object)
    Write-Verbose -Message "EvergreenUI: Found $($names.Count) Azure resource groups"
    foreach ($name in $names) { $name }
}
