Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchInfoView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    $State.InfoJobs = @{}
    foreach ($kind in 'Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions', 'About') {
        $State.InfoJobs[$kind] = @{
            Generation = 0
            ActiveId = $null
            ActiveRequest = $null
            Pending = $null
        }
    }
    $State.InfoClosed = $false

    $State.NavSettings.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Settings' }
    }.GetNewClosure())
    $State.NavAbout.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'About' }
    }.GetNewClosure())
    $State.SettingsResetLayoutButton.Add_Click({
        try {
            foreach ($entry in @(
                    @{ Name = 'WindowWidth'; Value = '1200' },
                    @{ Name = 'WindowHeight'; Value = '820' },
                    @{ Name = 'DownloadTrayHeight'; Value = '180' },
                    @{ Name = 'AppsListWidth'; Value = '220' },
                    @{ Name = 'WindowMaximized'; Value = 'False' }
                )) {
                & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{
                    Name = $entry.Name
                    Value = $entry.Value
                }
                $State.Settings[$entry.Name] = if ($entry.Name -in @('WindowWidth', 'WindowHeight', 'DownloadTrayHeight', 'AppsListWidth')) {
                    [int]$entry.Value
                } else {
                    $false
                }
            }
            $State.Window.WindowState = [System.Windows.WindowState]::Normal
            $State.Window.Width = 1200
            $State.Window.Height = 820
            $State.AppsListColumn.Width = [System.Windows.GridLength]::new(220)
            $State.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::new(180)
            $State.SettingsLayoutStatusLabel.Text = 'Window layout reset to defaults.'
        }
        catch {
            $message = "Could not reset window layout: $($_.Exception.Message)"
            $State.SettingsLayoutStatusLabel.Text = $message
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $message
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    foreach ($entry in @(
            @{ Control = 'SettingsUpdateEvergreenButton'; Action = 'Update'; Status = 'Updating Evergreen application data...' },
            @{ Control = 'SettingsClearCacheButton'; Action = 'Clear'; Status = 'Clearing Workbench caches...' },
            @{ Control = 'SettingsOpenCacheFolderButton'; Action = 'Open'; Status = 'Opening cache folder...' }
        )) {
        $action = $entry.Action
        $status = $entry.Status
        $State[$entry.Control].Add_Click({
            $State.SettingsMaintenanceStatusLabel.Text = $status
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchMaintenanceAction' -Parameters @{
                State = $State
                Action = $action
            }
        }.GetNewClosure())
    }

    $State.SettingsRestoreDefaultsButton.Add_Click({
        $confirmed = [System.Windows.MessageBox]::Show(
            $State.Window,
            'Restore all Workbench settings and UI preferences to their defaults?',
            'Restore Workbench defaults',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($confirmed -ne [System.Windows.MessageBoxResult]::Yes) {
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Reset-EwSetting' -Parameters @{ Confirm = $false }
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchSettingsRefresh' -Parameters @{ State = $State }
            $settings = & $State.ModuleInvoker -Name 'Get-EwSetting' -Parameters @{}
            $State.Settings = $settings
            $State.ThemeCombo.SelectedItem = [string]$settings.Theme
            $State.SettingsRestoreStatusLabel.Text = 'Workbench settings restored to defaults.'
        }
        catch {
            $message = "Could not restore defaults: $($_.Exception.Message)"
            $State.SettingsRestoreStatusLabel.Text = $message
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    foreach ($kind in 'Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions') {
        $button = $State["Open${kind}FolderButton"]
        $button.Add_Click({
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchFolderCheck' -Parameters @{
                State = $State
                Kind = $kind
                OpenAfterCheck = $true
            }
        }.GetNewClosure())

        $browseButton = $State["Browse${kind}FolderButton"]
        $browseButton.Add_Click({
            $pathBox = $State["Settings${kind}PathBox"]
            $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
            $label = [regex]::Replace($kind, '(?<=[a-z0-9])(?=[A-Z])', ' ').ToLowerInvariant()
            $dialog.Title = "Select the $label folder"
            if (-not [string]::IsNullOrWhiteSpace($pathBox.Text) -and
                $State["Open${kind}FolderButton"].IsEnabled) {
                $dialog.InitialDirectory = $pathBox.Text
            }
            if (-not $dialog.ShowDialog($State.Window)) {
                return
            }
            try {
                & $State.ModuleInvoker -Name 'Set-EwWorkbenchFolderPath' -Parameters @{
                    State = $State
                    Kind = $kind
                    Path = $dialog.FolderName
                    Confirm = $false
                }
            }
            catch {
                $message = "Could not save $label folder: $($_.Exception.Message)"
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State
                    Message = $message
                    Level = 'Error'
                }
            }
        }.GetNewClosure())
    }
    $State.RefreshAboutDependenciesButton.Add_Click({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchAboutRefresh' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.Window.Add_Closed({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInfoJobCleanup' -Parameters @{ State = $State; Closing = $true }
    }.GetNewClosure())

    $module = $ExecutionContext.SessionState.Module
    $psData = if ($module.PrivateData -is [System.Collections.IDictionary] -and
        $module.PrivateData.Contains('PSData')) { $module.PrivateData['PSData'] } else { @{} }
    $prerelease = if ($psData.Contains('Prerelease')) { [string]$psData['Prerelease'] } else { '' }
    $State.AboutNameValue.Text = "Evergreen Workbench ($($module.Name))"
    $State.AboutVersionValue.Text = if ($prerelease) {
        "Version: $($module.Version) ($prerelease)"
    }
    else {
        "Version: $($module.Version)"
    }
    $State.AboutAuthorValue.Text = "Author: $($module.Author)"
    $State.AboutCompanyValue.Text = "Company: $($module.CompanyName)"
    $State.AboutCopyrightValue.Text = [string]$module.Copyright
    $State.AboutDescriptionValue.Text = [string]$module.Description

    foreach ($entry in @(
            @{ Control = 'AboutProjectLink'; Metadata = 'ProjectUri' },
            @{ Control = 'AboutLicenseLink'; Metadata = 'LicenseUri' }
        )) {
        $link = $State[$entry.Control]
        $uri = $null
        $value = if ($psData.Contains($entry.Metadata)) { [string]$psData[$entry.Metadata] } else { '' }
        if ([uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https')) {
            $link.NavigateUri = $uri
            $link.Add_RequestNavigate({
                param($linkSource, $navigationArgs)
                $navigationArgs.Handled = $true
                try {
                    & $State.ModuleInvoker -Name 'Open-EwWorkbenchLink' -Parameters @{ Uri = $linkSource.NavigateUri }
                    $State.AboutLinkStatusLabel.Text = ''
                }
                catch {
                    $message = "Could not open the link: $($_.Exception.Message)"
                    $State.AboutLinkStatusLabel.Text = $message
                    & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                        State = $State
                        Message = $message
                        Level = 'Error'
                        PreserveStatus = $true
                    }
                }
            }.GetNewClosure())
        }
        else {
            $link.IsEnabled = $false
            $link.ToolTip = 'No valid project or license URL is available.'
        }
    }
}
