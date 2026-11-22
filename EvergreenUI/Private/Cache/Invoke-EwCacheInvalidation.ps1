Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwCacheInvalidation {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ((Test-Path -LiteralPath $Path -ErrorAction Stop) -and
        -not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)) {
        throw "Cache coordination metadata is not a file: '$Path'."
    }
    $null = New-Item -Path (Split-Path -Path $Path -Parent) -ItemType Directory -Force -ErrorAction Stop
    $epoch = [guid]::NewGuid().ToString('N')
    Write-EwJsonFile -Path $Path -InputObject $epoch -ErrorAction Stop
    return $epoch
}
