# Navigation Feature Extraction from Start-EvergreenWorkbench.ps1

## Overview
The navigation feature manages the 8-view panel switching system using RadioButton controls (NavApps, NavDownload, NavLibrary, NavPackages, NavImport, NavInstall, NavSettings, NavUpdate, NavAbout) and the NavToggleButton for collapsing/expanding the navigation rail.

## Control References Needed

### Navigation RadioButtons (Checked handlers)
```powershell
$navToggleButton = $window.FindName('NavToggleButton')    # Hamburger button to collapse/expand
$navApps = $window.FindName('NavApps')                    # Apps tab
$navDownload = $window.FindName('NavDownload')            # Download queue tab
$navLibrary = $window.FindName('NavLibrary')              # Library management tab
$navPackages = $window.FindName('NavPackages')            # Packages/Import definitions tab
$navImport = $window.FindName('NavImport')                # Import tab (Intune/Nerdio/M365)
$navInstall = $window.FindName('NavInstall')              # Install/Local package tab
$navSettings = $window.FindName('NavSettings')            # Settings tab
$navUpdate = $window.FindName('NavUpdate')                # Update Evergreen tab
$navAbout = $window.FindName('NavAbout')                  # About tab
```

### Content Panels (Visibility controlled by nav buttons)
```powershell
$appsPanel = $window.FindName('AppsPanel')                # Apps tab content
$downloadPanel = $window.FindName('DownloadPanel')        # Download queue content
$libraryPanel = $window.FindName('LibraryPanel')          # Library content
$packagesPanel = $window.FindName('PackagesPanel')        # Packages/Import definitions content
$importPanel = $window.FindName('ImportPanel')            # Import tab content
$installPanel = $window.FindName('InstallPanel')          # Install tab content
$settingsPanel = $window.FindName('SettingsPanel')        # Settings content
$updatePanel = $window.FindName('UpdatePanel')            # Update content
$aboutPanel = $window.FindName('AboutPanel')              # About content
```

### NavRail Label Controls (for collapse/expand toggle)
```powershell
$rootGrid = $window.FindName('RootGrid')                  # Root grid with column definitions
# Column 0 = nav rail (width toggles between 70px and 180px)
# Labels: NavAppsLabel, NavDownloadLabel, NavLibraryLabel, NavPackagesLabel, 
#         NavImportLabel, NavInstallLabel, NavSettingsLabel, NavUpdateLabel, NavAboutLabel
```

---

## 1. Panel Visibility Map (Core Data Structure)

**Location in file**: Lines 6937-6945

```powershell
# Map: navigation button name => content panel control
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
```

---

## 2. Generic Checked Handler (Core Event Logic)

**Location in file**: Lines 6948-6959

This handler is attached to ALL navigation RadioButtons. It swaps panel visibility when any nav button is checked.

```powershell
$navCheckedHandler = {
    param($s, $e)
    foreach ($entry in $panelMap.GetEnumerator()) {
        $entry.Value.Visibility = if ($entry.Key -eq $s.Name) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
    }
}

# Register handler on ALL navigation buttons
foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navPackages, $navImport, $navInstall, $navSettings, $navUpdate, $navAbout)) {
    $navBtn.add_Checked($navCheckedHandler)
}
```

---

## 3. NavToggleButton Click Handler (Collapse/Expand Rail)

**Location in file**: Lines 6963-6972

Toggles nav rail width between 70px (icon only) and 180px (with labels).

```powershell
# Collapse/expand nav rail when hamburger button is clicked
# 72px leaves enough room for Segoe Fluent Icons glyph overhang when labels are hidden.
$navRailLabels = @('NavAppsLabel', 'NavDownloadLabel', 'NavLibraryLabel', 'NavPackagesLabel', 'NavImportLabel',
    'NavInstallLabel', 'NavSettingsLabel', 'NavUpdateLabel', 'NavAboutLabel') |
ForEach-Object { $window.FindName($_) }

$navToggleButton.add_Click({
    $navColumn = $rootGrid.ColumnDefinitions[0]
    if ($navColumn.Width.Value -gt 70) {
        # Collapse: narrow to 70px and hide labels
        $navColumn.Width = [System.Windows.GridLength]::new(70)
        foreach ($lbl in $navRailLabels) { $lbl.Visibility = [System.Windows.Visibility]::Collapsed }
    }
    else {
        # Expand: widen to 180px and show labels
        $navColumn.Width = [System.Windows.GridLength]::new(180)
        foreach ($lbl in $navRailLabels) { $lbl.Visibility = [System.Windows.Visibility]::Visible }
    }
})
```

