# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Evergreen Workbench** is a WPF-based graphical frontend for the [Evergreen](https://github.com/aaronparker/evergreen) PowerShell module. It provides a GUI for discovering, downloading, and managing 500+ Windows applications. Published to PowerShell Gallery as a pre-release module.

- **Platform**: Windows only (WPF requires Windows)
- **PowerShell**: 5.1 (Desktop) and 7+ (Core), minimum PS 5.1
- **Dependency**: Evergreen module ≥ 2603.2832.0

## Commands

### Testing
```powershell
Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed
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

## Architecture

### Module Structure
The module exposes a single public function (`Start-EvergreenWorkbench`) that orchestrates everything. All internal logic lives in 23 private helper functions dot-sourced by `EvergreenUI.psm1`.

```
EvergreenUI/
├── EvergreenUI.psd1        # Module manifest (version, deps, exports)
├── EvergreenUI.psm1        # Loads Private/ then Public/
├── Public/
│   └── Start-EvergreenWorkbench.ps1   # Only exported function
├── Private/                           # 23 helper functions
│   ├── themes/
│   │   ├── Set-LightTheme.ps1
│   │   └── Set-DarkTheme.ps1
│   └── [utility functions]
└── Resources/
    ├── EvergreenUI.xaml    # WPF UI definition (~3,000 lines)
    └── evergreenbulk.png
```

### Threading Model
WPF requires STA (Single Threaded Apartment). `Start-EvergreenWorkbench` ensures STA thread on startup. Background operations (app downloads, library updates, Intune imports) run in isolated STA runspaces created by `New-WpfRunspace`. Communication between runspaces and the UI uses a `$syncHash` (synchronized hashtable) with `Dispatcher.Invoke` for thread-safe UI updates.

### Key Private Functions

| Function | Purpose |
|----------|---------|
| `Get-UIConfig` | Load/create user config from `%APPDATA%\EvergreenUI\settings.json` |
| `Set-UIConfig` | Persist UI state changes |
| `Get-EvergreenAppList` | Fetch and cache app list from Evergreen module |
| `Get-FilterableProperties` | Determine which properties get filter controls |
| `New-FilterPanel` | Dynamically build filter UI from app result properties |
| `Invoke-FilterUpdate` | Refresh filter panel when app selection changes |
| `Invoke-AppDownload` | Queue and execute batch downloads |
| `New-WpfRunspace` | Factory for background STA runspaces |
| `Write-UILog` | Thread-safe log output to the UI log panel |
| `Invoke-IntuneGraphWin32Import` | Import Win32 apps to Intune via Graph API |
| `Test-LocalPackageDetection` | Detect installed app versions for comparison |

### Providers / Tabs
The UI has four tabs with distinct workflows:
1. **Apps** — Browse Evergreen app catalog, apply filters, queue downloads
2. **Library** — Manage local Evergreen app library
3. **Import** — Nerdio Manager and Intune Win32 packaging workflows
4. **Install** — Local package installation from definition files

### Configuration
User settings persist to `$env:APPDATA\EvergreenUI\settings.json`. `Get-UIConfig` creates defaults on first run. Settings include output/library paths, theme, log verbosity, and per-provider config (Nerdio, Intune, Install).

## Code Conventions

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in all scripts
- PSScriptAnalyzer must pass with default ruleset
- CRLF line endings for all PowerShell files (enforced via `.gitattributes`)
- WPF controls are named with a consistent prefix scheme (see `EvergreenUI.xaml`)

## Release Process

Releases are automated via two GitHub Actions workflows:
1. **tag-release.yml** — Watches `EvergreenUI.psd1` for version changes; creates a git tag `v{version}` when the version is bumped
2. **publish-psgallery.yml** — Triggered by tag creation; publishes to PowerShell Gallery using `$env:NUGET_API_KEY`

Version format is `Major.Minor.Patch` (e.g., `1.0.9`). Bump the version in `EvergreenUI.psd1` (`ModuleVersion`) to trigger a release.
