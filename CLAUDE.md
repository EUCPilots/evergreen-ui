# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`EvergreenUI\` requires PowerShell 7.6 or later. Its public headless commands run
without WPF; the UI provides Apps, Library, Packages, Intune, Nerdio,
Settings, and About views. Packages contains Definitions and Install tabs.
Apps combines application discovery and
downloads in one view. Read `docs\adr\` before designing changes.

**Evergreen Workbench** is a WPF-based graphical frontend for the [Evergreen](https://github.com/aaronparker/evergreen) PowerShell module. It provides a GUI for discovering, downloading, and managing 500+ Windows applications. The manifest marks the module as a preview.

- **Platform**: Windows only (WPF requires Windows)
- **PowerShell**: 7.6+ (Core)
- **Dependency**: Evergreen module ≥ 2603.2832.0

## Additional instructions

* Review .github\instructions for additional instructions

## Commands

### Testing

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

### Linting

```powershell
Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse
```

### Running the UI

```powershell
Import-Module .\EvergreenUI\EvergreenUI.psd1
Start-EvergreenWorkbench
```

### Public APIs

| Area | Commands | Notes |
|---|---|---|
| Settings | `Get-EwSetting`, `Set-EwSetting`, `Reset-EwSetting` | Uses fresh settings at `%APPDATA%\EvergreenWorkbench\settings.json`, including validated UI state (`StartupView`, `LastAppName`, `WindowWidth`, `WindowHeight`, `DownloadTrayHeight`, `AppsListWidth`, `WindowMaximized`). Saving `LibraryPath` records it in `LibraryPathHistory` (10 most recent). |
| WPF interface | `Start-EvergreenWorkbench` | Opens the Workbench views; requires Windows and PowerShell 7.6+. |
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

The module exports headless commands plus the WPF entry point; its UI calls
the public commands.

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
    ├── EvergreenWorkbench.xaml        # WPF shell
    ├── Install.ps1
    └── m365-app.json
```

### Threading Model

Workbench loads WPF only when `Start-EvergreenWorkbench` is
called, and moves to an STA runspace when necessary. Views start long-running
headless operations with `Start-EwJob`; a WPF
dispatcher timer reads job snapshots and updates controls on the UI thread.
Worker runspaces never access WPF controls.

### Navigation Views

The shell includes seven RadioButton navigation views: Apps, Library,
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

### Configuration

User settings persist to `$env:APPDATA\EvergreenWorkbench\settings.json`.
`Get-EwSetting` supplies defaults for missing settings; `Set-EwSetting`
persists supported values.

## Code Conventions

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in all scripts
- PSScriptAnalyzer must pass with default ruleset
- CRLF line endings for all PowerShell files (enforced via `.gitattributes`)
- Name new WPF controls consistently with the surrounding controls in
  `EvergreenUI\Resources\EvergreenWorkbench.xaml`.
- Always use named parameters for PowerShell cmdlet calls (e.g. `Start-Sleep -Seconds 3`, not `Start-Sleep 3`)
- Never use em dashes in any code or markdown files
- Target PowerShell 7.6 or later.
- Never use emojis
- Never use horizontal lines in markdown files

### Logging

Use `Write-Verbose` with the prefix `"EvergreenUI: "` for operational
diagnostics. Use existing UI logging helpers for Workbench activity.

Log the following at a minimum:
- Start and outcome of significant file/network/API operations
- Which branch was taken when complex conditional logic selects a code path
- Cache hit/miss with age information
- Version resolution outcomes

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

## Release Process

Releases are automated via two GitHub Actions workflows:
1. **tag-release.yml** - Watches `EvergreenUI.psd1` for version changes; creates a git tag `v{version}` when the version is bumped
2. **publish-psgallery.yml** - Triggered by tag creation; publishes to PowerShell Gallery using `$env:NUGET_API_KEY`

Version format is `Major.Minor.Patch` (e.g., `2.0.2`). Bump the version in `EvergreenUI.psd1` (`ModuleVersion`) to trigger a release.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for EUCPilots/evergreen-ui (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
