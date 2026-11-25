Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-EwComparableVersion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Version
    )

    $raw = if ($null -eq $Version) { '' } else { $Version }
    $result = {
        param([bool]$Success, [string]$Normalized = '', [object]$Parsed = $null, [string]$Message = '')
        [PSCustomObject]@{ Success = $Success; Raw = $raw; Normalized = $Normalized; Parsed = $Parsed; Error = $Message }
    }

    $trimmed = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return (& $result -Success $false -Message 'Version is empty.')
    }
    $match = [regex]::Match($trimmed, '\d+(\.\d+){0,3}')
    $normalized = if ($match.Success) { $match.Value } else { ($trimmed -replace '[^0-9\.]', '').Trim('.') }
    $segments = @($normalized.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 4)
    if ($segments.Count -eq 0) {
        return (& $result -Success $false -Message 'Version has no numeric segments.')
    }
    if ($segments.Count -eq 1) {
        $segments += '0'
    }
    $normalized = $segments -join '.'
    try {
        return (& $result -Success $true -Normalized $normalized -Parsed ([version]$normalized))
    }
    catch {
        return (& $result -Success $false -Normalized $normalized -Message $_.Exception.Message)
    }
}
