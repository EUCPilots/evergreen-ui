#Requires -Version 5.1
<#
.SYNOPSIS
    Reads the EvergreenUI user configuration from disk.

.DESCRIPTION
    Loads $env:APPDATA\EvergreenUI\config.json and returns a PSCustomObject.
    If the file does not exist or is malformed, returns a default config object.
    Never throws — a missing or corrupt config is treated as first-run.

.OUTPUTS
    PSCustomObject with properties:
        OutputPath   : string  — last-used download output path
        LibraryPath  : string  — last-used library path
        Theme        : string  — 'Light' or 'Dark'
        LogVerbosity : string  — 'Normal' or 'Verbose'
        LogHeight    : int     — log panel height in pixels
        StartupView  : string  — 'Apps' | 'Download' | 'Library' | 'Settings'
        LastAppName  : string  — last selected app in Apps view
        WindowWidth  : int     — last window width
        WindowHeight : int     — last window height

.EXAMPLE
    $config = Get-UIConfig
    $outputPath = $config.OutputPath
#>
function Get-UIConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $default = [PSCustomObject]@{
        OutputPath   = ''
        LibraryPath  = ''
        Theme        = 'Light'
        LogVerbosity = 'Normal'
        LogHeight    = 150
        StartupView  = 'Apps'
        LastAppName  = ''
        WindowWidth  = 1200
        WindowHeight = 750
    }

    $configPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\config.json'

    if (-not (Test-Path -Path $configPath -PathType Leaf)) {
        return $default
    }

    try {
        $json = Get-Content -Path $configPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        # Merge with defaults so new keys added in future versions are populated
        foreach ($prop in $default.PSObject.Properties.Name) {
            if ($null -eq $json.$prop) {
                $json | Add-Member -NotePropertyName $prop -NotePropertyValue $default.$prop -Force
            }
        }
        return $json
    }
    catch {
        Write-Verbose "EvergreenUI: Could not read config ($configPath): $($_.Exception.Message)"
        return $default
    }
}
