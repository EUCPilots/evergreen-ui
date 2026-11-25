Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwCacheEpoch {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
        # A fresh token also makes deleted metadata fail closed. Never resurrect
        # unversioned payloads or reuse an earlier lookup's missing-marker token.
        $epoch = Invoke-EwCacheInvalidation -Path $Path -ErrorAction Stop
        Write-Verbose -Message "EvergreenUI: Cache coordination metadata initialized at '$Path'; unversioned payloads are not reused"
        return $epoch
    }
    $epoch = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $parsed = [guid]::Empty
    if ($epoch -isnot [string] -or -not [guid]::TryParse($epoch, [ref]$parsed)) {
        throw "Invalid cache epoch in '$Path'."
    }
    return $epoch
}
