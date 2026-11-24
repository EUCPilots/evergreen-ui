# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`EvergreenUI-v1\` contains the working v1 reference. `EvergreenUI\` is the v2
rewrite, requiring PowerShell 7.6 or later. Its public headless commands run
without WPF; the v2 UI provides Apps, Library, Packages, Intune, Nerdio,
Settings, and About views. Packages contains Definitions and Install tabs.
Apps combines application discovery and
downloads in one view.
Unless explicitly marked v2, the architecture and conventions below describe
v1. Read `docs\adr\` before designing v2 changes.

**Evergreen Workbench** is a WPF-based graphical frontend for the [Evergreen](https://github.com/aaronparker/evergreen) PowerShell module. It provides a GUI for discovering, downloading, and managing 500+ Windows applications. Published to PowerShell Gallery as a pre-release module.

- **Platform**: Windows only (WPF requires Windows)
- **PowerShell**: 5.1 (Desktop) and 7+ (Core), minimum PS 5.1
- **Dependency**: Evergreen module ≥ 2603.2832.0

## Additional instructions

* Review .github\agents for custom agents
* Review .github\instructions for additional instructions

## Commands

### Testing

For v2:

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

For the v1 reference:

```powershell
Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed
```

### Linting

```powershell
Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse
```

### Running the UI

V1 reference:

```powershell
Import-Module .\EvergreenUI-v1\EvergreenUI.psd1
Start-EvergreenWorkbench
```

V2 preview:

```powershell
Import-Module .\EvergreenUI\EvergreenUI.psd1
Start-EvergreenWorkbench
```

### V2 Public APIs

| Area | Commands | Notes |
|---|---|---|
| Settings | `Get-EwSetting`, `Set-EwSetting`, `Reset-EwSetting` | Uses fresh settings at `%APPDATA%\EvergreenWorkbench\settings.json`, including validated UI state (`StartupView`, `LastAppName`, `WindowWidth`, `WindowHeight`, `DownloadTrayHeight`, `AppsListWidth`, `WindowMaximized`). Saving `LibraryPath` records it in `LibraryPathHistory` (10 most recent). |
| WPF interface | `Start-EvergreenWorkbench` | Opens the v2 Workbench views; requires Windows and PowerShell 7.6+. |
| Jobs | `Start-EwJob`, `Get-EwJob`, `Stop-EwJob`, `Remove-EwJob` | Runs bounded background work in the module's runspace pool. |
| Apps and downloads | `Get-EwApp`, `Get-EwFilterableProperty`, `Save-EwArtifact` | Wraps Evergreen catalog, artifact, and download operations. Resolved artifacts are cached per application as `Cache\Apps\{Name}.json` for 24 hours; `-Force` bypasses and refreshes the cache. |
| Library | `Get-EwLibrary`, `Update-EwLibrary` | Reads or updates a local Evergreen library. |
| Definitions | `Get-EwDefinition`, `Resolve-EwArtifact`, `Update-EwDefinition` | Supports a constrained `Application.Filter` grammar instead of executing stored PowerShell. |
| Local install | `Test-EwDetection`, `Install-EwPackage` | Evaluates File, Registry, and MSI rules; installation supports `ShouldProcess`. |
| Packages | `New-EwPackage` | Builds Intune Win32 or Microsoft 365 Intune/Nerdio packages. Intune packaging requires optional `IntuneWin32App`. |
| Authentication | `Connect-EwIntune`, `Disconnect-EwIntune`, `Connect-EwNerdio`, `Disconnect-EwNerdio` | Loads Graph and Azure modules only for the requested provider. |
| Publishing | `Publish-EwIntuneApp`, `Publish-EwIntuneBatch`, `Publish-EwNerdioApp`, `Publish-EwNerdioBatch`, `Set-EwIntuneSupersedence` | Publishes through Microsoft Graph or Nerdio. Batches confirm snapshots and preserve partial outcomes. |
| Favourites | `Add-EwFavouriteApp`, `Remove-EwFavouriteApp` | Stores favourites in settings; `Get-EwApp` lists favourites first. |
| Dependencies and cache | `Get-EwDependency`, `Update-EwEvergreen`, `Clear-EwCache` | Reports module status, refreshes Evergreen application data (also clearing cached application versions), or explicitly clears Workbench caches. |
| Microsoft 365 | `Get-EwM365Configuration` | Discovers ODT XML configurations with channel, products, and architecture. |
| Intune compare | `Get-EwIntuneApp`, `Compare-EwIntuneApp` | Lists Win32 apps via Graph and compares them with App.json definitions. |
| Azure discovery | `Connect-EwAzure`, `Disconnect-EwAzure`, `Get-EwAzureResourceGroup`, `Get-EwAzureStorageAccount`, `Get-EwAzureStorageContainer` | Lists resources for Nerdio storage configuration. |
| Nerdio | `Get-EwNerdioDefinition`, `Get-EwNerdioShellApp`, `Get-EwNerdioShellAppVersion`, `Compare-EwNerdioShellApp`, `Get-EwNerdioPublishPlan`, `Get-EwNerdioShellAppVersionPrunePlan`, `Remove-EwNerdioShellAppVersion` | Reads Definition.json files, compares Shell Apps, prepares publishing snapshots and previews exact version retention/deletion. The UI supports Evergreen sources, confirmed post-publish pruning, and durable recovery of uncertain writes without credentials. |

`Evergreen` is required. `IntuneWin32App`, `Microsoft.Graph.Authentication`, `Az.Accounts`, `Az.Resources`, and `Az.Storage` are optional provider dependencies.

## Architecture

### Module Structure

The v1 module exposes a single public function
(`Start-EvergreenWorkbench`) that orchestrates its WPF interface. V2 exports
headless commands plus the WPF entry point; its UI calls the public v2
commands.

```
EvergreenUI/
├── EvergreenUI.psd1        # Module manifest (version, deps, exports)
├── EvergreenUI.psm1        # Loads Private/ then Public/
├── Public/
│   ├── Start-EvergreenWorkbench.ps1
│   └── [headless commands grouped by feature]
├── Private/
│   ├── UI/                            # WPF shell, view wiring, and job monitor
│   └── [headless helpers grouped by feature]
└── Resources/
    ├── EvergreenWorkbench.xaml        # V2 WPF shell
    ├── Install.ps1
    └── m365-app.json
