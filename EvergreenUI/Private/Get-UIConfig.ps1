#Requires -Version 5.1
<#
.SYNOPSIS
    Reads the EvergreenUI user configuration from disk.

.DESCRIPTION
    Loads $env:APPDATA\EvergreenUI\settings.json and returns a PSCustomObject.
    If the file does not exist or is malformed, returns a default config object.
    Never throws - a missing or corrupt config is treated as first-run.

.OUTPUTS
    PSCustomObject with properties:
        OutputPath   : string  - last-used download output path
        LibraryPath  : string  - last-used library path
        Theme        : string  - 'Light' or 'Dark'
        LogVerbosity : string  - 'Normal' or 'Verbose'
        LogVisible   : bool    - whether the progress log panel is expanded
        LogHeight    : int     - log panel height in pixels
        StartupView  : string  - 'Apps' | 'Download' | 'Library' | 'Import' | 'Settings' | 'About'
        LastAppName  : string  - last selected app in Apps view
        WindowWidth  : int     - last window width
        WindowHeight : int     - last window height

.EXAMPLE
    $config = Get-UIConfig
    $outputPath = $config.OutputPath
#>
function Get-UIConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $default = [PSCustomObject]@{
        OutputPath        = (Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads')
        LibraryPath       = ''
        Theme             = 'Light'
        LogVerbosity      = 'Normal'
        LogVisible        = $false
        LogHeight         = 150
        StartupView       = 'Apps'
        LastAppName       = ''
        WindowWidth       = 1200
        WindowHeight      = 750
        ImportSettings    = [PSCustomObject]@{
            CurrentProvider = 'Nerdio'
        }
        NerdioSettings    = [PSCustomObject]@{
            ModulePath        = ''
            NmeHost           = ''
            NmeClientId       = ''
            NmeApiScope       = ''
            NmeSubscriptionId = ''
            NmeOAuthTokenUrl  = ''
            NmeResourceGroup  = ''
            NmeStorageAccount = ''
            NmeContainer      = ''
            DefinitionsPath   = ''
        }
        IntuneSettings    = [PSCustomObject]@{
            DefinitionsPath   = ''
            PackageOutputPath = ''
        }
        AzureAuthSettings = [PSCustomObject]@{
            TenantId              = ''
            LastAccountId         = ''
            LastTenantId          = ''
            LastSignedInUtc       = ''
            NerdioTenantId        = ''
            NerdioLastAccountId   = ''
            NerdioLastTenantId    = ''
            NerdioLastSignedInUtc = ''
        }
    }

    $configPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\settings.json'

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

        if ($null -eq $json.ImportSettings) {
            $json | Add-Member -NotePropertyName 'ImportSettings' -NotePropertyValue $default.ImportSettings -Force
        }
        elseif ($null -eq $json.ImportSettings.CurrentProvider -or [string]::IsNullOrWhiteSpace([string]$json.ImportSettings.CurrentProvider)) {
            $json.ImportSettings | Add-Member -NotePropertyName 'CurrentProvider' -NotePropertyValue 'Nerdio' -Force
        }

        if ($null -eq $json.NerdioSettings) {
            $json | Add-Member -NotePropertyName 'NerdioSettings' -NotePropertyValue $default.NerdioSettings -Force
        }
        else {
            foreach ($prop in $default.NerdioSettings.PSObject.Properties.Name) {
                if ($null -eq $json.NerdioSettings.$prop) {
                    $json.NerdioSettings | Add-Member -NotePropertyName $prop -NotePropertyValue $default.NerdioSettings.$prop -Force
                }
            }
        }

        if ($null -eq $json.IntuneSettings) {
            $json | Add-Member -NotePropertyName 'IntuneSettings' -NotePropertyValue $default.IntuneSettings -Force
        }
        else {
            foreach ($prop in $default.IntuneSettings.PSObject.Properties.Name) {
                if ($null -eq $json.IntuneSettings.$prop) {
                    $json.IntuneSettings | Add-Member -NotePropertyName $prop -NotePropertyValue $default.IntuneSettings.$prop -Force
                }
            }
        }

        if ($null -eq $json.AzureAuthSettings) {
            $json | Add-Member -NotePropertyName 'AzureAuthSettings' -NotePropertyValue $default.AzureAuthSettings -Force
        }
        else {
            foreach ($prop in $default.AzureAuthSettings.PSObject.Properties.Name) {
                if ($null -eq $json.AzureAuthSettings.$prop) {
                    $json.AzureAuthSettings | Add-Member -NotePropertyName $prop -NotePropertyValue $default.AzureAuthSettings.$prop -Force
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$json.OutputPath)) {
            $json.OutputPath = [string]$default.OutputPath
        }

        return $json
    }
    catch {
        Write-Verbose "EvergreenUI: Could not read config ($configPath): $($_.Exception.Message)"
        return $default
    }
}
