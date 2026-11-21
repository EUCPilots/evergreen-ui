Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-EwJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [psobject]$InputObject
    )

    $json = ConvertTo-Json -InputObject $InputObject -Depth 100
    $temporaryPath = Join-Path -Path (Split-Path -Path $Path -Parent) -ChildPath ".$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
    }
}