```

### Threading Model

V1 uses dedicated STA runspaces and communicates through `$syncHash` and
`Dispatcher.Invoke`. V2 loads WPF only when `Start-EvergreenWorkbench` is
called, and moves to an STA runspace when necessary. V2 views start long-running
headless operations with `Start-EwJob`; a WPF
dispatcher timer reads job snapshots and updates controls on the UI thread.
Worker runspaces never access WPF controls.

### V2 Navigation Views

The v2 shell includes seven RadioButton navigation views: Apps, Library,
Packages, Intune, Nerdio, Settings, and About. Apps uses `Get-EwApp`,
`Get-EwFilterableProperty`, and the favourite commands; its collapsible queue
tray batches artifacts for `Save-EwArtifact` across applications and shows
download progress. Settings manages saved download and library folders;
Library reads and updates an Evergreen library and shows selected application
versions; Packages loads and updates shared
Intune App.json definitions on its Definitions tab and saves definition and
output paths; its Install tab
reloads definitions, checks local detection, resolves latest versions
separately, and supports confirmed batch installs through `Install-EwPackage`.
Definition folder changes and completed loads or updates invalidate Install
rows. Entering the Install tab refreshes local detection through the shared
Job, deferring during another operation and disabling install actions until
fresh results arrive. Matching definition-path selections survive refresh;
latest Artifact and architecture assessments do not. Definitions is the default
tab; legacy `StartupView=Install` selects Packages > Install without new settings.
About captures loaded module versions in the window runspace and refreshes
local dependency status independently of the active UI Job. Its potentially
blocking scan uses a separate short-lived runspace so closing the window can
stop the monitoring Job promptly.
Intune compares Definitions and builds and publishes confirmed batches through
`Publish-EwIntuneBatch`. Nerdio owns its staged Azure/API setup and runs confirmed
publishing plans through `Get-EwNerdioPublishPlan` and `Publish-EwNerdioBatch`.
Nerdio's synchronized session is passed explicitly into Job workers; script
variables alone are not shared between runspaces. Pending and unknown provider
outcomes are persisted before writes, require review, and are never retried
automatically. The UI supports Evergreen sources and optional post-publish
pruning through an exact-version preview and a separate confirmation; ambiguous
versions are skipped. Recovery state contains no credentials and requires the
same Nerdio destination to resume. Long-running work uses the shared job pool.

For Apps maintenance or cache changes, read
`docs\adr\0005-explicit-coordinated-workbench-cache-clearing.md` for ownership
and in-flight invalidation boundaries.

### Key Private Functions

| Function | Purpose |
|----------|---------|
| `Get-UIConfig` | Load/create user config from `%APPDATA%\EvergreenUI\settings.json` |
| `Set-UIConfig` | Persist UI state changes |
| `Merge-ConfigSection` | Merge default property values into a loaded config section (used by Get-UIConfig) |
| `Get-EvergreenAppList` | Fetch and cache app list from Evergreen module |
| `Get-FilterableProperties` | Determine which properties get filter controls |
| `New-FilterPanel` | Dynamically build filter UI from app result properties |
| `Invoke-FilterUpdate` | Refresh filter panel when app selection changes |
| `Invoke-AppDownload` | Queue and execute batch downloads |
| `Invoke-LibraryUpdate` | Run Start-EvergreenLibraryUpdate on a background runspace; forwards events to Write-UILog |
| `Get-InstallPackageDefinitions` | Recursively load and validate App.json definitions for the Install workflow |
| `Get-InstallPackageLatestVersion` | Resolve latest artifact with per-definition JSON cache; wraps Get-IntunePackageLatestVersion |
| `Get-IntunePackageLatestVersion` | Resolve latest installer via Application.Filter expression (Get-EvergreenApp or Get-VcList) |
| `Invoke-LocalPackageInstall` | Stage installer content and execute install command locally from App.json definition |
| `Invoke-IntunePackageBuild` | Download latest installer and create .intunewin package via IntuneWin32App module |
| `Invoke-IntuneDefinitionUpdate` | Update App.json and Source\Install.json definition files with the latest version and SetupFile resolved via each definition's Application.Filter expression; updates detection rule version values in place |
| `Invoke-IntuneGraphWin32Import` | Import Win32 apps to Intune via Graph API; parses RequirementRule.Architecture (single value or comma-separated list) and maps to Graph API `allowedArchitectures` string enum (`x64`, `x86`, `arm64`, or `x86,x64,arm64`) |
| `Set-IntuneGraphWin32Supersedence` | POST mobileAppSupersedence relationship between two Intune Win32 apps via Graph API |
| `Get-M365AppConfigurations` | Parse ODT XML configuration files; returns channel, products, architecture, and GUID |
| `Invoke-M365AppPackageBuild` | Download M365 setup.exe, update ODT XML, and build .intunewin for Intune import |
| `Invoke-M365AppShellAppBuild` | Download M365 setup.exe, update ODT XML, and build .zip for Nerdio Shell App import |
| `Invoke-AzureSignIn` | Interactive Entra sign-in for Intune workflows via Connect-MgGraph |
| `Invoke-AzureSignOut` | Disconnect Microsoft Graph and Az contexts |
| `Invoke-NerdioAzureSignIn` | Interactive Azure sign-in for Nerdio Manager via Connect-AzAccount |
| `Invoke-NerdioAzureSignOut` | Disconnect Az contexts for Nerdio |
| `Get-NerdioAzureResourceGroups` | Query Azure resource groups for Nerdio configuration |
| `Get-NerdioAzureStorageAccounts` | Query storage accounts in a resource group |
| `Get-NerdioAzureStorageContainers` | Query blob containers in a storage account |
| `New-WpfRunspace` | Factory for background STA runspaces |
| `Write-UILog` | Thread-safe log output to the UI log panel |
| `Write-UpdateOutput` | Thread-safe log output to the Update tab panel |
| `Format-LogEntry` | Format a `[HH:mm:ss] [LEVEL] message` log line (used by Write-UILog and Write-UpdateOutput) |
| `Get-SafeFolderName` | Sanitise a definition file path's parent directory name for use as a working folder name |
| `Set-DwmTitleBarColor` | Apply accent colour and dark/light mode to native OS title bar via DWM P/Invoke (Windows 11) |
| `Test-EvergreenModule` | Verify Evergreen module is installed and importable; throws on missing; called once at startup |
| `Test-LocalPackageDetection` | Evaluate App.json DetectionRule entries on local machine; supports File, Registry, and MSI rule types |

Note: `Invoke-AzureSignIn.ps1` is a multi-function file containing all seven Azure/Nerdio authentication helpers listed above.

### V1 Navigation Views

The UI uses a RadioButton-based navigation system (not a TabControl) with 8 views. The top-level navigation buttons are named `Nav{View}` and each view's content lives in a `{View}Panel`:

1. **Apps** - Browse Evergreen catalog, apply dynamic filters, queue downloads
2. **Download** - Manage and monitor the active download queue
3. **Library** - Manage local Evergreen app library via `Invoke-LibraryUpdate`
4. **Import** - A nested `TabControl` (`ImportProviderTabControl`) with four sub-tabs:
   - **Intune Win32 Apps** - Build .intunewin packages and import to Intune via Graph API
   - **Nerdio Manager Shell Apps** - Build .zip packages and upload to Azure Blob Storage
   - **Microsoft 365 Apps** - Configure ODT XML, build .intunewin or .zip for M365 Apps
   - **Authentication** - Entra ID sign-in for Intune (Connect-MgGraph) and Azure sign-in for Nerdio (Connect-AzAccount)
5. **Install** - Local package installation from App.json definition files
6. **Settings** - UI preferences (theme, output/library paths, log verbosity, feature toggles for Import and Install tabs)
7. **Update** - Evergreen module and library update output panel (uses `Write-UpdateOutput`)
8. **About** - Module version, author, and dependency information

### Configuration

User settings persist to `$env:APPDATA\EvergreenUI\settings.json`. `Get-UIConfig` creates defaults on first run and forward-merges any missing keys via `Merge-ConfigSection`.

Top-level settings keys: `OutputPath`, `LibraryPath`, `Theme`, `LogVisible`, `LogHeight`, `ShowImportTab`, `ShowInstallTab`, `StartupView`, `LastAppName`, `FavouriteApps`, `WindowWidth`, `WindowHeight`, `ImportSettings`, `NerdioSettings`, `IntuneSettings`, `M365Settings`, `InstallSettings`, `AzureAuthSettings`.

## Code Conventions

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in all scripts
- PSScriptAnalyzer must pass with default ruleset
- CRLF line endings for all PowerShell files (enforced via `.gitattributes`)
- WPF controls follow a consistent naming scheme (140+ named controls in `EvergreenUI.xaml`):
  - `Nav{View}` - navigation RadioButtons (NavApps, NavDownload, NavLibrary, NavImport, NavInstall, NavSettings, NavUpdate, NavAbout)
  - `{View}Panel` - top-level content panels (AppsPanel, DownloadPanel, LibraryPanel, etc.)
  - `{Action}{Feature}Button` - buttons (RefreshAppsButton, ClearQueueButton, BrowseLibraryButton)
  - `{Feature}StatusLabel`, `{Feature}CountLabel` - status and count labels
  - `{Feature}PathBox`, `{Feature}Box` - text inputs (OutputPathBox, AppSearchBox)
  - `{Feature}ListView` - list views (VersionsListView, DownloadQueueListView)
  - `{Feature}StatusDot` - connection/state indicators (IntuneConnectionStatusDot)
  - `Show{Feature}Toggle` - feature-enable toggles (ShowImportTabToggle)
  - `{Feature}Combo` - combo boxes (ThemeComboBox, NmeResourceGroupCombo)
- Always use named parameters for PowerShell cmdlet calls (e.g. `Start-Sleep -Seconds 3`, not `Start-Sleep 3`)
- Never use em dashes in any code or markdown files
- Ensure PowerShell commands use compatibility with PowerShell 5.1, for example Join-Path does not support -AdditionalChildPaths on PowerShell 5.1, so use an approach that is compatible on both PowerShell 5.1 or PowerShell 7 and above
- Never use emojis
- Never use horizontal lines in markdown files

### Logging

Use `Write-UILog` for functions that receive `$SyncHash` (all runspace-facing functions). Use `Write-Verbose` with the prefix `"EvergreenUI: "` for utility functions that do not have a `$SyncHash` parameter (e.g. `Get-UIConfig`, `Get-InstallPackageLatestVersion`).

Log the following at a minimum:
- Start and outcome of significant file/network/API operations
- Which branch was taken when complex conditional logic selects a code path
- Cache hit/miss with age information
- Version resolution outcomes

`Format-LogEntry` is the shared helper for timestamp+prefix formatting. It is called internally by both `Write-UILog` and `Write-UpdateOutput` - do not inline the formatting in new output functions.

### Error Handling

- Use `-ErrorAction Stop` on all cmdlets inside a `try/catch` block that is intended to catch that cmdlet's errors.
- Every `catch {}` (empty catch) **must** include a comment that explains why silence is intentional, e.g.: `# best-effort - failure here must not abort the caller`. Also add `Write-Verbose` of the caught exception so failures surface when running with `-Verbose`.
- Polling/retry loops must log each failed attempt with attempt number and exception message rather than silently swallowing errors.

