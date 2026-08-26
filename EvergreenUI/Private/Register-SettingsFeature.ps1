function Register-SettingsFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Settings tab (theme, paths, preferences, and log management).

    .DESCRIPTION
    Sets up event handlers for all Settings-related controls:
    - Theme selection (light/dark mode with dynamic UI switching)
    - Output path browsing and validation
    - Evergreen apps path display and folder access
    - Log panel toggle, copy, save, and clear operations
    - Cache management (open and clear)
    - Feature toggles (Show Import/Install tabs, Architecture filtering)
    - Settings panel population on activation

    All path inputs are normalized (trimmed and de-quoted) on change and persisted to config.
    Log height is persisted when collapsed; restored when expanded.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls from XAML.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.

    Depends on: $SyncHash.RefreshInstallRows, $SyncHash.UpdateDownloadAllButtonState
    (defined by Install and Download features respectively).
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract Settings controls
    $themeComboBox = $Controls.ThemeComboBox
    $settingsPanel = $Controls.SettingsPanel
    $outputPathBox = $Controls.OutputPathBox
    $evergreenAppsPathBox = $Controls.EvergreenAppsPathBox
    $browseOutputButton = $Controls.BrowseOutputButton
    $browseLibraryButton = $Controls.BrowseLibraryButton
    $openEvergreenAppsFolderButton = $Controls.OpenEvergreenAppsFolderButton
    $clearCacheButton = $Controls.ClearCacheButton
    $openCacheFolderButton = $Controls.OpenCacheFolderButton
    $openLogsFolderButton = $Controls.OpenLogsFolderButton
    $clearLogsButton = $Controls.ClearLogsButton
    $logToggleButton = $Controls.LogToggleButton
    $copyLogButton = $Controls.CopyLogButton
    $saveLogButton = $Controls.SaveLogButton
    $showImportTabToggle = $Controls.ShowImportTabToggle
    $showInstallTabToggle = $Controls.ShowInstallTabToggle
    $installHideIncompatibleArchitectureToggle = $Controls.InstallHideIncompatibleArchitectureToggle
    $libraryPathViewBox = $Controls.LibraryPathViewBox
    $navSettings = $Controls.NavSettings
    $navApps = $Controls.NavApps
    $navImport = $Controls.NavImport
    $navInstall = $Controls.NavInstall
    $logRowDef = $SyncHash.Window.FindName('LogRowDefinition')

    # Helper scriptblock: Normalize directory path (trim whitespace and quotes)
    $normalizeDirectoryPath = {
        param([string]$PathValue)

        if ([string]::IsNullOrWhiteSpace($PathValue)) {
            return ''
        }

        return $PathValue.Trim().Trim('"')
    }

    # Helper scriptblock: Set Import/Install tab visibility based on config
    $setImportTabVisibility = {
        param(
            [bool]$ShowImport,
            [bool]$ShowInstall
        )

        if ($null -ne $navImport) {
            $navImport.Visibility = if ($ShowImport) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }

            if (-not $ShowImport -and $navImport.IsChecked) {
                $navApps.IsChecked = $true
            }
        }

        if ($null -ne $navInstall) {
            $navInstall.Visibility = if ($ShowInstall) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }

            if (-not $ShowInstall -and $navInstall.IsChecked) {
                $navApps.IsChecked = $true
            }
        }

        # If startup view is hidden, reset to Apps
        $startupView = [string]$SyncHash.Config.StartupView
        if (($startupView -eq 'Import' -and -not $ShowImport) -or ($startupView -eq 'Install' -and -not $ShowInstall)) {
            $SyncHash.Config.StartupView = 'Apps'
        }
    }

    # Store helper scriptblocks in SyncHash for cross-feature access
    $SyncHash.NormalizeDirectoryPath = $normalizeDirectoryPath
    $SyncHash.SetImportTabVisibility = $setImportTabVisibility

    # =========================================================================
    # Theme Selection: Dark/Light mode with immediate UI update
    # =========================================================================
    $themeComboBox.add_SelectionChanged({
            $item = $themeComboBox.SelectedItem
            if ($null -eq $item) { return }

            if ([string]$item.Content -eq 'Dark') {
                & ($SyncHash['SetDarkTheme']) -Window $SyncHash.Window
                $SyncHash.Config.Theme = 'Dark'
            }
            else {
                & ($SyncHash['SetLightTheme']) -Window $SyncHash.Window
                $SyncHash.Config.Theme = 'Light'
            }

            & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
        }.GetNewClosure())

    # =========================================================================
    # Settings Panel Activation: Populate form fields from config
    # =========================================================================
    $navSettings.add_Checked({
            $outputPathBox.Text = $SyncHash.Config.OutputPath
            $evergreenAppsPathBox.Text = (& ($SyncHash['GetEvergreenAppsPath']))

            $themeComboBox.SelectedIndex = if ([string]$SyncHash.Config.Theme -eq 'Dark') { 1 } else { 0 }

            if ($null -ne $showImportTabToggle) {
                $showImportTabToggle.IsChecked = [bool]$SyncHash.Config.ShowImportTab
            }
            if ($null -ne $showInstallTabToggle) {
                $showInstallTabToggle.IsChecked = [bool]$SyncHash.Config.ShowInstallTab
            }

            & $setImportTabVisibility -ShowImport ([bool]$SyncHash.Config.ShowImportTab) -ShowInstall ([bool]$SyncHash.Config.ShowInstallTab)
        }.GetNewClosure())

    # =========================================================================
    # Feature Toggles: Show/hide Import and Install tabs
    # =========================================================================
    if ($null -ne $showImportTabToggle) {
        $showImportTabToggle.add_Click({
                $showImport = [bool]$showImportTabToggle.IsChecked
                $SyncHash.Config.ShowImportTab = $showImport
                & $setImportTabVisibility -ShowImport $showImport -ShowInstall ([bool]$SyncHash.Config.ShowInstallTab)
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $showInstallTabToggle) {
        $showInstallTabToggle.add_Click({
                $showInstall = [bool]$showInstallTabToggle.IsChecked
                $SyncHash.Config.ShowInstallTab = $showInstall
                & $setImportTabVisibility -ShowImport ([bool]$SyncHash.Config.ShowImportTab) -ShowInstall $showInstall
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $installHideIncompatibleArchitectureToggle) {
        $installHideIncompatibleArchitectureToggle.add_Click({
                $hideIncompatibleArchitecture = [bool]$installHideIncompatibleArchitectureToggle.IsChecked
                if ($null -eq $SyncHash.Config.InstallSettings) {
                    $SyncHash.Config | Add-Member -NotePropertyName 'InstallSettings' -NotePropertyValue ([PSCustomObject]@{ HideIncompatibleArchitecture = $hideIncompatibleArchitecture }) -Force
                }
                else {
                    $SyncHash.Config.InstallSettings.HideIncompatibleArchitecture = $hideIncompatibleArchitecture
                }
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                & ($SyncHash['RefreshInstallRows'])
            }.GetNewClosure())
    }

    # =========================================================================
    # Log Panel: Toggle visibility with height persistence
    # =========================================================================
    # When expanded, the log area height (above the 48px status bar) is restored
    # from config; when collapsed, row 3 drops to exactly the status bar height.
    $logToggleButton.add_Click({
            if ($logToggleButton.IsChecked) {
                $restoreHeight = [Math]::Max(80, $SyncHash.Config.LogHeight)
                $logRowDef.Height = [System.Windows.GridLength]::new(48 + $restoreHeight)
                $logToggleButton.Content = 'Hide progress log'
                $SyncHash.Config.LogVisible = $true
            }
            else {
                # Save current displayed log height before collapsing
                $currentHeight = [int]$logRowDef.Height.Value - 48
                if ($currentHeight -gt 0) { $SyncHash.Config.LogHeight = $currentHeight }
                $logRowDef.Height = [System.Windows.GridLength]::new(48)
                $logToggleButton.Content = 'Show progress log'
                $SyncHash.Config.LogVisible = $false
            }

            & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
        }.GetNewClosure())

    # =========================================================================
    # Log Operations: Copy and Save
    # =========================================================================
    $copyLogButton.add_Click({
            if (-not [string]::IsNullOrEmpty($SyncHash.LogTextBox.Text)) {
                [System.Windows.Clipboard]::SetText($SyncHash.LogTextBox.Text)
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Log copied to clipboard.' -Level Info
            }
        }.GetNewClosure())

    $saveLogButton.add_Click({
            $dlg = [System.Windows.Forms.SaveFileDialog]::new()
            $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
            $dlg.FileName = "EvergreenUI-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $SyncHash.LogTextBox.Text |
                    Set-Content -Path $dlg.FileName -Encoding UTF8 -ErrorAction Stop
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Log saved: $($dlg.FileName)" -Level Info
                }
                catch {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to save log: $_" -Level Error
                }
            }
        }.GetNewClosure())

    # =========================================================================
    # Output Path Management: Browse and normalize
    # =========================================================================
    $browseOutputButton.add_Click({
            $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
            $dlg.Description = 'Select download output folder'
            $dlg.SelectedPath = $outputPathBox.Text
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
                $outputPathBox.Text = $normalised
                $SyncHash.Config.OutputPath = $normalised
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                & ($SyncHash['UpdateDownloadAllButtonState'])
            }
        }.GetNewClosure())

    # Normalize path when focus leaves the output path box
    $outputPathBox.add_LostFocus({
            $normalised = & $normalizeDirectoryPath -PathValue $outputPathBox.Text
            $outputPathBox.Text = $normalised
            $SyncHash.Config.OutputPath = $normalised
            & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            & ($SyncHash['UpdateDownloadAllButtonState'])
        }.GetNewClosure())

    # =========================================================================
    # Evergreen Apps Path: Display and Open folder
    # =========================================================================
    $openEvergreenAppsFolderButton.add_Click({
            $folderPath = $evergreenAppsPathBox.Text
            if ([string]::IsNullOrWhiteSpace($folderPath)) { return }
            if (-not (Test-Path -LiteralPath $folderPath)) {
                $null = New-Item -ItemType Directory -Path $folderPath -Force
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList $folderPath | Out-Null
        }.GetNewClosure())

    # =========================================================================
    # Cache Management: Open and Clear
    # =========================================================================
    $openCacheFolderButton.add_Click({
            $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                $null = New-Item -ItemType Directory -Path $cacheDir -Force
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList $cacheDir | Out-Null
        }.GetNewClosure())

    $clearCacheButton.add_Click({
            $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
            if (Test-Path -LiteralPath $cacheDir) {
                try {
                    $files = Get-ChildItem -LiteralPath $cacheDir -Filter '*.json' -File -ErrorAction Stop
                    $count = $files.Count
                    $files | Remove-Item -Force -ErrorAction Stop
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Cache cleared. $count file(s) removed." -Level Info
                }
                catch {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to clear cache: $_" -Level Error
                }
            }
            else {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Cache directory does not exist. Nothing to clear.' -Level Info
            }
        }.GetNewClosure())

    # =========================================================================
    # Log Files Management: Open and Clear
    # =========================================================================
    $openLogsFolderButton.add_Click({
            $logsDir = Join-Path $env:LOCALAPPDATA 'EvergreenUI\Logs'
            try {
                if (-not (Test-Path -LiteralPath $logsDir)) {
                    $null = New-Item -ItemType Directory -Path $logsDir -Force -ErrorAction Stop
                }
                Start-Process -FilePath 'explorer.exe' -ArgumentList $logsDir -ErrorAction Stop | Out-Null
            }
            catch {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to open logs folder '$logsDir': $_" -Level Error
            }
        }.GetNewClosure())

    $clearLogsButton.add_Click({
            $logsDir = Join-Path $env:LOCALAPPDATA 'EvergreenUI\Logs'
            if (-not (Test-Path -LiteralPath $logsDir)) {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Logs directory does not exist. 0 file(s) removed.' -Level Info
                return
            }

            try {
                $logFiles = Get-ChildItem -LiteralPath $logsDir -Filter '*.log' -File -ErrorAction Stop
                $logFileCount = $logFiles.Count

                if ($logFileCount -eq 0) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'No log files found. 0 file(s) removed.' -Level Info
                    return
                }

                $logFiles | Remove-Item -Force -ErrorAction Stop
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Logs cleared. $logFileCount file(s) removed." -Level Info
            }
            catch {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to clear log files in '$logsDir': $_" -Level Error
            }
        }.GetNewClosure())

    Write-Verbose 'EvergreenUI: Settings feature registered.'
}
