# Changelog

## [1.0.13] - 2026-03-29

### Added
- Import tab / Microsoft 365 Apps: new sub-tab for packaging and importing Microsoft 365 Apps configurations into Intune and Nerdio Manager
- Import tab / Microsoft 365 Apps: browse a directory of Office Deployment Tool XML configuration files; table displays Filename, Display Name, Products, and Status columns
- Import tab / Microsoft 365 Apps: Channel selector and Company Name input in the action bar; version label next to the Channel selector shows the latest Evergreen version for the selected channel
- Import tab / Microsoft 365 Apps: separate Intune and Nerdio Manager connection status indicators in the configuration status bar
- Import tab / Microsoft 365 Apps: **Import Intune Win32App** and **Import Nerdio Manager Shell App** buttons enabled only when a valid configuration is selected and the respective service is authenticated
- Import tab / Microsoft 365 Apps: build workflow downloads `setup.exe` via Evergreen, copies and updates the configuration XML with the selected Channel, TenantId, and CompanyName, then packages with `New-IntuneWin32AppPackage`
- Import tab / Microsoft 365 Apps: `App.json` is copied from the bundled `Resources/m365-app.json` template into the package directory and updated with version, display name, GUID, program commands, architecture, and detection rule values before Intune upload
- `Get-M365AppConfigurations` private function: parses Office Deployment Tool XML files, extracts products, architecture, and VDI flag, validates Configuration GUIDs, and returns display names in `"Products: Environment, Architecture"` format
- `Invoke-M365AppPackageBuild` private function: full package build pipeline for Microsoft 365 Apps including Evergreen download, XML update, and `.intunewin` packaging; produces an updated `App.json` alongside the package
- `Get-UIConfig`: `M365Settings` block added with `DefinitionsPath`, `PackageOutputPath`, `Channel`, and `CompanyName` defaults

### Changed
- Import tab: Microsoft 365 Apps sub-tab inserted between Nerdio Manager Shell Apps and Authentication tabs
- Import tab / Microsoft 365 Apps: Channel and Company Name XML placeholders (`#Channel`) are resolved at packaging time from the user's dropdown selection; Channel is no longer read from the XML for display purposes
- Import tab / Intune and Nerdio Manager: connection status indicators updated to match the Microsoft 365 Apps tab — 9×9 ellipse with border stroke, service-name prefix label ("Intune:" / "Nerdio Manager:"), and status text right-aligned in the count bar
- Import tab / Intune and Nerdio Manager: count bar `DockPanel` changed to `LastChildFill="False"` so the right-docked status indicators correctly snap to the right edge
- Import tab / Microsoft Intune Win32 Apps: Import Win32 app button height pinned to 32 px to match the Nerdio Manager Shell Apps tab
- Nerdio Manager authentication: `Connect-Nme` called with `-ErrorAction Stop` so non-terminating errors are promoted to terminating and caught by the existing error handler; return value checked for null with an explicit failure message; `Set-NmeCredentials` also called with `-ErrorAction Stop`; module-load failure path now writes to the progress log

### Fixed
- Nerdio Manager authentication: failures produced no log output when the NerdioShellApps module could not be loaded silently (empty path) or when `Connect-Nme` wrote non-terminating errors rather than throwing — both cases are now logged

## [1.0.12] - 2026-03-28

### Added
- Apps tab: **Add to Library** button writes the selected application and active filter state to `EvergreenLibrary.json` in the configured library path; the button is only enabled when an app is loaded and a valid `EvergreenLibrary.json` exists
- Apps tab: inline status label next to the action buttons confirms a successful **Add to Library** operation with the app name (auto-clears after 3 seconds) or shows an error in red if the write fails
- Library tab: indeterminate progress bar appears below the path controls while **Update Library** is running and collapses on completion

### Fixed
- Library tab: warnings emitted by `Get-EvergreenLibrary` (e.g. missing app directories) are now captured and forwarded to the workbench log instead of being written to the PowerShell host

## [1.0.11] - 2026-03-27