---

## 4. Tab-Specific Checked Handlers (Lazy Loading & Initialization)

These handlers execute custom logic when each tab is first visited. They call feature-specific scriptblocks to load data or initialize resources.

### NavApps (Line 6974-6979)
```powershell
$navApps.add_Checked({
    if ($null -eq $syncHash.AppList -or $syncHash.AppList.Count -eq 0) {
        & $loadAppCatalog                    # Lazy-load app catalog on first visit
    }
})
```

### NavDownload (Line 6981-6983)
```powershell
$navDownload.add_Checked({
    & $refreshQueueView                     # Refresh queue display when tab is shown
})
```

### NavLibrary (Line 6985-6993)
```powershell
$navLibrary.add_Checked({
    # Restore library path from config if available
    if ([string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
        $libraryPathViewBox.Text = $syncHash.Config.LibraryPath
    }
    if (-not [string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
        & $refreshLibraryView                # Refresh library contents display
    }
})
```

### NavPackages (Line 6995-7047)
```powershell
$navPackages.add_Checked({
    # Load Import-tab dependent modules on first visit only
    if (-not $syncHash.ImportModulesInitialized) {
        Write-UILog -SyncHash $syncHash -Message 'Packages tab: initializing required modules...' -Level Info
        & $loadImportTabModules              # Load Intune/Nerdio/M365 modules
    }

    & $refreshImportAuthUi                  # Update auth status indicators
    & $refreshNerdioApiAuthUi
    & $refreshNerdioAzureAuthUi

    # Auto-load local definitions only - do not query Intune or Nerdio Manager.
    $savedIntunePath = if ($null -ne $syncHash.Config.IntuneSettings) {
        [string]$syncHash.Config.IntuneSettings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedIntunePath) -and
        (Test-Path -LiteralPath $savedIntunePath -PathType Container) -and
        @($syncHash.IntuneWin32Rows).Count -eq 0) {
        & $loadIntuneDefinitions             # Load Intune definitions from disk
    }

    $savedNerdioPath = if ($null -ne $syncHash.Config.NerdioSettings) {
        [string]$syncHash.Config.NerdioSettings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedNerdioPath) -and
        (Test-Path -LiteralPath $savedNerdioPath -PathType Container) -and
        @($syncHash.NerdioShellAppRows).Count -eq 0) {
        & $loadNerdioDefinitions             # Load Nerdio definitions from disk
    }

    $savedM365Path = if ($null -ne $syncHash.Config.M365Settings) {
        [string]$syncHash.Config.M365Settings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedM365Path) -and
        (Test-Path -LiteralPath $savedM365Path -PathType Container) -and
        @($syncHash.M365ConfigRows).Count -eq 0) {
        & $loadM365Configs                  # Load M365 configs from disk
    }
})
```

### NavImport (Line 7049-7100)
```powershell
$navImport.add_Checked({
    # Load Import-tab dependent modules on first visit only
    if (-not $syncHash.ImportModulesInitialized) {
        Write-UILog -SyncHash $syncHash -Message 'Import tab: initializing required modules...' -Level Info
        & $loadImportTabModules              # Load Intune/Nerdio/M365 modules
    }

    & $refreshImportAuthUi                  # Update auth status indicators
    & $refreshNerdioApiAuthUi
    & $refreshNerdioAzureAuthUi
    & $setImportProvider -Provider $syncHash.Config.ImportSettings.CurrentProvider

    # Auto-load local definitions only - do not query Intune or Nerdio Manager.
    # Skip if compare data is already populated to avoid redundant API calls.
    $savedIntunePath = if ($null -ne $syncHash.Config.IntuneSettings) {
        [string]$syncHash.Config.IntuneSettings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedIntunePath) -and
        (Test-Path -LiteralPath $savedIntunePath -PathType Container) -and
        @($syncHash.IntuneWin32Rows).Count -eq 0) {
        & $loadIntuneDefinitions
    }

    $savedNerdioPath = if ($null -ne $syncHash.Config.NerdioSettings) {
        [string]$syncHash.Config.NerdioSettings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedNerdioPath) -and
        (Test-Path -LiteralPath $savedNerdioPath -PathType Container) -and
        @($syncHash.NerdioShellAppRows).Count -eq 0) {
        & $loadNerdioDefinitions
    }

    $savedM365Path = if ($null -ne $syncHash.Config.M365Settings) {
        [string]$syncHash.Config.M365Settings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedM365Path) -and
        (Test-Path -LiteralPath $savedM365Path -PathType Container) -and
        @($syncHash.M365ConfigRows).Count -eq 0) {
        & $loadM365Configs
    }
})
```

