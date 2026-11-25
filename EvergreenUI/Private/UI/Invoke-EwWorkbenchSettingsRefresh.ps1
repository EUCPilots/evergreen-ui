Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchSettingsRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    try {
        $settings = Get-EwSetting -ErrorAction Stop
        $State.Settings.OutputPath = [string]$settings.OutputPath
        $State.Settings.LibraryPath = [string]$settings.LibraryPath
        $State.Settings.LibraryPathHistory = @($settings.LibraryPathHistory)
        $State.Settings.IntuneDefinitionsPath = [string]$settings.IntuneDefinitionsPath
        $State.Settings.M365DefinitionsPath = [string]$settings.M365DefinitionsPath
        $State.Settings.NerdioDefinitionsPath = [string]$settings.NerdioDefinitionsPath
        $State.SettingsDownloadPathBox.Text = [string]$settings.OutputPath
        $State.SettingsLibraryPathBox.Text = [string]$settings.LibraryPath
        $State.SettingsPackageDefinitionsPathBox.Text = [string]$settings.IntuneDefinitionsPath
        $State.SettingsM365ConfigurationsPathBox.Text = [string]$settings.M365DefinitionsPath
        $State.SettingsNerdioDefinitionsPathBox.Text = [string]$settings.NerdioDefinitionsPath
        $State.DownloadDestinationText.Text = [string]$settings.OutputPath
        $State.DownloadDestinationText.ToolTip = [string]$settings.OutputPath
        Update-EwWorkbenchLibraryPathHistory -State $State -Path ([string]$settings.LibraryPath) -Confirm:$false
        foreach ($kind in 'Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions') {
            Invoke-EwWorkbenchFolderCheck -State $State -Kind $kind
        }
    }
    catch {
        $message = "Could not read saved settings: $($_.Exception.Message)"
        foreach ($kind in 'Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions') {
            $slot = $State.InfoJobs[$kind]
            $slot.Generation = [int]$slot.Generation + 1
            $slot.Pending = $null
            Invoke-EwWorkbenchInfoJobCleanup -State $State -Kind $kind
            $State["Settings${kind}PathBox"].Text = ''
            $State["Open${kind}FolderButton"].IsEnabled = $false
            $State["${kind}FolderStatusLabel"].Text = $message
        }
        Write-EwWorkbenchLog -State $State -Message $message -Level Error -PreserveStatus
    }
}
