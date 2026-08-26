function Register-NavigationFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the navigation system and view switching.

    .DESCRIPTION
    Sets up event handlers for the main navigation RadioButtons (Apps, Download, Library,
    Packages, Import, Install, Settings, Update, About) that control which panel is
    displayed. Also handles the nav toggle button that expands/collapses the nav sidebar.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for navigation.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract navigation controls
    $navToggleButton = $Controls.NavToggleButton
    $navApps = $Controls.NavApps
    $navDownload = $Controls.NavDownload
    $navLibrary = $Controls.NavLibrary
    $navPackages = $Controls.NavPackages
    $navImport = $Controls.NavImport
    $navInstall = $Controls.NavInstall
    $navSettings = $Controls.NavSettings
    $navUpdate = $Controls.NavUpdate
    $navAbout = $Controls.NavAbout

    # Panel references for view switching
    $appsPanel = $Controls.AppsPanel
    $downloadPanel = $Controls.DownloadPanel
    $libraryPanel = $Controls.LibraryPanel
    $packagesPanel = $Controls.PackagesPanel
    $importPanel = $Controls.ImportPanel
    $installPanel = $Controls.InstallPanel
    $settingsPanel = $Controls.SettingsPanel
    $updatePanel = $Controls.UpdatePanel
    $aboutPanel = $Controls.AboutPanel

    # Additional controls needed for navigation
    $rootGrid = $SyncHash.Window.FindName('RootGrid')
    $libraryPathViewBox = $Controls.LibraryPathViewBox
    $importProviderTabControl = $Controls.ImportProviderTabControl
    $themeComboBox = $Controls.ThemeComboBox
    $outputPathBox = $Controls.OutputPathBox
    $evergreenAppsPathBox = $Controls.EvergreenAppsPathBox
    $showImportTabToggle = $Controls.ShowImportTabToggle
    $showInstallTabToggle = $Controls.ShowInstallTabToggle
    $installHideIncompatibleArchitectureToggle = $Controls.InstallHideIncompatibleArchitectureToggle
    $logToggleButton = $Controls.LogToggleButton
    $logRowDef = $SyncHash.Window.FindName('LogRowDefinition')
    $copyLogButton = $Controls.CopyLogButton
    $saveLogButton = $Controls.SaveLogButton
    $logScrollViewer = $Controls.LogScrollViewer

    # Build panel visibility map for quick switching
    $panelMap = @{
        NavApps     = $appsPanel
        NavDownload = $downloadPanel
        NavLibrary  = $libraryPanel
        NavPackages = $packagesPanel
        NavImport   = $importPanel
        NavInstall  = $installPanel
        NavSettings = $settingsPanel
        NavUpdate   = $updatePanel
        NavAbout    = $aboutPanel
    }
    $SyncHash.PanelMap = $panelMap

    # Generic checked handler swaps panels based on which RadioButton was checked
    $navCheckedHandler = {
        param($s, $e)
        [void]$e
        foreach ($entry in $panelMap.GetEnumerator()) {
            $entry.Value.Visibility = if ($entry.Key -eq $s.Name) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }
        }
    }.GetNewClosure()

    # Attach generic checked handler to all 9 navigation RadioButtons
    foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navPackages, $navImport, $navInstall, $navSettings, $navUpdate, $navAbout)) {
        $navBtn.add_Checked($navCheckedHandler)
    }

    # NavToggleButton: Collapse/expand nav rail
    # 72px leaves room for Segoe Fluent Icons; 180px shows full labels
    $navRailLabels = @('NavAppsLabel', 'NavDownloadLabel', 'NavLibraryLabel', 'NavPackagesLabel', 'NavImportLabel',
        'NavInstallLabel', 'NavSettingsLabel', 'NavUpdateLabel', 'NavAboutLabel') |
        ForEach-Object { $SyncHash.Window.FindName($_) }

    $navToggleButton.add_Click({
            $navColumn = $rootGrid.ColumnDefinitions[0]
            if ($navColumn.Width.Value -gt 70) {
                $navColumn.Width = [System.Windows.GridLength]::new(70)
                foreach ($lbl in $navRailLabels) { $lbl.Visibility = [System.Windows.Visibility]::Collapsed }
            }
            else {
                $navColumn.Width = [System.Windows.GridLength]::new(180)
                foreach ($lbl in $navRailLabels) { $lbl.Visibility = [System.Windows.Visibility]::Visible }
            }
        }.GetNewClosure())

    # NavApps: Lazy-load app catalog on first visit
    $navApps.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            if ($null -eq $SyncHash.AppList -or $SyncHash.AppList.Count -eq 0) {
                & ($SyncHash['LoadAppCatalog'])
            }
        }.GetNewClosure())

    # NavDownload: Refresh queue view when shown
    $navDownload.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            & ($SyncHash['RefreshQueueView'])
        }.GetNewClosure())

    # NavLibrary: Restore path and refresh view
    $navLibrary.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            if ([string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
                $libraryPathViewBox.Text = $SyncHash.Config.LibraryPath
            }
            if (-not [string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
                & ($SyncHash['RefreshLibraryView'])
            }
        }.GetNewClosure())

    # NavPackages: Initialize Import tab modules and load saved definitions
    $navPackages.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            if (-not $SyncHash.ImportModulesInitialized) {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Packages tab: initializing required modules...' -Level Info
                & ($SyncHash['LoadImportTabModules'])
            }

            & ($SyncHash['RefreshImportAuthUi'])
            & ($SyncHash['RefreshNerdioApiAuthUi'])
            & ($SyncHash['RefreshNerdioAzureAuthUi'])

            # Auto-load local Intune definitions if path is configured
            $savedIntunePath = if ($null -ne $SyncHash.Config.IntuneSettings) {
                [string]$SyncHash.Config.IntuneSettings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedIntunePath) -and
                (Test-Path -LiteralPath $savedIntunePath -PathType Container) -and
                @($SyncHash.IntuneWin32Rows).Count -eq 0) {
                & ($SyncHash['LoadIntuneDefinitions'])
            }

            # Auto-load local Nerdio definitions if path is configured
            $savedNerdioPath = if ($null -ne $SyncHash.Config.NerdioSettings) {
                [string]$SyncHash.Config.NerdioSettings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedNerdioPath) -and
                (Test-Path -LiteralPath $savedNerdioPath -PathType Container) -and
                @($SyncHash.NerdioShellAppRows).Count -eq 0) {
                & ($SyncHash['LoadNerdioDefinitions'])
            }

            # Auto-load local M365 configurations if path is configured
            $savedM365Path = if ($null -ne $SyncHash.Config.M365Settings) {
                [string]$SyncHash.Config.M365Settings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedM365Path) -and
                (Test-Path -LiteralPath $savedM365Path -PathType Container) -and
                @($SyncHash.M365ConfigRows).Count -eq 0) {
                & ($SyncHash['LoadM365Configs'])
            }
        }.GetNewClosure())

    # NavImport: Similar to NavPackages but also sets the import provider
    $navImport.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            if (-not $SyncHash.ImportModulesInitialized) {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Import tab: initializing required modules...' -Level Info
                & ($SyncHash['LoadImportTabModules'])
            }

            & ($SyncHash['RefreshImportAuthUi'])
            & ($SyncHash['RefreshNerdioApiAuthUi'])
            & ($SyncHash['RefreshNerdioAzureAuthUi'])
            & ($SyncHash['SetImportProvider']) -Provider $SyncHash.Config.ImportSettings.CurrentProvider

            # Auto-load local Intune definitions if path is configured and rows not already loaded
            $savedIntunePath = if ($null -ne $SyncHash.Config.IntuneSettings) {
                [string]$SyncHash.Config.IntuneSettings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedIntunePath) -and
                (Test-Path -LiteralPath $savedIntunePath -PathType Container) -and
                @($SyncHash.IntuneWin32Rows).Count -eq 0) {
                & ($SyncHash['LoadIntuneDefinitions'])
            }

            # Auto-load local Nerdio definitions if path is configured and rows not already loaded
            $savedNerdioPath = if ($null -ne $SyncHash.Config.NerdioSettings) {
                [string]$SyncHash.Config.NerdioSettings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedNerdioPath) -and
                (Test-Path -LiteralPath $savedNerdioPath -PathType Container) -and
                @($SyncHash.NerdioShellAppRows).Count -eq 0) {
                & ($SyncHash['LoadNerdioDefinitions'])
            }

            # Auto-load local M365 configurations if path is configured and rows not already loaded
            $savedM365Path = if ($null -ne $SyncHash.Config.M365Settings) {
                [string]$SyncHash.Config.M365Settings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedM365Path) -and
                (Test-Path -LiteralPath $savedM365Path -PathType Container) -and
                @($SyncHash.M365ConfigRows).Count -eq 0) {
                & ($SyncHash['LoadM365Configs'])
            }
        }.GetNewClosure())

    # NavInstall: Update elevation state and load definitions
    $navInstall.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            & ($SyncHash['SetInstallElevationState'])
            $savedInstallPath = if ($null -ne $SyncHash.Config.IntuneSettings) {
                [string]$SyncHash.Config.IntuneSettings.DefinitionsPath
            } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($savedInstallPath) -and
                (Test-Path -LiteralPath $savedInstallPath -PathType Container)) {
                & ($SyncHash['LoadInstallDefinitions'])
            }
            else {
                & ($SyncHash['RefreshInstallRows'])
            }
        }.GetNewClosure())

    # NavUpdate: Set status message
    $navUpdate.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            if ($null -ne $SyncHash.UpdateStatusLabel -and -not $SyncHash.IsRunning) {
                $SyncHash.UpdateStatusLabel.Text = 'Ready to run Update-Evergreen.'
            }
        }.GetNewClosure())

    # NavSettings: Populate settings form with current config values
    $navSettings.add_Checked({
            if ($SyncHash.ContainsKey('IsInitializing') -and [bool]$SyncHash['IsInitializing']) { return }
            $outputPathBox.Text = $SyncHash.Config.OutputPath
            $evergreenAppsPathBox.Text = (& ($SyncHash['GetEvergreenAppsPath']))

            $themeComboBox.SelectedIndex = if ([string]$SyncHash.Config.Theme -eq 'Dark') { 1 } else { 0 }
            if ($null -ne $showImportTabToggle) {
                $showImportTabToggle.IsChecked = [bool]$SyncHash.Config.ShowImportTab
            }
            if ($null -ne $showInstallTabToggle) {
                $showInstallTabToggle.IsChecked = [bool]$SyncHash.Config.ShowInstallTab
            }
            & ($SyncHash['SetImportTabVisibility']) -ShowImport ([bool]$SyncHash.Config.ShowImportTab) -ShowInstall ([bool]$SyncHash.Config.ShowInstallTab)
        }.GetNewClosure())

    # ShowImportTabToggle: Toggle visibility of Import and Packages tabs
    if ($null -ne $showImportTabToggle) {
        $showImportTabToggle.add_Click({
                $showImport = [bool]$showImportTabToggle.IsChecked
                $SyncHash.Config.ShowImportTab = $showImport
                & ($SyncHash['SetImportTabVisibility']) -ShowImport $showImport -ShowInstall ([bool]$SyncHash.Config.ShowInstallTab)
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    # ShowInstallTabToggle: Toggle visibility of Install/Packages tab
    if ($null -ne $showInstallTabToggle) {
        $showInstallTabToggle.add_Click({
                $showInstall = [bool]$showInstallTabToggle.IsChecked
                $SyncHash.Config.ShowInstallTab = $showInstall
                & ($SyncHash['SetImportTabVisibility']) -ShowImport ([bool]$SyncHash.Config.ShowImportTab) -ShowInstall $showInstall
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    # InstallHideIncompatibleArchitectureToggle: Filter Install rows by architecture
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

    Write-Verbose 'EvergreenUI: Navigation feature registered.'
}
