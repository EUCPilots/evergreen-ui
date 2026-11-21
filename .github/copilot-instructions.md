# Copilot instructions

Evergreen Workbench (`EvergreenUI` module) is a Windows-only WPF frontend for the [Evergreen](https://github.com/aaronparker/evergreen) PowerShell module. `EvergreenUI-v1\` holds the v1 reference implementation, supporting PowerShell 5.1 and 7+. `EvergreenUI\` contains the in-progress v2 rewrite, requiring PowerShell 7.6+. The architecture and conventions below describe v1 unless stated otherwise. See `GLOSSARY.md` and `docs\adr\` for v2 decisions. `.scripts\` holds standalone packaging helpers.

See `CLAUDE.md` for the full function table, settings keys and control naming scheme. Additional rules live in `.github\instructions\` (PowerShell, Pester 5, WPF, Markdown) and custom agents in `.github\agents`.

## Commands

```powershell
# v2 and v1 test suites (Pester 5)
Invoke-Pester -Path .\tests -Output Detailed

# v1 reference tests (Pester 5)
Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed

# Single v2 Describe/test by name
Invoke-Pester -Path .\tests\EvergreenUI.AppsLibrary.Tests.ps1 -Output Detailed -FullNameFilter '*application catalog*'

# Single v1 Describe/test by name
Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed -FullNameFilter '*Get-UIConfig*'

# Lint (default PSScriptAnalyzer ruleset must pass)
Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse

# Run the v1 UI
Import-Module .\EvergreenUI-v1\EvergreenUI.psd1 -Force
Start-EvergreenWorkbench
```

## Architecture

- v2 loads feature-grouped private and public scripts recursively, with private scripts first. Its settings commands use `%APPDATA%\EvergreenWorkbench\settings.json` without migrating v1 settings. `Get-EwApp` lists the catalog or resolves artifacts; `Get-EwFilterableProperty` derives filter metadata; `Save-EwArtifact` downloads an artifact. `Get-EwLibrary` reads inventory and `Update-EwLibrary` refreshes it. Definition commands validate App.json files, safely evaluate supported `Application.Filter` expressions, resolve artifacts, and update definitions. `Test-EwDetection` and `Install-EwPackage` handle local installation; `New-EwPackage` builds Intune and Microsoft 365 packages. Provider auth and publishing commands load optional Graph/Azure modules only when requested. Favourites, dependency status, Microsoft 365 configuration discovery, Intune and Nerdio comparison, Azure resource discovery, and Nerdio version cleanup are also headless commands (see `CLAUDE.md`). Keep Evergreen calls behind private wrappers so tests can mock them. `Start-EwJob` uses a bounded runspace pool; `Get-EwJob` exposes progress, information and state-change events. Remove completed jobs with `Remove-EwJob`. The v2 UI is not yet implemented.
- v1's `EvergreenUI.psm1` dot-sources `Private\themes\*.ps1` first, then `Private\*.ps1`, then `Public\`. Its only exported function is `Start-EvergreenWorkbench`. For v2, the manifest exports the headless commands listed in `CLAUDE.md`. New private helpers go in feature-grouped `Private\` folders, one function per file (v1 exception: `Invoke-AzureSignIn.ps1` holds all seven Azure/Nerdio auth helpers).
- The whole UI is one XAML file, `Resources\EvergreenUI.xaml`. `Start-EvergreenWorkbench` loads it, binds named controls and wires event handlers. Navigation is RadioButtons (`Nav{View}`) toggling `{View}Panel` content, not a TabControl. Import is a nested TabControl (`ImportProviderTabControl`).
- WPF needs STA. Long-running work (downloads, library updates, Intune/Nerdio/M365 builds and imports) runs in background STA runspaces created by `New-WpfRunspace`. Runspaces talk to the UI only through the shared `$syncHash` and `Dispatcher.Invoke`. Never touch controls directly from a runspace.
- Install and Import workflows are driven by `App.json` definition files (`Application.Filter` expression resolves the latest version via `Get-EvergreenApp` or `Get-VcList`; `DetectionRule` entries for File, Registry, MSI).
- Settings persist to `%APPDATA%\EvergreenUI\settings.json`. `Get-UIConfig` creates defaults and forward-merges missing keys; when adding a setting, add a default there and use `Merge-ConfigSection` for nested sections.
- v1 tests import `..\EvergreenUI-v1\EvergreenUI.psd1`; v2 tests import `..\EvergreenUI\EvergreenUI.psd1`. Private functions are tested via module scope.

## Conventions

- Every script: `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Always use named parameters. Keep v1 code compatible with PS 5.1; v2 requires PowerShell 7.6+.
- CRLF line endings for PowerShell files (`.gitattributes`).
- No em dashes, emojis or horizontal rules in code or markdown.
- Logging: functions that receive `$SyncHash` use `Write-UILog`; utility functions without it use `Write-Verbose "EvergreenUI: ..."`. Use `Format-LogEntry` for any new log-output helper rather than formatting inline. Log start and outcome of file/network/API operations, cache hit/miss with age, which branch a complex condition took, and version resolution outcomes.
- Use `-ErrorAction Stop` on cmdlets inside `try/catch`. An empty `catch {}` must have a comment explaining why and a `Write-Verbose` of the exception. Retry/polling loops log each failed attempt with number and message.
- Functions with complex results define a local `$fail` scriptblock returning a function-specific `[PSCustomObject]` with `Succeeded = $false` and `Error`.
- Use `Get-SafeFolderName -DefinitionPath` for working folder names derived from definition paths.
- New XAML controls follow the naming scheme (`{Action}{Feature}Button`, `{Feature}StatusLabel`, `{Feature}PathBox`, `{Feature}ListView`, `Show{Feature}Toggle`, `{Feature}Combo`, `{Feature}StatusDot`).

## Releases

Bump `ModuleVersion` in `EvergreenUI\EvergreenUI.psd1` (format `Major.Minor.Patch`). `tag-release.yml` tags `v{version}`, then `publish-psgallery.yml` publishes to PowerShell Gallery. Update `CHANGELOG.md` with user-facing changes.

## Tooling preference

Prefer PowerShell (`Select-String` rather than `rg`) for searching. If a tool is missing, ask the user to install it.
