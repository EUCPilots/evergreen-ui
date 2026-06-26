# Changelog

## [1.1.25]

### New Packages workflow and navigation updates
- Added a new Packages top-level view to centralize package definition and output settings.
- Moved key package-related controls out of other views into this dedicated area.
- Updated navigation and startup behavior to support the new Packages view cleanly.
- Added package definition counts and richer status presentation across Intune, Nerdio, and M365 package areas.

### Microsoft 365 packaging improvements
- Added Import for option with Single session and Multi-session modes.
- Propagated session mode into SharedComputerLicensing handling during package build.
- Updated M365 config parsing to include ExcludedProducts and surfaced this in the UI.
- Switched M365 versioning to use downloaded setup.exe file version where possible.
- Added package description metadata note containing setup.exe version, SharedComputerLicensing value, and source XML name.
- Improved M365 tables and labels for better clarity.

### Intune Win32 import enhancements
- Extended import logic to map and send custom requirement rules (file, registry, script) into Graph payloads.
- Added assignment creation support (AllDevices, AllUsers, Group) with assignment settings.
- Added install-time/date handling and restart-related assignment behavior support.
- Split Intune loading indicators into separate Import and Definitions states for clearer feedback.
- Improved comparison and import action UI wording/flow.

### Install workflow reliability and compatibility
- Added Hide incompatible architecture option for local install lists.
- Improved architecture compatibility handling in install rows.
- Enhanced local detection to support multiple registry schema variants and stronger numeric/operator comparisons.
- Improved behavior for installed-but-not-detected edge cases when latest version is known or unavailable.
- Consolidated install definitions source with Intune definitions path workflow.

### UI/theme and usability polish
- Added broader UI text, spacing, column width, and label updates.
- Added or refined loading/status panels across major views.
- Switched various controls to FluentButton variants for consistency.
- Aligned dark theme base to Windows 11 dark palette.
- Disabled forced WPF SoftwareOnly rendering path (commented fallback retained).
- Reordered import provider tabs and made Authentication the default/fallback position.

### Behavioral Notes
- Import provider tab order changed; Authentication is now the first/default provider.
- Install definitions are now driven by the package definitions path flow rather than a standalone install path field.
- Several labels/button captions were updated for consistency and discoverability.

## [1.0.24] - 2026-07-02

### Added

- Bump to initial release version.

### Changed

