Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchSettingsRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    try {
        $settings = Get-EwSetting -ErrorAction Stop
        $State.Settings.OutputPath = [string]$settings.OutputPath
        $State.Settings.LibraryPath = [string]$settings.LibraryPath
        $State.SettingsDownloadPathBox.Text = [string]$settings.OutputPath
        $State.SettingsLibraryPathBox.Text = [string]$settings.LibraryPath
        $State.DownloadDestinationText.Text = [string]$settings.OutputPath
        $State.DownloadDestinationText.ToolTip = [string]$settings.OutputPath
        $State.LibraryPathBox.Text = [string]$settings.LibraryPath
        foreach ($kind in 'Download', 'Library') {
            Invoke-EwWorkbenchFolderCheck -State $State -Kind $kind
        }
    }
    catch {
        $message = "Could not read saved settings: $($_.Exception.Message)"
        foreach ($kind in 'Download', 'Library') {
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
