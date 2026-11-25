Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwDefinitionFileHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath
    )

    $bytes = [System.IO.File]::ReadAllBytes($DefinitionPath)
    $sha256 = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($sha256)
}
