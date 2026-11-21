Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwNerdioBlobUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [psobject]$Context
    )

    Assert-EwModule -Name Az.Storage
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    $md5 = [System.Security.Cryptography.MD5]::HashData([System.Text.Encoding]::UTF8.GetBytes($hash))
    $blobName = '{0}.{1}' -f ([Convert]::ToHexString($md5).ToLowerInvariant()), (Split-Path -Path $Path -Leaf)
    $keys = @(Get-AzStorageAccountKey -ResourceGroupName $Context.ResourceGroupName `
        -Name $Context.StorageAccountName -ErrorAction Stop)
    if ($keys.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$keys[0].Value)) {
        throw 'Azure storage account returned no access key.'
    }
    $storageContext = New-AzStorageContext -StorageAccountName $Context.StorageAccountName `
        -StorageAccountKey $keys[0].Value -ErrorAction Stop
    $blob = Set-AzStorageBlobContent -File $Path -Container $Context.ContainerName `
        -Blob $blobName -Context $storageContext -Force -ErrorAction Stop
    $blobUri = [string]$blob.ICloudBlob.Uri.AbsoluteUri
    if ([string]::IsNullOrWhiteSpace($blobUri)) {
        throw "Azure Storage did not return a blob URI for '$blobName'."
    }
    $sas = New-AzStorageBlobSASToken -Context $storageContext -Container $Context.ContainerName `
        -Blob $blobName -Permission r -ExpiryTime (Get-Date).AddYears(5) -FullUri -ErrorAction Stop
    [PSCustomObject]@{
        Sha256 = $hash
        BlobName = $blobName
        SourceUrl = if ([string]::IsNullOrWhiteSpace([string]$sas)) { $blobUri } else { [string]$sas }
    }
}
