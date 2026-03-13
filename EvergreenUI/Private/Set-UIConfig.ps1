#Requires -Version 5.1
<#
.SYNOPSIS
    Persists the EvergreenUI user configuration to disk.

.DESCRIPTION
    Serialises the provided config object to JSON and writes it to
    $env:APPDATA\EvergreenUI\config.json. Creates the directory if it does not
    exist. Errors are written as warnings and are never terminating - a failed
    config write must not crash the UI.

.PARAMETER Config
    A PSCustomObject (typically the output of Get-UIConfig, modified by the
    user's session) to persist. Must contain at minimum: OutputPath, LibraryPath,
    Theme, LogVerbosity, LogHeight.

.EXAMPLE
    $config = Get-UIConfig
    $config.Theme = 'Dark'
    $config.OutputPath = 'D:\Installers'
    Set-UIConfig -Config $config
#>
function Set-UIConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $configDir = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
    $configPath = Join-Path -Path $configDir   -ChildPath 'config.json'

    try {
        if (-not (Test-Path -Path $configDir -PathType Container)) {
            [void](New-Item -Path $configDir -ItemType Directory -Force -ErrorAction Stop)
        }

        $Config |
        ConvertTo-Json -Depth 5 -ErrorAction Stop |
        Set-Content -Path $configPath -Encoding UTF8 -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "EvergreenUI: Could not save config ($configPath): $($_.Exception.Message)"
    }
}
