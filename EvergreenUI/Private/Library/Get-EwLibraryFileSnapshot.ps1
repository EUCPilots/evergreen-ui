Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwLibraryFileSnapshot {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $safePath = Get-EwLibrarySafePath -Root $Root -Path $Path
    Write-Verbose -Message "EvergreenUI: Reading library manifest $safePath"
    $bytes = [IO.File]::ReadAllBytes($safePath)
    $text = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $data = ConvertFrom-Json -InputObject $text -NoEnumerate -ErrorAction Stop
    if ($null -eq $data) {
        throw "Library manifest contains null instead of inventory: $safePath"
    }
    [PSCustomObject]@{
        Path = $safePath
        Hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        Data = $data
    }
}