### Added
- Import tab / Microsoft Intune: `DisplayName` property added to all comparison rows and used as the **App** column — matched rows show the Intune app name, unmatched rows show the definition name
- Import tab / Nerdio Shell Apps: **Versions** column shows the total count of versions present on the Shell App

### Changed
- Import tab / Microsoft Intune: columns reduced from 9 to 6 — **App**, **Publisher**, **Intune Version**, **Latest**, **Status**, **Action**; removed Definition, Matched, Update Required, and Definition Version columns
- Import tab / Microsoft Intune: Action column values rationalised — `Import new app` (definition not in Intune), `Import new version and supersede` (matched app with update available), `Fix in definition` (duplicate GUID across definitions), `-` (no action required)
- Import tab / Microsoft Intune: row colours updated — green tint for matched apps that are current; amber tint for matched apps with an update available; transparent background for all other rows
- Import tab / Nerdio Shell Apps: columns restructured — **App**, **Publisher**, **Shell App**, **Versions**, **Shell App Version**, **Latest**, **Status**, **Action**; removed Definition App column
- Import tab / Nerdio Shell Apps: Action column values — `Update`, `Import`, or `-`; same row colour scheme as the Intune tab
- Import tab / Authentication: sign-in buttons are disabled while a session is already authenticated and re-enabled when the user signs out
- Settings tab: Preferences section reorganised — Theme selector occupies the left half of the row; **Show Import tab** and **Show Install tab** toggle switches are grouped on the right half within the same row
- Import tab / Microsoft Intune: `IsUpdate` flag passed to the import runspace is now derived from `IsMatched` and `UpdateRequired` row properties rather than the `ImportAction` string, making the distinction between a new app and a supersedence update independent of the display label

### Fixed
- Install tab: **Load definitions** now correctly populates the Latest Version column from the cache; `ConvertFrom-Json` was silently converting ISO 8601 timestamp strings into `[DateTime]` objects, causing all `TryParseExact` calls to return `$false` and produce zero cache hits with no warning in the log

## [1.0.10] - 2026-03-27

### Added
- Install tab: latest-version results are now cached to `%APPDATA%\EvergreenUI\install-latest-cache.json`; the cache is loaded automatically when clicking **Load definitions** so the Latest Version column is populated without re-querying Evergreen
- Apps view: Language filter ComboBox added to the filter panel

### Changed
- Settings tab: **Show Import tab** and **Show Install tab** options are now Fluent-style toggle switches with the toggle on the right side of the label, and both default to enabled
- Settings tab: Log Verbosity option removed; Theme selector now spans the full settings panel width

### Fixed
- Install tab: cache timestamp parsing failed when `ConvertFrom-Json` auto-converted ISO 8601 date strings to `[DateTime]` objects, causing Latest Version to remain blank after loading definitions even when a valid cache existed; parsing now handles both raw `[DateTime]` values and string representations

## [1.0.9] - 2026-03-20

### Added
- Install tab: full local package installation workflow driven by `App.json` definition files; supports loading definitions, detecting installed versions, fetching latest versions via Evergreen, and installing or updating packages
- Install script execution via `Install.ps1` with a centralized working directory per package

### Changed
- Public entry point renamed to `Start-EvergreenWorkbench`; the previous name `Start-EvergreenUI` is no longer exported
- Install latest-version cache stored under `%APPDATA%\EvergreenUI` for consistent per-user persistence
- Install definitions list sorted by publisher then application name

## [1.0.8] - 2026-03-17

### Changed
- Internal refactor of `Start-EvergreenWorkbench` to improve code organisation and maintainability

## [1.0.7] - 2026-03-16

### Added
- Update tab: panel and background runner for updating the Evergreen PowerShell module itself via `Update-Evergreen`
- Download progress bar showing per-file and overall queue progress
- `Sha` and `Sha1` hash properties added as display-only columns in the Apps results grid

### Fixed
- Pester test suite updated to reflect current module structure

## [1.0.6] - 2026-03-16

