Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwSetting {
    <#
    .SYNOPSIS
        Gets Evergreen Workbench settings.
    .DESCRIPTION
        Reads v2 settings without accessing or migrating the v1 settings file.
        Missing settings receive defaults; invalid settings are reported.
    .EXAMPLE
        Get-EwSetting
    .OUTPUTS
        System.Collections.IDictionary
    .NOTES
        Settings are stored under APPDATA in EvergreenWorkbench\settings.json.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [System.Management.Automation.OrderedHashtable])]
    param()

    $defaults = [ordered]@{
        SchemaVersion = 1
        Theme = 'System'
        OutputPath = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'
        LibraryPath = ''
    }
    $path = Get-EwSettingsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Verbose -Message "EvergreenUI: No settings at $path; using defaults"
        return $defaults
    }

    Write-Verbose -Message "EvergreenUI: Reading settings from $path"
    $loaded = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($loaded -isnot [System.Collections.IDictionary] -or -not $loaded.Contains('SchemaVersion') -or $loaded.SchemaVersion -ne 1) {
        throw "Unsupported or invalid settings schema in '$path'."
    }
    foreach ($key in $defaults.Keys) {
        if (-not $loaded.Contains($key)) {
            $loaded[$key] = $defaults[$key]
        }
    }
    Write-Verbose -Message "EvergreenUI: Settings loaded from $path"
    return $loaded
}
