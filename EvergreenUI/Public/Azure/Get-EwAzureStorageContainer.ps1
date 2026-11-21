Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAzureStorageContainer {
    <#
    .SYNOPSIS
        Lists blob containers in an Azure storage account.
    .DESCRIPTION
        Returns container names, sorted, for choosing where Nerdio Shell App
        packages are uploaded.
    .PARAMETER ResourceGroupName
        Resource group containing the storage account.
    .PARAMETER StorageAccountName
        Storage account containing the containers.
    .EXAMPLE
        Get-EwAzureStorageContainer -ResourceGroupName rg-packages -StorageAccountName stpackages
    .OUTPUTS
        System.String
    .NOTES
        Requires Az.Storage and an Azure context from Connect-EwAzure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName
    )

    Assert-EwModule -Name Az.Storage
    Write-Verbose -Message "EvergreenUI: Listing containers in storage account '$StorageAccountName'"
    $account = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    $names = @(Get-AzStorageContainer -Context $account.Context -ErrorAction Stop |
            ForEach-Object { [string]$_.Name } | Sort-Object)
    Write-Verbose -Message "EvergreenUI: Found $($names.Count) containers in '$StorageAccountName'"
    foreach ($name in $names) { $name }
}
