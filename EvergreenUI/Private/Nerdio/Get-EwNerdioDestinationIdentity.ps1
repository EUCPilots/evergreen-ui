Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioDestinationIdentity {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    [ordered]@{
        TenantId = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'TenantId')
        SubscriptionId = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'SubscriptionId')
        NmeHost = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'NmeHost')
        ResourceGroupName = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'ResourceGroupName')
        StorageAccountName = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'StorageAccountName')
        ContainerName = [string](Get-EwFirstPropertyValue -InputObject $Context -Name 'ContainerName')
    }
}
