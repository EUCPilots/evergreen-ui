# Copilot instructions

Evergreen Workbench (`EvergreenUI` module) is a Windows-only WPF frontend and headless API for the [Evergreen](https://github.com/aaronparker/evergreen) PowerShell module. `EvergreenUI\` requires PowerShell 7.6+. See `GLOSSARY.md` and `docs\adr\` for domain terms and architecture decisions. `.scripts\` holds standalone packaging helpers.

See `CLAUDE.md` for command and architecture guidance. Additional rules live in `.github\instructions\` (PowerShell, Pester, WPF, Markdown).

## Commands

```powershell
# Test suite (Pester 5)
Invoke-Pester -Path .\tests -Output Detailed

# Single Describe/test by name
Invoke-Pester -Path .\tests\EvergreenUI.AppsLibrary.Tests.ps1 -Output Detailed -FullNameFilter '*application catalog*'

# Lint (default PSScriptAnalyzer ruleset must pass)
Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse

# Run the UI
Import-Module .\EvergreenUI\EvergreenUI.psd1 -Force
Start-EvergreenWorkbench
```

## Architecture

- The module loads feature-grouped private and public scripts recursively, with private
  scripts first. Settings use
  `%APPDATA%\EvergreenWorkbench\settings.json`.
  `Get-EwApp` lists the catalog or resolves artifacts (cached per application for 24 hours under `Cache\Apps`);
  `Get-EwFilterableProperty` derives filter metadata; `Save-EwArtifact`
  downloads an artifact. `Get-EwLibrary` reads inventory and
  `Update-EwLibrary` refreshes it. Definition commands validate App.json files,
  safely evaluate supported `Application.Filter` expressions, resolve
  artifacts, and update definitions. `Test-EwDetection` and `Install-EwPackage`
  handle local installation; `New-EwPackage` builds Intune and Microsoft 365
  packages. Provider auth and publishing commands load optional Graph/Azure
  modules only when requested. Other headless commands support favourites,
  dependency status, Microsoft 365 configuration discovery, Intune and Nerdio
  comparison, Azure resource discovery, and Nerdio version cleanup (see
  `CLAUDE.md`). Keep Evergreen calls behind private wrappers so tests can mock
  them. `Start-EwJob` uses a bounded runspace pool; `Get-EwJob` exposes
  progress, information and state-change events. Remove completed jobs with
  `Remove-EwJob`. The WPF shell provides Apps, Library, Packages, Intune,
  Nerdio, Settings, and About views through
  `Start-EvergreenWorkbench`. Packages contains Definitions and Install tabs
  and manages shared Intune paths; Intune runs
  confirmed build-and-publish batches. Nerdio owns staged Azure/API setup and
  confirmed publishing plans; its in-memory session is passed explicitly into
  Job workers. The Install tab checks and installs locally. Apps combines discovery
  and downloads with a collapsible queue tray; Settings manages saved folders.
  About reports local dependencies and loaded versions from the window runspace.
- The manifest exports headless commands and `Start-EvergreenWorkbench`.
  Keep private helpers in feature folders, one function per file.
- WPF needs STA. Long operations run through `Start-EwJob`; a dispatcher timer
  polls job state and applies results on the UI thread. Never touch controls
  directly from a worker runspace.
- XAML lives in `EvergreenUI\Resources\EvergreenWorkbench.xaml`; private UI helpers and per-view event wiring live in `EvergreenUI\Private\UI\`. WPF assemblies are loaded only when the UI is started, so importing the module remains headless.
- Install and packaging workflows use `App.json` definition files (`Application.Filter` resolves the latest version via `Get-EvergreenApp` or `Get-VcList`; `DetectionRule` entries support File, Registry, MSI).
- Tests import `..\EvergreenUI\EvergreenUI.psd1`. Private functions are tested via module scope.

## Conventions

- Every script: `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Always use named parameters. Target PowerShell 7.6+.
- CRLF line endings for PowerShell files (`.gitattributes`).
- No em dashes, emojis or horizontal rules in code or markdown.
- Logging: use `Write-Verbose "EvergreenUI: ..."` for operational diagnostics and existing UI logging helpers for Workbench activity. Log start and outcome of file/network/API operations, cache hit/miss with age, which branch a complex condition took, and version resolution outcomes.
- Use `-ErrorAction Stop` on cmdlets inside `try/catch`. An empty `catch {}` must have a comment explaining why and a `Write-Verbose` of the exception. Retry/polling loops log each failed attempt with number and message.
- Functions with complex results define a local `$fail` scriptblock returning a function-specific `[PSCustomObject]` with `Succeeded = $false` and `Error`.
- Name new XAML controls consistently with surrounding controls.

## Releases

Bump `ModuleVersion` in `EvergreenUI\EvergreenUI.psd1` (format `Major.Minor.Patch`). `tag-release.yml` tags `v{version}`, then `publish-psgallery.yml` publishes to PowerShell Gallery. Update `CHANGELOG.md` with user-facing changes.

## Tooling preference

Prefer PowerShell (`Select-String` rather than `rg`) for searching. If a tool is missing, ask the user to install it.
