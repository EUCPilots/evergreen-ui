# EvergreenUI Repository Instructions

Evergreen Workbench (`EvergreenUI`) is a Windows-only WPF frontend and headless API for the Evergreen PowerShell module. It requires PowerShell 7.6 or later. The module is also a Windows-only application: WPF is loaded only when
`Start-EvergreenWorkbench` is called.

- Platform: Windows
- PowerShell: 7.6 or later
- Evergreen dependency: at least 2603.2832.0
- UI views: Apps, Library, Packages, Intune, Nerdio, Settings, and About
- Packaging helpers: `.scripts\`

Read `GLOSSARY.md` and the relevant files under `docs\adr\` before designing domain or architecture changes. Repository-specific rules for Markdown, PowerShell, Pester, and WPF live in `.github\instructions\`.

## Commands

```powershell
# Test suite
Invoke-Pester -Path .\tests -Output Detailed

# One test by name
Invoke-Pester -Path .\tests\EvergreenUI.AppsLibrary.Tests.ps1 -Output Detailed -FullNameFilter '*application catalog*'

# Lint
Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse

# Run the UI
Import-Module .\EvergreenUI\EvergreenUI.psd1 -Force
Start-EvergreenWorkbench
```

## Public APIs

| Area | Commands | Notes |
|---|---|---|
| Settings | `Get-EwSetting`, `Set-EwSetting`, `Reset-EwSetting` | Settings persist in `$env:APPDATA\EvergreenWorkbench\settings.json`, including validated UI state and library path history. |
| WPF interface | `Start-EvergreenWorkbench` | Opens the Workbench views; requires Windows and PowerShell 7.6 or later. |
| Jobs | `Start-EwJob`, `Get-EwJob`, `Stop-EwJob`, `Remove-EwJob` | Uses a bounded runspace pool and exposes progress, information, and state-change events. Remove completed jobs with `Remove-EwJob`. |
| Apps and downloads | `Get-EwApp`, `Get-EwFilterableProperty`, `Save-EwArtifact` | Lists the catalog or resolves artifacts; resolved applications are cached under `Cache\Apps` for 24 hours. `-Force` bypasses and refreshes the cache. |
| Library | `Get-EwLibrary`, `Update-EwLibrary` | Reads or updates a local Evergreen library. |
| Definitions | `Get-EwDefinition`, `Resolve-EwArtifact`, `Update-EwDefinition` | Validates App.json files, evaluates the supported `Application.Filter` grammar, and resolves or updates artifacts. |
| Local install | `Test-EwDetection`, `Install-EwPackage` | Evaluates File, Registry, and MSI detection rules and supports `ShouldProcess`. |
| Packages | `New-EwPackage` | Builds Intune Win32 or Microsoft 365 Intune/Nerdio packages; Intune requires optional `IntuneWin32App`. |
| Authentication | `Connect-EwIntune`, `Disconnect-EwIntune`, `Connect-EwNerdio`, `Disconnect-EwNerdio` | Loads provider modules only when the corresponding provider is requested. |
| Publishing | `Publish-EwIntuneApp`, `Publish-EwIntuneBatch`, `Publish-EwNerdioApp`, `Publish-EwNerdioBatch`, `Set-EwIntuneSupersedence` | Publishes through Microsoft Graph or Nerdio and preserves partial batch outcomes. |
| Favourites | `Add-EwFavouriteApp`, `Remove-EwFavouriteApp` | Stores favourites in settings; `Get-EwApp` lists favourites first. |
| Dependencies and cache | `Get-EwDependency`, `Update-EwEvergreen`, `Clear-EwCache` | Reports dependency status, refreshes Evergreen application data, or explicitly clears Workbench caches. |
| Microsoft 365 | `Get-EwM365Configuration` | Discovers ODT XML channel, product, and architecture configurations. |
| Intune compare | `Get-EwIntuneApp`, `Compare-EwIntuneApp` | Lists Win32 apps and compares them with App.json definitions. |
| Azure discovery | `Connect-EwAzure`, `Disconnect-EwAzure`, `Get-EwAzureResourceGroup`, `Get-EwAzureStorageAccount`, `Get-EwAzureStorageContainer` | Discovers Azure resources for Nerdio storage configuration. |
| Nerdio | `Get-EwNerdioDefinition`, `Get-EwNerdioShellApp`, `Get-EwNerdioShellAppVersion`, `Compare-EwNerdioShellApp`, `Get-EwNerdioPublishPlan`, `Get-EwNerdioShellAppVersionPrunePlan`, `Remove-EwNerdioShellAppVersion` | Reads definitions, compares Shell Apps, prepares publishing plans, and manages exact-version pruning. |

Evergreen is required. `IntuneWin32App`, `Microsoft.Graph.Authentication`,
`Az.Accounts`, `Az.Resources`, and `Az.Storage` are optional provider dependencies.

## Architecture

- Feature folders contain public and private scripts. The module loader imports private scripts before public scripts and loads feature folders recursively.
- Feature implementations belong in private helpers, one function per file. Public commands remain thin adapters around private logic.
- Keep Evergreen calls behind private wrappers so tests can mock them.
- The manifest exports headless commands and `Start-EvergreenWorkbench`.
- WPF assemblies and controls are loaded only when the UI starts.
- XAML lives in `EvergreenUI\Resources\EvergreenWorkbench.xaml`. Private UI helpers and view event wiring live in `EvergreenUI\Private\UI\`.
- WPF requires STA. Start long operations with `Start-EwJob`; poll snapshots through the UI dispatcher timer and update controls only on the UI thread. Never access controls from a worker runspace.

### Navigation and Workflows

- Apps combines discovery, downloads, favourites, and the collapsible queue tray.
- Library reads and updates an Evergreen library and shows selected application versions.
- Packages contains Definitions and Install tabs. Definitions manages shared App.json folders; Install checks local detection and resolves latest versions.
- Entering the Install tab refreshes local detection through the shared job. Defer refresh while another operation is running and disable install actions until fresh results arrive.
- Intune compares definitions and builds confirmed publishing batches.
- Nerdio owns staged Azure/API setup and confirmed publishing plans. Pass the synchronized Nerdio session explicitly into job workers.
- Apps maintenance or cache changes must follow `docs\adr\0005-explicit-coordinated-workbench-cache-clearing.md` for ownership and in-flight invalidation boundaries.

### Worker Scope

`Start-EwJob` recreates scriptblocks outside module scope. Invoke private helpers inside workers with:

```powershell
& (Get-Module -Name EvergreenUI) {
    & <Private-Helper> @Parameters
}
```

Pass inputs explicitly. Never rely on script variables crossing runspace boundaries.

## Configuration

User settings persist to `$env:APPDATA\EvergreenWorkbench\settings.json`. `Get-EwSetting` supplies defaults for missing settings and `Set-EwSetting` persists supported values.

## Conventions

- Every script starts with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Target PowerShell 7.6 or later and use named parameters for cmdlet calls.
- Keep PowerShell files CRLF. Follow `.gitattributes`.
- Use approved PowerShell verbs, full cmdlet names, and named parameters.
- Keep comments rare and put comments only where logic is not self-explanatory.
- Use no em dashes, emojis, or horizontal rules in code or Markdown.
- Name XAML controls consistently with nearby controls.
- Use PSScriptAnalyzer's default ruleset.
- Use `-ErrorAction Stop` for cmdlets inside `try/catch`.
- For an empty `catch`, explain why it is intentional and write the exception with `Write-Verbose`.
- Log polling failures with attempt number and exception message.
- Functions with complex results define a local `$fail` scriptblock that returns a function-specific `PSCustomObject` with `Succeeded = $false` and `Error`.

### Logging

Use `Write-Verbose "EvergreenUI: ..."` for operational diagnostics and existing UI logging helpers for Workbench activity. Log start and outcome for significant file, network, and API operations. Log cache hit or miss with age, selected branches for complex conditions, and version resolution outcomes.

## Testing

- Import the module before tests: `Import-Module ..\EvergreenUI\EvergreenUI.psd1`.
- Test private functions through module scope.
- Pester test files use `*.Tests.ps1`.
- Run focused tests with `Invoke-Pester -Path ... -FullNameFilter ...`.
- Run the complete suite with `Invoke-Pester -Path .\tests -Output Detailed`.
- Follow `.github\instructions\powershell-pester-6.instructions.md`.

## Releases

Before a release, bump `ModuleVersion` in
`EvergreenUI\EvergreenUI.psd1` using `Major.Minor.Patch`. Update `CHANGELOG.md`
with user-facing changes.

Tagging and PowerShell Gallery publication are automated:

1. `tag-release.yml` creates `v{version}` after the module version changes.
2. `publish-psgallery.yml` publishes the tag to the PowerShell Gallery.

## Agent Context

- GitHub Issues for this repository use `EUCPilots/evergreen-ui`. Use `gh` for issue operations; follow `docs\agents\issue-tracker.md`.
- Triage uses `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`; see `docs\agents\triage-labels.md`.
- Before domain work, read relevant terms in `GLOSSARY.md` and decisions in `docs\adr\`; follow `docs\agents\domain.md`.

## Others

- Do not wrap long lines in code or Markdown; let them extend naturally.
- Update CHANGELOG.md with user-facing changes for each release.
- Follow semantic versioning for module versioning: `Major.Minor.Patch`.
- Ensure that each release has a corresponding entry in `CHANGELOG.md` with user-facing changes.
- Ask before changing the module version or making releases.