- Compute local architecture from PROCESSOR_ARCHITECTURE and read definition architecture from RequirementRule.Architecture. Determine compatibility (treat '-', empty, 'All' or 'x86,x64,arm64' as compatible; otherwise split comma lists and match against local arch). Mark definitions with incompatible architectures by setting an explicit status and 'Incompatible' action before detection is attempted.
- Introduce a dedicated RowHoverBrush resource in both Set-LightTheme.ps1 and Set-DarkTheme.ps1 (light: #D9F2EF, dark: #30504C) and update EvergreenUI.xaml to replace AccentLightBrush with RowHoverBrush for IsMouseOver triggers in row/list templates. This decouples hover background from the accent color, ensuring consistent and appropriate hover visuals across light and dark themes.
- Introduce a new 'Authentication' import provider and make it the default/fallback. Updates Get-UIConfig to set ImportSettings.CurrentProvider to 'Authentication' when missing. Update Start-EvergreenWorkbench to resolve empty or unknown providers to 'Authentication', add an explicit 'Authentication' case, map it to tab index 3, and adjust the tab-selection handler so unknown indices fall back to 'Authentication' (and M365 is now index 2). These changes enable a shared Authentication tab and use it as the default provider.

## [1.0.23] - 2026-06-02

### Added

- Start-EvergreenWorkbench.ps1: introduce an Architecture field (default '-') and populate it from DefinitionObject.Application.Architecture when present, then include it in the PSCustomObject rows. EvergreenUI.xaml: add an "Architecture" GridView column bound to Architecture, and adjust the navigation radio buttons (swap/update icons and labels) so Update and Settings entries render correctly.

## [1.0.22] - 2026-06-02

### Added

- `Resources/Install.ps1`: generic install script that drives app installation from `Install.json`; a simple alternative to PSAppDeployToolkit for definitions that do not ship their own install script; writes CMTrace-compatible log entries via an internal `Write-LogFile` function; restarts in a 64-bit PowerShell session automatically when invoked from a 32-bit process
- `Invoke-IntunePackageBuild`: copies `Install.ps1` from module Resources into the staging source path before packaging; skipped for PSADT packages (detected by the presence of `Invoke-AppDeployToolkit.ps1`); copy is best-effort and logs a warning on failure without aborting the build
- Import tab / Microsoft Intune Win32 Apps: **Architecture** column added to the definitions list view; value is read from `Application.Architecture` in each definition's `App.json` and shown as `-` when absent

### Changed

- Import tab / Microsoft Intune Win32 Apps: **Import** button label updates dynamically -- shows "Import Win32 app" for a single selection and "Import N Win32 apps" when multiple actionable rows are selected; button enabled state now uses `@(...)` array coercion and `.Count -gt 0` instead of a `$null` check to handle single-item selections correctly
- Import tab / Microsoft Intune Win32 Apps: multi-app import loop now stops on the first failure (`break`) instead of skipping to the next item (`continue`); a `StoppedEarly` flag is set on the result object; the completion log message reports skipped count and uses Warning level when stopped early

## [1.0.21] - 2026-06-02

### Added

- Import tab / Microsoft Intune Win32 Apps: **Update definitions** button (`IntuneUpdateDefinitionsButton`) added to the action bar; invokes `Invoke-IntuneDefinitionUpdate` in a background STA runspace via the standard `New-WpfRunspace` + `DispatcherTimer` poll pattern; the definitions list is reloaded automatically on completion; the button is disabled while the operation is running
- `Invoke-IntuneDefinitionUpdate` private function: resolves the latest package version for each definition via `Get-IntunePackageLatestVersion` and updates `App.json` (`PackageInformation.Version` and `PackageInformation.SetupFile`) and detection rule version values in place; also updates `Source\Install.json` when present; updates are best-effort per-definition and results are returned as `PSCustomObject`s

### Changed

- `Invoke-IntuneGraphWin32Import`: `RequirementRule.Architecture` is now parsed as a single value or a comma-separated list and mapped to the Graph API string enum (`x64`, `x86`, `arm64`, or `x86,x64,arm64`); multiple or unspecified architectures resolve to `x86,x64,arm64`; the payload key was renamed from `applicableArchitectures` to `allowedArchitectures` to match the current Graph API schema; a `Write-UILog` entry is written for the resolved value
- XAML / Import tab / Microsoft Intune Win32 Apps: **Load definitions** button labels renamed to **Reload definitions**; App column in the definitions list widened; an extra grid column added to accommodate the new Update definitions button
- XAML / column widths: App columns widened (200 px to 300 px, 155 px to 300 px, 190 px to 300 px), Publisher (130 px to 140 px), Installed and Latest (100 px to 140 px), and Status (170 px to 190 px) across the Install and Import list views to reduce text truncation
- XAML / layout and typography: window font updated to `"Segoe UI Variable Text, Segoe UI"` and base `FontSize` increased to 14; several secondary labels increased from 11 to 12; status bar base height increased from 40 to 48 px; control top margins tightened from 18 to 16 px; `MinHeight` set to 32 on several controls; scrollbar thickness reduced from 10 to 8
- XAML / `CheckBox` control template: outer grid and box sizes increased; border stroke thickness and colours revised; indeterminate dash widened; hover and checked state triggers added; high-contrast `DataTrigger` added for accessibility
- `Start-EvergreenWorkbench`: log panel row height save and restore logic updated to account for the new 48 px status bar base height

## [1.0.20] - 2026-04-17

### Added

- `Invoke-M365AppShellAppBuild` private function: downloads `setup.exe` for Microsoft 365 Apps via Evergreen, updates the install XML with the caller-supplied Channel, TenantId, and CompanyName, and produces a zip archive containing `setup.exe`, `Install-Microsoft365Apps.xml`, and `Uninstall-Microsoft365Apps.xml` for Nerdio Shell App upload; no IntuneWin32App dependency

### Changed

- Import tab / Microsoft 365 Apps: **Import Nerdio Manager Shell App** workflow replaced to follow the same pattern as the Nerdio Manager Shell Apps tab import; the workflow now reads Shell App definition files (`Definition.json`, `Detect.ps1`, `Install.ps1`, `Uninstall.ps1`) from a `shell-app` subdirectory alongside the M365 XML configuration files, validates all four files are present before starting, builds a zip archive of `setup.exe` and the configuration XMLs via `Invoke-M365AppShellAppBuild`, loads the definition via `Get-ShellAppDefinition`, sets the Shell App name from the selected configuration display name, and creates the Shell App via `New-ShellApp -Definition -AppMetadata`; the IntuneWin32App module is no longer required for this workflow

## [1.0.19] - 2026-04-07

### Added

- Nerdio Manager / Shell Apps tab: **Import New App** (`NerdioImportNewButton`) fully implemented; creates a new Shell App in Nerdio Manager via `New-ShellApp` (POST `/api/v1/shell-app`) using the same async runspace pattern as the Add Version workflow; reads the Shell App definition and scripts via `Get-ShellAppDefinition`, resolves the latest Evergreen app metadata via `Get-AppMetadata`, and automatically refreshes the Shell App list on success; the "planned for a future release" tooltip removed from the button in XAML
- Apps tab / App Detail: **Last refresh** timestamp added to the app detail header (`AppLastRefreshedLabel`); displays the cache file `LastWriteTime` formatted with `'g'` after a fresh app detail fetch or when loading from cache; the label is hidden when no app is selected or no cache exists

### Changed

- Import tab / Compare: `IntuneCompareHasRun` and `NerdioCompareHasRun` flags added to `$syncHash` to track whether a comparison has been run; import actions and status prompts show "Compare..." and suppress import buttons until a compare has completed; definitions are only marked new or importable after a compare is run; Intune matched-state status text changed to "Matched (No update required)"; row background brushes for Import and Match states updated and a visual cue added for the pending-compare Intune state
- XAML / startup palette: safe-startup brush values in `EvergreenUI.xaml` aligned with `Set-LightTheme.ps1` -- window/background, primary/secondary text, accent (and hover/light variant), control border, secondary button background/border, and all status color resources updated; theme functions continue to override these values on `Loaded`
- XAML / `ListViewItem` control template: hardcoded `Transparent` background on the `ListViewItem` `ControlTemplate` `Border` replaced with `{TemplateBinding Background}` so style- or runtime-assigned background values are respected and can override the template default
- XAML / spacing: left margin added to several buttons across the Import and Library tabs for consistent spacing
- `EvergreenUI.psd1`: PSData `Tags` updated -- `WPF` and `EUC` removed; `MSI` added
- Documentation: module help XML and README docs URL updated

### Fixed

- Import tab / collection counts: pipelines and collections not wrapped in `@(...)` before accessing `.Count` returned incorrect counts or missed conditional loads for Intune, Nerdio, and Microsoft 365 data when a query returned a single item or null; all affected `.Count` accesses now use `@(...)` array coercion to ensure correct behavior

## [1.0.18] - 2026-04-05

### Added

- About panel: **Required Modules** section added showing module name and installed version for all modules the Import tab depends on (IntuneWin32App, NerdioShellApps, Microsoft.Graph.Authentication, Az.*)
- Import tab: module-state tracking flags added to `$syncHash` (`EvergreenModuleLoaded`, `MgGraphModuleLoaded`, `IntuneWin32AppLoaded`, `AzModulesLoaded`, `NerdioShellAppsLoaded`, `ImportModulesInitialized`); Import tab action and sign-in buttons are disabled until the required modules are confirmed loaded

### Changed

- Import tab: IntuneWin32App, NerdioShellApps, Microsoft.Graph.Authentication, and Az.* module loading deferred from startup to a one-shot `loadImportTabModules` scriptblock that fires on the first visit to the Import tab, keeping startup fast for users who never open import workflows; the Evergreen module continues to load eagerly at startup with a gold-to-green status dot transition
- Import tab: all three sign-in operations (Intune/MgGraph, Nerdio API, Nerdio Azure) moved from the WPF dispatcher thread into background STA runspaces using the existing `New-WpfRunspace` + `DispatcherTimer` poll pattern; `Invoke-AzureSignIn.ps1` bare `Import-Module` calls wrapped with `Get-Module` guards to skip modules already loaded by `loadImportTabModules`
- XAML / Library list views: several `GridView` column widths resized for better layout -- Filename 180 px -> 300 px, Display Name 320 px -> 380 px, Products 220 px -> 300 px
- XAML / Import tab: Intune import button renamed from "Import Intune Win32App" to "Import Intune Win32 App"; button style changed from `FluentButton` to `FluentSecondaryButton`; multiple "Intune" labels updated to "Microsoft Intune" for consistency; Azure sign-in label shortened; Azure Storage label expanded to clarify scope; BetaChannel combo option removed
- XAML / Library tab: New and Open Folder button `x:Name` and `Content` values swapped to match their actual actions
- XAML / grid splitter: row height reduced from 8 to 3 for tighter layout
- XAML / spacing: horizontal spacing unified -- `TextBox` Padding set to `8,0,0,0`; placeholder `TextBlock` left margins reduced from 10 to 8 across search, path, and tenant ID fields; explicit `Margin` attributes removed from several buttons so they inherit layout spacing
- Nav rail: collapsed width increased from 64 px to 70 px to prevent Segoe Fluent Icons glyph overhang clipping when labels are hidden

### Fixed

- Import tab sign-in operations blocked the WPF dispatcher thread when OAuth redirects failed (e.g. "localhost refused to connect"), causing the UI to hang; sign-in now runs in a background STA runspace so the UI remains responsive regardless of redirect outcome

## [1.0.17] - 2026-04-04

### Added

- Apps tab: favourite apps -- users can star or unstar any application from the app list sidebar; favourited apps are pinned to the top of the list and sorted alphabetically among themselves; a filled star in the accent colour marks a favourite and a hover outline star appears on non-starred items to add them; favourites persist across sessions via `FavouriteApps` in `settings.json`
- Apps tab / Versions list: column visibility toggle -- right-click a column header to show or hide optional columns via a context menu; column widths are saved and restored across toggles via `VersionsColSavedWidths`; structural columns (Version, URI) are excluded from toggling
- Settings: Logs section added with two actions: **Open Logs Folder** opens (and creates if absent) `%LocalAppData%\EvergreenUI\Logs` in File Explorer; **Clear Log Files** deletes all `*.log` files in that folder and reports the count removed

### Changed

- XAML: Fluent styles hardened for focus, contrast, and startup reliability -- transparent bootstrap brushes replaced with safe default colours to prevent an unstable first paint; a shared keyboard focus visual style is applied across interactive controls and list items; the toggle switch gains a visible keyboard focus ring in its control template; high-contrast-safe style triggers added using system brushes for key control states; nav icons migrated from inline geometry to Segoe Fluent Icons glyphs with a Segoe MDL2 Assets fallback for Windows 10 compatibility
- XAML / filter panel: `CheckBox` control template revamped with an explicit focus ring, refined check and indeterminate visuals, correct disabled-state handling, and improved content alignment; `AutomationProperties.Name` is now set on generated filter checkboxes so screen readers announce "DisplayName: Value"; `RenderOptions.ProcessRenderMode` is set to `SoftwareOnly` at startup (best-effort, non-fatal) to avoid render-target quota failures on GPUs that reject hardware acceleration
- XAML: `FluentContextMenu` and `FluentMenuItem` named styles added to `Window.Resources`; runtime-generated context menus (column toggle, other right-click menus) use these styles via `TryFindResource` with a null guard so the change is backwards-compatible if a style is absent
- Apps tab / Versions list: `Md5` added to the display-only property set in `Get-FilterableProperties`; MD5 checksums are now treated as display-only columns consistent with `Sha`, `Sha1`, and `Sha256`
- Update tab: `ClearUpdateOutputButton` and its `Click` event handler removed; the control was unreferenced and served no function

## [1.0.16] - 2026-04-02

### Added

- Apps tab / Download Queue: **Path** column added to the download queue table; the column is empty while an item is queued and is populated with the saved file path once the download completes
- Column sorting added to the Versions, Download Queue, Library Contents, Library Details, Nerdio Manager, and Microsoft 365 Apps list views; clicking a column header sorts ascending; clicking again toggles to descending

### Changed

- Install tab: `Invoke-LocalPackageInstall` now updates the `Install.json` copied to the staging directory before running `Install.ps1`; `PackageInformation.Version` is set to the resolved latest version and `PackageInformation.SetupFile` is updated to the actual downloaded installer filename; the update is best-effort and logs a warning on failure without aborting the install
- Import tab / Microsoft Intune Win32 Apps: `Invoke-IntunePackageBuild` now copies `App.json` to the staging source path and updates `PackageInformation.Version` and `PackageInformation.SetupFile` with the resolved version and actual downloaded filename before packaging; `$setupFile` resolution prefers the actual downloaded filename over the value stored in `App.json`, then falls back to the SetupType default
- Apps tab / Download Queue: queue items now store the original Evergreen result object in a `SourceProperties` field so all app-specific properties (Sku, Type, Ring, etc.) are passed to `Save-EvergreenApp` intact; duplicate detection changed from a five-property comparison to URI-only matching
- Settings: `StartupView` ComboBox removed from the Settings page; the active tab is now automatically saved on navigation and restored on launch; defensive validation still coerces a stored disabled-tab value to `Apps`
- XAML and script: several control names renamed for consistency (`AppsComboBox` → `AppsListBox`, `ShowImportTabCheckBox` → `ShowImportTabToggle`, `ShowInstallTabCheckBox` → `ShowInstallTabToggle`, and various Browse button names); `AutomationProperties.Name` and `ToolTip` attributes added to key controls for accessibility; `TextTrimming` and `ToolTip` display templates added to URI and path columns to handle long values

### Fixed

- Apps tab / Download Queue: apps with the same version and architecture but differing properties (e.g. Adobe Acrobat DC Sku variants) were incorrectly deduplicated and silently dropped from the queue; URI-only duplicate detection corrects this
- Apps tab / Download Queue: apps with non-standard Evergreen result properties (Sku, Type, Ring, etc.) were downloaded without those properties being forwarded to `Save-EvergreenApp`, causing incorrect download path organisation; `SourceProperties` pass-through corrects this
- Install tab: `Install.ps1` could fail to locate the installer for EXE packages whose filename embeds the version (e.g. `audacity-win-3.7.7-64bit.exe`) when a newer version had been downloaded; updating `PackageInformation.SetupFile` in the staged `Install.json` resolves the mismatch
- Import tab / Microsoft Intune Win32 Apps: `New-IntuneWin32AppPackage` could reference a non-existent setup file for EXE packages with version-embedded filenames when `$setupFile` was read from a stale `App.json`; preferring the actual downloaded filename corrects this

## [1.0.15] - 2026-04-01

### Changed

- Import tab / Microsoft Intune Win32 Apps: Intune connection status controls container changed from `StackPanel` to `DockPanel`; status dot `Ellipse` docked to the left, improving alignment within the count bar layout
- Theme scripts: `StatusWarningBrush`, `StatusPositiveLightBrush`, `StatusWarningLightBrush`, and `StatusErrorLightBrush` added to `Window.Resources` and both light and dark theme scripts
- XAML: eight hardcoded ARGB hex row background tints across four `ListView`s replaced with `DynamicResource` bindings so row tints adapt correctly between light and dark themes
- XAML: `NavToggleButton` and `LogToggleButton` inline `ControlTemplate`s extracted into named `FluentNavButton` and `FluentToggleButton` styles in `Window.Resources`, eliminating duplicated template definitions

### Fixed

- `FluentToggleSwitch` thumb colour was hardcoded white; now uses `ToggleThumbBrush` so dark mode correctly renders a dark thumb
- Five status dot `Ellipse` fills using hardcoded `OrangeRed` and `Gold` replaced with named brush resources; `StatusDot` named style applied consistently across all status indicators
- `NerdioStatusCellStyle` Gold foreground and `EvergreenStatusDot` `#88FFFFFF` semi-transparent fill replaced with named brush resources so colours adapt to the active theme

## [1.0.14] - 2026-03-30

### Added
- Progress log entries are now written to a per-session log file at `%LocalAppData%\EvergreenUI\logs\EvergreenUI-<timestamp>.log` (UTF-8, no BOM); a new file is created on each launch of the Workbench
- `Format-LogEntry` private function: shared timestamp and level-prefix formatting used by `Write-UILog` and `Write-UpdateOutput`, eliminating duplicated formatting logic
- `Merge-ConfigSection` private function: merges missing default properties into a loaded config section, replacing six identical `foreach`/`Add-Member` blocks in `Get-UIConfig`
- `Get-SafeFolderName` private function: sanitises a definition file's parent directory name for use as a working folder name; applied in `Invoke-IntunePackageBuild` and `Invoke-LocalPackageInstall`

### Changed
- Navigation rail is now collapsible via a hamburger toggle button; nav items show icon and label when expanded (180 px) and icon only when collapsed (64 px); label visibility is toggled via named `TextBlock` controls (`NavAppsLabel`, `NavDownloadLabel`, etc.)
- NerdioShellApps PowerShell module moved from `support/` into `Resources/` and is loaded automatically from the bundled path at runtime; the Nerdio Manager module-path setting and its associated Settings page controls have been removed
- `Write-UILog` and `Write-UpdateOutput` now delegate to `Format-LogEntry` for consistent `[HH:mm:ss] [LEVEL]` formatting
- `Get-UIConfig` simplified by replacing repeated merge loops with `Merge-ConfigSection` calls
- `Format-LogEntry.ps1` is now dot-sourced into every background runspace before `Write-UILog.ps1` so log formatting is available in all runspaces
- `Get-SafeFolderName.ps1` is now dot-sourced into the Intune import and Install runspaces so the helper is available where needed
- Post-import Nerdio verification context (`PendingNerdioPostImportVerifyAppId`, `PendingNerdioPostImportExpectedEvergreenVersion`) is now stored in `$syncHash` at dispatch time rather than being re-read from captured local variables in the completion timer tick, fixing a strict-mode variable-not-set error after a successful Shell App version add
- Install tab: elevation/UAC status indicator right-aligned to match sign-in status indicators on the Import tabs (DockPanel `LastChildFill` changed from `True` to `False`)
- Download queue list view: padding removed from the wrapping border to tighten spacing
- `GridViewColumnHeader` style extracted to a single shared style in `Window.Resources`, removing duplicated per-`ListView` header style definitions

### Fixed
- Background runspaces (Download All, Library Update, Update-Evergreen, Install resolve/run, Intune import, M365 package build) all failed silently because `Format-LogEntry` was not dot-sourced into the runspace session; every `Write-UILog` call threw a "term not recognised" error that was caught and swallowed, leaving no log output and no work performed
- Intune Win32 import and Install run runspaces failed with "term not recognised" for `Get-SafeFolderName` after the function was extracted in the observability refactor
- Install tab "Find latest versions" logged an error (`Format-LogEntry` not recognised) and performed no version resolution
- Nerdio Shell App "Add version" logged a strict-mode error (`$shellAppId` cannot be retrieved) when attempting to set post-import verification context in the completion handler
- Install tab elevation status indicator no longer stretches across the full status bar width
- NerdioShellApps module updated for Windows PowerShell 5.1 compatibility: PS 7-only ternary and null-coalescing operators replaced, temp directory detection rewritten using Windows-compatible environment checks, `PSStyle` fallback added for informational logging
- Em dash characters (`—`) replaced with hyphens in string literals across private functions; UTF-8 em dashes were misread by PowerShell 5.1 as Windows-1252, causing the middle byte (`0x94`) to be interpreted as a closing double-quote and breaking script parsing on import

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
- Import tab / Intune and Nerdio Manager: connection status indicators updated to match the Microsoft 365 Apps tab - 9×9 ellipse with border stroke, service-name prefix label ("Intune:" / "Nerdio Manager:"), and status text right-aligned in the count bar
- Import tab / Intune and Nerdio Manager: count bar `DockPanel` changed to `LastChildFill="False"` so the right-docked status indicators correctly snap to the right edge
- Import tab / Microsoft Intune Win32 Apps: Import Win32 app button height pinned to 32 px to match the Nerdio Manager Shell Apps tab
- Nerdio Manager authentication: `Connect-Nme` called with `-ErrorAction Stop` so non-terminating errors are promoted to terminating and caught by the existing error handler; return value checked for null with an explicit failure message; `Set-NmeCredentials` also called with `-ErrorAction Stop`; module-load failure path now writes to the progress log

### Fixed
- Nerdio Manager authentication: failures produced no log output when the NerdioShellApps module could not be loaded silently (empty path) or when `Connect-Nme` wrote non-terminating errors rather than throwing - both cases are now logged

## [1.0.12] - 2026-03-28

### Added
- Apps tab: **Add to Library** button writes the selected application and active filter state to `EvergreenLibrary.json` in the configured library path; the button is only enabled when an app is loaded and a valid `EvergreenLibrary.json` exists
- Apps tab: inline status label next to the action buttons confirms a successful **Add to Library** operation with the app name (auto-clears after 3 seconds) or shows an error in red if the write fails
- Library tab: indeterminate progress bar appears below the path controls while **Update Library** is running and collapses on completion

### Fixed
- Library tab: warnings emitted by `Get-EvergreenLibrary` (e.g. missing app directories) are now captured and forwarded to the workbench log instead of being written to the PowerShell host

## [1.0.11] - 2026-03-27

### Added
- Import tab / Microsoft Intune: `DisplayName` property added to all comparison rows and used as the **App** column - matched rows show the Intune app name, unmatched rows show the definition name
- Import tab / Nerdio Shell Apps: **Versions** column shows the total count of versions present on the Shell App

### Changed
- Import tab / Microsoft Intune: columns reduced from 9 to 6 - **App**, **Publisher**, **Intune Version**, **Latest**, **Status**, **Action**; removed Definition, Matched, Update Required, and Definition Version columns
- Import tab / Microsoft Intune: Action column values rationalised - `Import new app` (definition not in Intune), `Import new version and supersede` (matched app with update available), `Fix in definition` (duplicate GUID across definitions), `-` (no action required)
- Import tab / Microsoft Intune: row colours updated - green tint for matched apps that are current; amber tint for matched apps with an update available; transparent background for all other rows
- Import tab / Nerdio Shell Apps: columns restructured - **App**, **Publisher**, **Shell App**, **Versions**, **Shell App Version**, **Latest**, **Status**, **Action**; removed Definition App column
- Import tab / Nerdio Shell Apps: Action column values - `Update`, `Import`, or `-`; same row colour scheme as the Intune tab
- Import tab / Authentication: sign-in buttons are disabled while a session is already authenticated and re-enabled when the user signs out
- Settings tab: Preferences section reorganised - Theme selector occupies the left half of the row; **Show Import tab** and **Show Install tab** toggle switches are grouped on the right half within the same row
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
- Library GridView is now fully dynamic - columns are generated from the properties returned by Evergreen rather than being hardcoded

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
