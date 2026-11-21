#Requires -Version 5.1
<#
.SYNOPSIS
    Persists the EvergreenUI user configuration to disk.

.DESCRIPTION
    Serialises the provided config object to JSON and writes it to
    $env:APPDATA\EvergreenUI\settings.json. Creates the directory if it does not
    exist. Errors are written as warnings and are never terminating - a failed
    config write must not crash the UI.

.PARAMETER Config
    A PSCustomObject (typically the output of Get-UIConfig, modified by the
    user's session) to persist. Must contain at minimum: OutputPath, LibraryPath,
    Theme, LogHeight.

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
    $configPath = Join-Path -Path $configDir -ChildPath 'settings.json'
    $tempPath = Join-Path -Path $configDir -ChildPath 'settings.json.tmp'

    try {
        if (-not (Test-Path -Path $configDir -PathType Container)) {
            [void](New-Item -Path $configDir -ItemType Directory -Force -ErrorAction Stop)
        }

        $json = $Config | ConvertTo-Json -Depth 5 -ErrorAction Stop

        # Write to a temp file first, then atomically replace settings.json.
        # This reduces the chance of partial/truncated files on unexpected termination.
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -Path $tempPath -Destination $configPath -Force -ErrorAction Stop
        Write-Verbose -Message "EvergreenUI: Config saved to '$configPath'."
    }
    catch {
        if (Test-Path -Path $tempPath -PathType Leaf) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        Write-Warning "EvergreenUI: Could not save config ($configPath): $($_.Exception.Message)"
    }
}
