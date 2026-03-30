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
        LogVisible   : bool    - whether the progress log panel is expanded
        LogHeight    : int     - log panel height in pixels
        ShowImportTab: bool    - whether the Import tab is visible in navigation
        StartupView  : string  - 'Apps' | 'Download' | 'Library' | 'Import' | 'Settings' | 'Update' | 'About'
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
        LogVisible        = $false
        LogHeight         = 150
        ShowImportTab     = $true
        ShowInstallTab    = $true
        StartupView       = 'Apps'
        LastAppName       = ''
        WindowWidth       = 1200
        WindowHeight      = 750
        ImportSettings    = [PSCustomObject]@{
            CurrentProvider = 'Nerdio'
        }
        NerdioSettings    = [PSCustomObject]@{
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
        M365Settings      = [PSCustomObject]@{
            DefinitionsPath   = ''
            PackageOutputPath = ''
            Channel           = 'MonthlyEnterprise'
            CompanyName       = ''
        }
        InstallSettings   = [PSCustomObject]@{
            DefinitionsPath   = ''
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

        # Merge nested settings sections - Merge-ConfigSection handles null (returns default)
        # and missing keys (adds from default), ensuring forward-compat with new settings.
        $json.NerdioSettings    = Merge-ConfigSection -Loaded $json.NerdioSettings    -Default $default.NerdioSettings
        $json.IntuneSettings    = Merge-ConfigSection -Loaded $json.IntuneSettings    -Default $default.IntuneSettings
        $json.M365Settings      = Merge-ConfigSection -Loaded $json.M365Settings      -Default $default.M365Settings
        $json.InstallSettings   = Merge-ConfigSection -Loaded $json.InstallSettings   -Default $default.InstallSettings
        $json.AzureAuthSettings = Merge-ConfigSection -Loaded $json.AzureAuthSettings -Default $default.AzureAuthSettings

        # ImportSettings has a special case: if present but CurrentProvider is blank, restore the default.
        if ($null -eq $json.ImportSettings) {
            $json | Add-Member -NotePropertyName 'ImportSettings' -NotePropertyValue $default.ImportSettings -Force
        }
        elseif ($null -eq $json.ImportSettings.CurrentProvider -or [string]::IsNullOrWhiteSpace([string]$json.ImportSettings.CurrentProvider)) {
            $json.ImportSettings | Add-Member -NotePropertyName 'CurrentProvider' -NotePropertyValue 'Nerdio' -Force
        }

        if ([string]::IsNullOrWhiteSpace([string]$json.OutputPath)) {
            $json.OutputPath = [string]$default.OutputPath
        }

        if ($null -eq $json.ShowImportTab) {
            $json.ShowImportTab = [bool]$default.ShowImportTab
        }

        if ($null -eq $json.ShowInstallTab) {
            # Backward compatibility: before this setting existed, Install visibility followed ShowImportTab.
            $json.ShowInstallTab = [bool]$json.ShowImportTab
        }

        return $json
    }
    catch {
        Write-Verbose "EvergreenUI: Could not read config ($configPath): $($_.Exception.Message)"
        return $default
    }
}
