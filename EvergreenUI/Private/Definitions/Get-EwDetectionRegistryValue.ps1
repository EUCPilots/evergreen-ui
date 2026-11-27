Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwDetectionRegistryValue {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ValueName = '',

        [Parameter()]
        [switch]$Check32BitOn64System
    )

    if ($Path -notmatch '^(HKLM|HKEY_LOCAL_MACHINE|HKCU|HKEY_CURRENT_USER):?\\(.+)$') {
        throw "Unsupported registry detection path '$Path'. Use HKLM or HKCU."
    }
    $hive = if ($Matches[1] -in @('HKLM', 'HKEY_LOCAL_MACHINE')) {
        [Microsoft.Win32.RegistryHive]::LocalMachine
    } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
    $subKey = $Matches[2]
    $view = if ([Environment]::Is64BitOperatingSystem -and -not $Check32BitOn64System) {
        [Microsoft.Win32.RegistryView]::Registry64
    } else { [Microsoft.Win32.RegistryView]::Registry32 }
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
    try {
        $key = $root.OpenSubKey($subKey)
        if ($null -eq $key) {
            return [PSCustomObject]@{ KeyExists = $false; ValueExists = $false; Value = $null }
        }
        try {
            $valueExists = $ValueName -in $key.GetValueNames()
            return [PSCustomObject]@{
                KeyExists = $true
                ValueExists = $valueExists
                Value = if ($valueExists) { $key.GetValue($ValueName) } else { $null }
            }
        }
        finally { $key.Dispose() }
    }
    finally { $root.Dispose() }
}
