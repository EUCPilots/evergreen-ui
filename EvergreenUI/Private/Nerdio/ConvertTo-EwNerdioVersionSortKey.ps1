Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-EwNerdioVersionSortKey {
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )

    $maximum = [version]::new([int]::MaxValue, [int]::MaxValue, [int]::MaxValue, [int]::MaxValue)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $maximum
    }
    $sanitized = ($Name.Trim() -replace '^[^0-9]*', '') -replace '[^0-9\.]', ''
    $parsed = $null
    if ($sanitized -notmatch '\.') {
        $sanitized = "$sanitized.0"
    }
    if ([version]::TryParse($sanitized, [ref]$parsed)) {
        return $parsed
    }
    return $maximum
}
