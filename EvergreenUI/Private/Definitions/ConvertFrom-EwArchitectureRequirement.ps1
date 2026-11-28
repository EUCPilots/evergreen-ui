Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-EwArchitectureRequirement {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Architecture
    )

    if ([string]::IsNullOrWhiteSpace($Architecture) -or $Architecture.Trim() -eq '-') {
        return [PSCustomObject]@{ Kind = 'Missing'; Values = [string[]]@(); Error = '' }
    }

    $values = @($Architecture.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if (@($values | Where-Object { $_ -notin @('all', 'x86', 'x64', 'arm64') }).Count -gt 0) {
        return [PSCustomObject]@{
            Kind = 'Invalid'
            Values = [string[]]@()
            Error = "Invalid architecture requirement '$Architecture'. Specify x86, x64, arm64, a comma-separated list, or All."
        }
    }
    $values = @($values | Select-Object -Unique)
    if ('all' -in $values -and $values.Count -ne 1) {
        return [PSCustomObject]@{
            Kind = 'Invalid'
            Values = [string[]]@()
            Error = "Invalid architecture requirement '$Architecture'. All cannot be combined with individual architectures."
        }
    }
    if ($values[0] -eq 'all') {
        return [PSCustomObject]@{ Kind = 'All'; Values = [string[]]@('x86', 'x64', 'arm64'); Error = '' }
    }
    $unique = @('x86', 'x64', 'arm64' | Where-Object { $_ -in $values })
    return [PSCustomObject]@{ Kind = 'Specific'; Values = [string[]]$unique; Error = '' }
}