### Structured Return Pattern

Functions with complex return types define a local `$fail` scriptblock:

```powershell
$fail = {
    param([string]$Msg)
    return [PSCustomObject]@{
        Succeeded = $false
        # ... function-specific fields ...
        Error     = $Msg
    }
}
```

Follow this pattern for new functions that return structured results. The shape is intentionally function-specific - do not try to genericise it.

### Shared Helper Patterns

- **Nested config merging**: use `Merge-ConfigSection -Loaded $json.Section -Default $default.Section` rather than repeating the `foreach`/`Add-Member` pattern.
- **Definition folder names**: use `Get-SafeFolderName -DefinitionPath $path` (returns the sanitised parent directory name). Only applicable when the folder name derives from a definition file path - for display-name-based names, apply the regex directly.
- **Log entry formatting**: use `Format-LogEntry -Message $msg -Level Info` if writing a new log-output helper function.

## Release Process

Releases are automated via two GitHub Actions workflows:
1. **tag-release.yml** - Watches `EvergreenUI.psd1` for version changes; creates a git tag `v{version}` when the version is bumped
2. **publish-psgallery.yml** - Triggered by tag creation; publishes to PowerShell Gallery using `$env:NUGET_API_KEY`

Version format is `Major.Minor.Patch` (e.g., `1.0.9`). Bump the version in `EvergreenUI.psd1` (`ModuleVersion`) to trigger a release.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for EUCPilots/evergreen-ui (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