### NavInstall (Line 7102-7117)
```powershell
$navInstall.add_Checked({
    & $setInstallElevationState             # Update elevation status indicator
    $savedInstallPath = if ($null -ne $syncHash.Config.IntuneSettings) {
        [string]$syncHash.Config.IntuneSettings.DefinitionsPath
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($savedInstallPath) -and
        (Test-Path -LiteralPath $savedInstallPath -PathType Container)) {
        & $loadInstallDefinitions            # Load Install definitions from disk
    }
    else {
        & $refreshInstallRows                # Refresh rows with current data
    }
})
```

### NavUpdate (Line 7119-7123)
```powershell
$navUpdate.add_Checked({
    if ($null -ne $syncHash.UpdateStatusLabel -and -not $syncHash.IsRunning) {
        $syncHash.UpdateStatusLabel.Text = 'Ready to run Update-Evergreen.'
    }
})
```

### NavAbout
Navigation to About tab requires no special handling (displayed statically).

---

## 5. Tab Visibility Control (Settings)

**Location in file**: Lines 2780-2820

Manages display/hide of Import and Install tabs based on settings toggles.

```powershell
$setImportTabVisibility = {
    param(
        [bool]$ShowImport,
        [bool]$ShowInstall
    )

    # Show/hide Import tab
    if ($null -ne $navImport) {
        $navImport.Visibility = if ($ShowImport) {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }

        # If Import tab is hidden and currently selected, switch to Apps
        if (-not $ShowImport -and $navImport.IsChecked) {
            $navApps.IsChecked = $true
        }
    }

    # Show/hide Install tab
    if ($null -ne $navInstall) {
        $navInstall.Visibility = if ($ShowInstall) {
            [System.Windows.Visibility]::Visible
        } else {
            [System.Windows.Visibility]::Collapsed
        }

        # If Install tab is hidden and currently selected, switch to Apps
        if (-not $ShowInstall -and $navInstall.IsChecked) {
            $navApps.IsChecked = $true
        }
    }

    # Invalidate startup view if it was a hidden tab
    $startupView = [string]$syncHash.Config.StartupView
    if (($startupView -eq 'Import' -and -not $ShowImport) -or 
        ($startupView -eq 'Install' -and -not $ShowInstall)) {
        $syncHash.Config.StartupView = 'Apps'
    }
}
```

---

## 6. Get Current Startup View Helper

**Location in file**: Lines 2823-2850

Determines which view is currently active by checking RadioButton.IsChecked state.

```powershell
$getCurrentStartupView = {
    if ($navDownload.IsChecked) {
        return 'Download'
    }
    elseif ($navLibrary.IsChecked) {
        return 'Library'
    }
    elseif ($navPackages.IsChecked) {
        return 'Packages'
    }
    elseif ($navImport.IsChecked) {
        return 'Import'
    }
    elseif ($navInstall.IsChecked) {
        return 'Install'
    }
    elseif ($navSettings.IsChecked) {
        return 'Settings'
    }
    elseif ($navUpdate.IsChecked) {
        return 'Update'
    }
    elseif ($navAbout.IsChecked) {
        return 'About'
    }

    return 'Apps'  # Default
}
```

---

## 7. Window.Loaded Event - Startup View Initialization

**Location in file**: Lines 6800-6835

Restores the user's last selected tab on application startup by checking `$syncHash.Config.StartupView`.

```powershell
$window.add_Loaded({
    # ... other initialization code ...
    
    switch ([string]$syncHash.Config.StartupView) {
        'Download' {
            $navDownload.IsChecked = $true
        }
        'Library' {
            $navLibrary.IsChecked = $true
        }
        'Packages' {
            $navPackages.IsChecked = $true
        }
        'Import' {
            # Only switch to Import if it's visible (enabled in settings)
            if ([bool]$syncHash.Config.ShowImportTab) {
                $navImport.IsChecked = $true
            }
            else {
                $navApps.IsChecked = $true
            }
        }
        'Install' {
            # Only switch to Install if it's visible (enabled in settings)
            if ([bool]$syncHash.Config.ShowInstallTab) {
                $navInstall.IsChecked = $true
            }
            else {
                $navApps.IsChecked = $true
            }
        }
        'Settings' {
            $navSettings.IsChecked = $true
        }
        'Update' {
            $navUpdate.IsChecked = $true
        }
        'About' {
            $navAbout.IsChecked = $true
        }
        default {
            $navApps.IsChecked = $true  # Default to Apps
        }
    }
})
```

---

## 8. Window.Closing Event - Persist Current View

