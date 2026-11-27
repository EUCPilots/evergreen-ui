Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EwDetectionFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter()]
        [switch]$Check32BitOn64System
    )

    $values = @{}
    if ([Environment]::Is64BitOperatingSystem) {
        foreach ($name in @('ProgramFiles', 'CommonProgramFiles')) {
            $native = [Environment]::GetEnvironmentVariable("${name}W6432")
            if ([string]::IsNullOrWhiteSpace($native)) {
                $native = [Environment]::GetEnvironmentVariable($name)
            }
            $selected = if ($Check32BitOn64System) {
                [Environment]::GetEnvironmentVariable("${name}(x86)")
            } else { $native }
            if (-not [string]::IsNullOrWhiteSpace($selected)) {
                $values[$name] = $selected
            }
        }
    }
    $expanded = [regex]::Replace($Path, '%([^%]+)%', {
            param($match)
            $name = $match.Groups[1].Value
            if ($values.ContainsKey($name)) { return $values[$name] }
            $value = [Environment]::GetEnvironmentVariable($name)
            if ($null -eq $value) { return $match.Value }
            return $value
        }.GetNewClosure())
    return $expanded
}