### Added
- Import tab with two provider workflows: **Nerdio Manager** and **Intune Win32 packaging**
- Intune: Win32 app packaging helper, reconciliation UI for comparing Intune inventory against Evergreen, and Graph API import via `Invoke-IntuneGraphWin32Import`
- Nerdio: Shell Apps support with version comparison, **Compare updates** feature for reconciling Nerdio inventory against Evergreen, and Azure/Entra ID sign-in flows
- Nerdio: storage account settings for uploading packaged apps
- About view displaying Evergreen module version, Workbench version, and system metadata
- Status colour brushes for both light and dark themes (accent, success, warning, error)
- Async background loading for Intune and Nerdio provider data using isolated STA runspaces
- `ShowImportTab` config property to control Import tab visibility from Settings
- `DefinitionsPath` config property for Intune Win32 definition files

### Changed
- Settings tab refactored to a multi-column grid layout
- Status indicators in app result lists now use themed brushes instead of hardcoded colours
- Azure context autosave enabled for background runspaces so authentication persists between operations
- `Get-EvergreenApp` used in place of direct Evergreen calls for consistent result handling

## [1.0.5] - 2026-03-15

### Added
- NerdioShellApps PowerShell module bundled under `support/` for managing Nerdio Shell App versions

### Changed
- Config file renamed from `config.json` to `settings.json`; existing config is migrated automatically
- Log panel visibility (expanded / collapsed) now persisted in settings across sessions
- Settings panel wrapped in a **General** section header for clarity
- Theme selector changed from a toggle button to a ComboBox (`Light` / `Dark`)

## [1.0.4] - 2026-03-14

### Added
- `Cmd` log level: PowerShell commands executed by the UI are now logged to the progress log panel for auditability

### Changed
- Renamed public entry point from `Start-EvergreenUI` to `Start-EvergreenWorkbench` to align with the Evergreen Workbench product name
- Fixed double-wrapped JSON result arrays returned by some Evergreen app queries

## [1.0.3] - 2026-03-14

### Changed
- Removed box-drawing ASCII characters from inline comments throughout the codebase
- Normalised path handling to remove trailing slashes and mixed separators
- Cleaned up module init script (`EvergreenUI.psm1`)
- Added UI screenshot to README
- Removed the static HTML prototype (`prototype/EvergreenUI-Prototype.html`)

## [1.0.2] - 2026-03-14

### Added
- **Export CSV**: Apps view results can be exported to a CSV file via the toolbar
- **Open folder** button in the Downloads view to open the output directory in Explorer
- Library GridView is now fully dynamic — columns are generated from the properties returned by Evergreen rather than being hardcoded

### Fixed
- Prevented duplicate entries appearing in the download queue when the same app is added multiple times
- Improved WPF `Dispatcher.Invoke` usage to prevent cross-thread UI update exceptions

### Changed
- Visual polish pass across all views: spacing, typography, border colours, and control sizing

## [1.0.1] - 2026-03-14

### Added
- Section headers and separators in the Apps and Library views
- **Update** button in the Library view to refresh the library from disk
- DWM title bar accent colour support for a native Windows 11 appearance
- XAML moved out of the PowerShell script and into a dedicated `Resources/EvergreenUI.xaml` file

### Changed
- TextBox control template redesigned to match Fluent styling
- Apps list and Library list visual layout overhauled

## [1.0.0] - 2026-03-13

### Added
- Initial public release published to PowerShell Gallery as a pre-release module
- **Apps tab**: browse 500+ applications from the Evergreen catalog; dynamic filter panel built from app result properties; multi-select download queue
- **Download tab**: background download queue with per-file progress, output path configuration, and post-download folder access
- **Library tab**: view and manage a local Evergreen app library from a configured path
- **Settings tab**: configure output path, library path, and UI theme (light / dark)
- `Start-EvergreenWorkbench` as the single exported public function
- STA threading model with `$syncHash` for safe cross-runspace UI updates via `Dispatcher.Invoke`
- Light and dark Fluent-style WPF themes
- User configuration persisted to `%APPDATA%\EvergreenUI\settings.json`
- GitHub Actions workflows for automatic tagging on version bump and publishing to PowerShell Gallery
