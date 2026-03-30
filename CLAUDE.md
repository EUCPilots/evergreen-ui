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

The module exposes a single public function (`Start-EvergreenWorkbench`) that orchestrates everything. All internal logic lives in private helper functions dot-sourced by `EvergreenUI.psm1`.

```
EvergreenUI/
├── EvergreenUI.psd1        # Module manifest (version, deps, exports)
├── EvergreenUI.psm1        # Loads Private/ then Public/
├── Public/
│   └── Start-EvergreenWorkbench.ps1   # Only exported function
├── Private/                           # helper functions
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
| `Merge-ConfigSection` | Merge default property values into a loaded config section (used by Get-UIConfig) |
| `Get-EvergreenAppList` | Fetch and cache app list from Evergreen module |
| `Get-FilterableProperties` | Determine which properties get filter controls |
| `New-FilterPanel` | Dynamically build filter UI from app result properties |
| `Invoke-FilterUpdate` | Refresh filter panel when app selection changes |
| `Invoke-AppDownload` | Queue and execute batch downloads |
| `New-WpfRunspace` | Factory for background STA runspaces |
| `Write-UILog` | Thread-safe log output to the UI log panel |
| `Write-UpdateOutput` | Thread-safe log output to the Update tab panel |
| `Format-LogEntry` | Format a `[HH:mm:ss] [LEVEL] message` log line (used by Write-UILog and Write-UpdateOutput) |
| `Get-SafeFolderName` | Sanitise a definition file path's parent directory name for use as a working folder name |
| `Invoke-IntuneGraphWin32Import` | Import Win32 apps to Intune via Graph API |
| `Test-LocalPackageDetection` | Detect installed app versions for comparison |

### Providers / Tabs

The UI has four tabs with distinct workflows:
1. **Apps** - Browse Evergreen app catalog, apply filters, queue downloads
2. **Library** - Manage local Evergreen app library
3. **Import** - Nerdio Manager and Intune Win32 packaging workflows
4. **Install** - Local package installation from definition files

### Configuration

User settings persist to `$env:APPDATA\EvergreenUI\settings.json`. `Get-UIConfig` creates defaults on first run. Settings include output/library paths, theme, log verbosity, and per-provider config (Nerdio, Intune, Install).

## Code Conventions

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in all scripts
- PSScriptAnalyzer must pass with default ruleset
- CRLF line endings for all PowerShell files (enforced via `.gitattributes`)
- WPF controls are named with a consistent prefix scheme (see `EvergreenUI.xaml`)
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