**Location in file**: Lines 6840-6890 (within closing handler)

Saves the currently active view to config before window closes.

```powershell
# Inside window.add_Closing block:
$syncHash.Config.StartupView = & $getCurrentStartupView

# ... plus other cleanup code ...
```

---

## Dependencies on Feature Scriptblocks

The navigation handlers call these feature-specific scriptblocks (defined elsewhere):

| Scriptblock | Purpose | Dependencies |
|---|---|---|
| `$loadAppCatalog` | Fetch apps from Evergreen module | Apps feature |
| `$refreshQueueView` | Refresh download queue display | Download feature |
| `$refreshLibraryView` | Refresh library contents | Library feature |
| `$loadImportTabModules` | Load Intune/Nerdio/M365 modules | Import feature |
| `$refreshImportAuthUi` | Update Intune/Graph auth indicators | Import feature |
| `$refreshNerdioApiAuthUi` | Update Nerdio API auth indicators | Import feature |
| `$refreshNerdioAzureAuthUi` | Update Nerdio Azure auth indicators | Import feature |
| `$setImportProvider` | Switch import provider tab | Import feature |
| `$loadIntuneDefinitions` | Load Intune App.json definitions | Import feature |
| `$loadNerdioDefinitions` | Load Nerdio definitions | Import feature |
| `$loadM365Configs` | Load M365 configurations | Import feature |
| `$setInstallElevationState` | Update elevation status | Install feature |
| `$loadInstallDefinitions` | Load Install definitions | Install feature |
| `$refreshInstallRows` | Refresh Install rows display | Install feature |
| `$normalizeDirectoryPath` | Normalize directory paths | Settings feature |

---

## Integration Points

### Settings Tab Interaction
- **ShowImportTabToggle** and **ShowInstallTabToggle** changes must call `$setImportTabVisibility`
- Settings persistence must call `$getCurrentStartupView` before saving

### Config Structure
```powershell
$syncHash.Config.StartupView           # Current startup view name (string)
$syncHash.Config.ShowImportTab         # Feature toggle (bool)
$syncHash.Config.ShowInstallTab        # Feature toggle (bool)
$syncHash.Config.ImportSettings        # Intune settings
$syncHash.Config.NerdioSettings        # Nerdio settings
$syncHash.Config.M365Settings          # M365 settings
$syncHash.Config.LibraryPath           # Library folder path
$syncHash.Config.IntuneSettings        # Intune settings
$syncHash.ImportCurrentProvider        # Active import provider (Auth/Intune/Nerdio/M365)
```

### State Variables
```powershell
$syncHash.ImportModulesInitialized     # Set by $loadImportTabModules
$syncHash.IntuneWin32Rows              # Used by NavPackages/NavImport to skip reloading
$syncHash.NerdioShellAppRows           # Used by NavPackages/NavImport to skip reloading
$syncHash.M365ConfigRows               # Used by NavPackages/NavImport to skip reloading
$syncHash.IsRunning                    # Prevents operations while UI is shutting down
```

---

## Key Implementation Patterns

### 1. Lazy Loading on First Tab Visit
Checks `$syncHash.<Feature>Initialized` or row count to avoid reloading data. This saves startup time and bandwidth.

### 2. Guard Against Hidden Tabs
Import and Install tabs can be disabled via settings. Navigation code checks visibility before switching and resets to Apps if the target tab is hidden.

### 3. Panel Visibility Pattern
Uses a `$panelMap` hashtable for O(1) visibility switching, avoiding repeated if/elseif chains.

### 4. Persistent Startup View
`$syncHash.Config.StartupView` is persisted to JSON on window close and restored on next startup.

### 5. Dispatcher Safety
Lazy-loaded operations use `New-WpfRunspace` for background tasks with `$syncHash.Window.Dispatcher.Invoke()` for UI updates.

---

## Summary

The navigation feature is relatively self-contained and handles:
1. **Panel visibility switching** via generic RadioButton.Checked handler
2. **NavRail collapse/expand** via hamburger button toggle
3. **Lazy loading** of feature data on first tab visit
4. **Tab visibility** based on feature settings
5. **Startup view restoration** from persisted config
6. **Status indicator updates** via feature-specific scriptblocks

**For migration to `Register-NavigationFeature.ps1`**:
- Extract all 9 RadioButton checked handlers and the toggle button handler
- Provide the `$panelMap` data structure
- Keep `$setImportTabVisibility` and `$getCurrentStartupView` scriptblocks
- Expose dependencies on feature scriptblocks via parameters
- Call feature registration functions before navigation registration
