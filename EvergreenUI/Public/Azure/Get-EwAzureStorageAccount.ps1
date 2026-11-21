Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwAzureStorageAccount {
    <#
    .SYNOPSIS
        Lists storage accounts in an Azure resource group.
    .DESCRIPTION
        Returns storage account names, sorted, for choosing where Nerdio Shell
        App packages are uploaded.
    .PARAMETER ResourceGroupName
        Resource group containing the storage accounts.
    .EXAMPLE
        Get-EwAzureStorageAccount -ResourceGroupName rg-packages
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
        [string]$ResourceGroupName
    )

    Assert-EwModule -Name Az.Storage
    Write-Verbose -Message "EvergreenUI: Listing storage accounts in '$ResourceGroupName'"
    $names = @(Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
            ForEach-Object { [string]$_.StorageAccountName } | Sort-Object)
    Write-Verbose -Message "EvergreenUI: Found $($names.Count) storage accounts in '$ResourceGroupName'"
    foreach ($name in $names) { $name }
}
