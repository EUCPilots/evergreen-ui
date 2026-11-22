# Evergreen Workbench

A WPF-based graphical frontend and headless API for the [Evergreen](https://eucpilots.com/evergreen/) PowerShell module.

Evergreen Workbench ships as a separate PowerShell module so it never modifies the core Evergreen module. The v1 WPF application supports **Windows PowerShell 5.1** and **PowerShell 7+**. The v2 preview targets Windows and requires **PowerShell 7.6+**.

The v1 implementation in `EvergreenUI-v1\` is the reference for the existing
WPF experience. The v2 preview in `EvergreenUI\` provides headless settings,
job, Apps, download, Library, definitions, local install, packaging,
authentication, and publishing commands. Its WPF interface covers
Apps, Download, Library, Packages, Intune, Nerdio, Install, Settings, and About.

V2 stores fresh settings in `%APPDATA%\EvergreenWorkbench\settings.json` and does not migrate v1 settings. Jobs run in a shared pool of up to four runspaces. Use `Start-EwJob`, `Get-EwJob`, `Stop-EwJob`, and `Remove-EwJob` to manage them. Job script blocks do not capture caller variables; pass values with `-ArgumentList`.

The v2 interface restores its window size and maximised state, last viewed page, and last selected application at startup. Apps artifact filters are multi-select: values combine with OR within a property and AND across properties, and no selection means All. The Download view can clear the whole queue unless a download is running, or clear only completed rows.

Use `Start-EwJob -NoModuleImport` for work that does not need Workbench
commands. A reused worker may still contain modules loaded by earlier jobs.

V2 app workflows use `Get-EwApp` to list the Evergreen catalog or resolve an application's artifacts. `Get-EwFilterableProperty` describes available filters, and `Save-EwArtifact` downloads a resolved artifact. `Get-EwLibrary` reads a local library inventory; `Update-EwLibrary` refreshes an initialized library.

V2 definition workflows use `Get-EwDefinition`, `Resolve-EwArtifact`, and `Update-EwDefinition`. Stored `Application.Filter` expressions are parsed by a constrained evaluator rather than executed as PowerShell; only supported Evergreen queries and `Where-Object` predicates resolve. `Test-EwDetection` evaluates File, Registry, and MSI rules, while `Install-EwPackage` stages and runs a local package with `ShouldProcess` support.

Local installation checks the native Windows architecture against the Definition
requirement and resolved Artifact. Incompatible values are blocked. A missing
requirement or x64 emulation on Arm64 needs separate approval; x86 is supported
on x86, x64, and Arm64. Windows 10 on Arm does not support x64 emulation.
For unattended use, explicitly supply
`-AllowMissingArchitectureRequirement` and/or `-AllowX64OnArm64` as needed.
`-Confirm:$false` alone does not approve these warnings, and a non-interactive
call without the required opt-in throws. Results report `Installed`, `Failed`,
`Blocked`, or `Skipped`; `-WhatIf` does not resolve or download an Artifact.

`New-EwPackage` builds Intune Win32 packages from App.json definitions or creates Microsoft 365 Apps packages for Intune or Nerdio from ODT XML. Intune package building uses the optional `IntuneWin32App` module. `Connect-EwIntune` and `Connect-EwNerdio` establish provider sessions; publishing commands require their corresponding Microsoft Graph or Azure modules and live provider access. Authentication tokens and secrets are kept in process memory, not settings.

`Connect-EwNerdio -ApiOnly` authenticates without an Azure storage connection.
A full connection with Azure storage remains required for Nerdio publishing.

Additional headless commands cover the remaining v1 workflows: `Add-EwFavouriteApp` and `Remove-EwFavouriteApp`; `Get-EwDependency` and `Update-EwEvergreen`; `Get-EwM365Configuration`; `Get-EwIntuneApp` and `Compare-EwIntuneApp`; `Connect-EwAzure`, `Disconnect-EwAzure`, and the `Get-EwAzure*` resource listing commands; and `Get-EwNerdioDefinition`, `Get-EwNerdioShellApp`, `Get-EwNerdioShellAppVersion`, `Compare-EwNerdioShellApp`, and `Remove-EwNerdioShellAppVersion`. `Publish-EwNerdioApp -ShellAppId` adds a version to an existing Shell App.

```powershell
Import-Module .\EvergreenUI\EvergreenUI.psd1
$artifacts = Get-EwApp -Name MicrosoftEdge
Get-EwFilterableProperty -Artifact $artifacts
$artifacts |
    Where-Object Architecture -eq 'x64' |
    Select-Object -First 1 |
    Save-EwArtifact -AppName MicrosoftEdge
Get-EwLibrary
Update-EwLibrary -WhatIf
```

## V1 Features

- **Apps view** - search and browse all 550+ Evergreen-supported applications; inspect version and download metadata returned by `Get-EvergreenApp`
- **Dynamic filters** - filter panel builds itself at runtime from whatever properties a given app actually returns (Architecture, Channel, Ring, Language, Type, Release, etc.)
- **Download queue** - select multiple app/version combinations and download them sequentially via `Save-EvergreenApp`
- **Library management** - inspect and update an Evergreen library on disk using `Start-EvergreenLibraryUpdate` and related cmdlets
- **Import** - four provider workflows accessed from a nested tab panel:
  - **Intune Win32 Apps** - resolve the latest installer via App.json definitions, build `.intunewin` packages with `IntuneWin32App`, import to Intune via Graph API, and set Win32 app supersedence relationships
  - **Nerdio Manager Shell Apps** - build `.zip` packages and upload to Azure Blob Storage for Nerdio Manager Shell Apps
  - **Microsoft 365 Apps** - parse ODT XML configurations, download the M365 setup executable, and build `.intunewin` or `.zip` packages for Intune or Nerdio import
  - **Authentication** - interactive Entra ID sign-in via `Connect-MgGraph` for Intune workflows and Azure sign-in via `Connect-AzAccount` for Nerdio workflows
- **Install** - evaluate App.json detection rules (File, Registry, MSI) against the local machine, resolve the latest installer version, stage content, and execute the install command
- **Update** - run Evergreen module and library updates with real-time output streamed to a dedicated panel
- **Settings** - configure output and library paths, UI theme, log verbosity, and feature visibility toggles for the Import and Install tabs
- **Fluent UI design** - light and dark themes aligned to the Evergreen docs brand palette, with native Windows 11 title bar accent colour applied via DWM
- **Real-time log panel** - timestamped progress log with `Info`, `Warning`, and `Error` levels, updated live from background runspaces
- **Session persistence** - output path, library path, theme, window size, startup view, last-used app, and per-provider settings stored in `$env:APPDATA\EvergreenUI\settings.json`

## V1 Requirements

| Requirement | Minimum |
|---|---|
| Operating system | Windows 10 / Windows Server 2019 or later |
| PowerShell | 5.1 (Desktop) or 7.0+ |
| .NET | .NET Framework 4.7.2+ (for PS 5.1) or .NET 6+ (for PS 7+) |
| Evergreen module | 2603.2832.0 or later (installed from PSGallery) |

No additional DLLs are required. The UI is built entirely using WPF assemblies that ship with Windows.

## Installation

To install the v1 WPF module from the PowerShell Gallery:

```powershell
Install-Module -Name EvergreenUI
```

To run v1 from source:

```powershell
# Install the Evergreen dependency first
Install-Module -Name Evergreen -Scope CurrentUser

# Clone the repository and import the module directly
git clone https://github.com/EUCPilots/evergreen-ui.git
Import-Module .\evergreen-ui\EvergreenUI-v1\EvergreenUI.psd1
```

To load the v2 preview from a repository checkout:

```powershell
Import-Module .\EvergreenUI\EvergreenUI.psd1
Get-EwDefinition -Path .\Definitions
```

The v2 manifest requires Evergreen. `IntuneWin32App`,
`Microsoft.Graph.Authentication`, `Az.Accounts`, `Az.Resources`, and `Az.Storage`
are optional and are checked when the corresponding packaging or provider
command is used.

## V1 Usage

```powershell
Import-Module .\EvergreenUI-v1\EvergreenUI.psd1
Start-EvergreenWorkbench
```

To start the v2 preview interface from the repository, import the v2 manifest:

```powershell
Import-Module .\EvergreenUI\EvergreenUI.psd1
Start-EvergreenWorkbench
```

The v2 interface uses WPF's native theme modes, and runs catalog lookups,
downloads, and library updates through the module's bounded background job
pool. On Windows 11 22H2 and later, its main window and title bar use Mica when
available. Windows transparency and contrast settings can produce a solid
background; unsupported systems use the native opaque title bar.

Its Packages view loads and updates shared Intune App.json definitions
and saves definition and package-output paths. Its Install view reloads those
definitions, checks local detection, resolves latest versions on request, and
supports confirmed batch installation with per-application results. It shows
Definition and Artifact architectures separately and can hide blocked rows for
the current session. Each affected application needs its own architecture
approval; blocked or declined applications are skipped. Changed Definition or
Artifact metadata is reviewed again, with at most two re-confirmations. This
check does not hash downloaded bytes or guarantee that an application will run.

### Apps maintenance

Apps provides Update Evergreen, Clear Workbench cache, and Open cache folder.
Update refreshes Evergreen application data, not the installed PowerShell
module. It keeps the existing local catalog reset, but does not clear the
persistent definition-Artifact cache. Cache clearing is a separate, confirmed
action.

Clear Workbench cache invalidates cached catalogs and clears the default
definition-Artifact cache in
`%LOCALAPPDATA%\EvergreenWorkbench\Cache` (with roaming AppData as a fallback).
It does not remove Evergreen application data, downloaded installers, Library
contents, settings, or provider recovery records. Open cache folder creates
the folder if it does not exist. Coordination metadata is retained when
cached results are cleared.

The headless `Clear-EwCache` command supports WhatIf and Confirm. An explicit
CachePath targets that definition cache and still invalidates catalog caches;
other custom cache directories are not searched or cleared.

```powershell
Update-EwEvergreen
Clear-EwCache -WhatIf
Clear-EwCache -CachePath 'C:\WorkbenchCache' -Confirm
```

Cache invalidation applies across Workbench runspaces and processes sharing
the cache. Queries already running may finish, but cannot cache results
started before the clear. Apps continues to query application Artifacts
directly rather than maintaining a per-app disk cache.

Maintenance runs through the existing background jobs and activity log.
Update and Clear are unavailable while another UI job is active, and the
window cannot close during maintenance writes. Apps refreshes afterward,
including after a partial clear that changed cache state. It preserves valid
selection, search and filters, and never changes queued download versions.
Partial failures are reported without automatic retries. If the follow-up
refresh fails, the maintenance result remains visible and retained data is
marked stale.

### Settings and About

Settings shows the saved Download and Library paths, including their existing
defaults. Change the paths in Apps or Library; the Settings view does not
save edits. Open folder is available only when the folder can be reached.
Appearance remains available in the sidebar.

About shows Workbench metadata and local dependency status. Installed versions
are the highest versions discoverable locally; loaded versions are those in
the Workbench window runspace, which can differ from the caller or a Job.
Status refreshes when About opens and on request, without interrupting another
Job or installing, updating, or importing optional dependencies. If a
refresh fails, the previous results remain visible and are marked stale.

The Intune view connects to Intune and compares saved Definitions. Select
eligible rows to build and publish them after one confirmation. Existing
matched apps are superseded; update-app mode is opt-in per row and assigns the
app as required to All Devices. The batch may update Definition files, stops
between applications when cancelled, and reports partial local and Intune
changes. Supersedence can be retried during the current Workbench session.

### Nerdio Shell Apps

The Nerdio view has collapsible Azure, API and Shell App definition setup.
Connect Azure with the tenant and subscription IDs, then select a resource
group, storage account and blob container. Enter the Nerdio host, client ID,
API scope and client secret, and connect the API. Use Save setup to persist
non-secret configuration; the client secret is cleared from the form when
connecting and is never saved.

Save the Shell App definition folder, then choose Load and compare. Only
valid Evergreen-backed definitions are publishable: unmatched definitions
create Shell Apps, and unambiguous matches with newer versions add a version.
Current apps, duplicate matches and unsupported sources are blocked. The
resolved installer is uploaded directly; local definitions are not changed.

Publish selected requires one confirmation showing versions, operations and
the Azure/Nerdio destination. Files, sources and matches are checked again
before writes. Cancellation takes effect between items, and the current
provider operation finishes first. Results retain known blob, app and job IDs.
Pending or unknown outcomes stop the batch and block further Nerdio publishing
until inspected. The Workbench stores unresolved operation metadata and
successful-publish pruning offers in
`%APPDATA%\EvergreenWorkbench\nerdio-recovery.json`; it never stores tokens or
client secrets. Recovery requires reconnecting to the same tenant, subscription,
Nerdio host and Azure storage destination. Select an unresolved result and use
Review outcome: choose Yes only after confirming success in Nerdio, No only
after confirming failure, or Cancel to leave it unresolved. A claimed publish
success is not accepted until v2 refreshes the Shell App and verifies the
published version is uniquely newest.

After a successful publish, choose Preview version pruning to review saved
pruning offers. The preview selects no apps by default, keeps one version by
default (including the newly published version), and lists the exact versions
to keep or delete. You can change the retention count, select specific apps,
and must confirm the exact deletion list. V2 rechecks the full version snapshot
before deleting; duplicate, unorderable or non-newest published versions are
skipped. A pending or unknown delete stops pruning and requires review. Its
recovery record also blocks publishing to that Shell App until resolved.
Postponed offers remain available across restarts and later batches.

To prune without publishing, select one matched existing Shell App in the
comparison list and choose Prune versions. Publishing eligibility is not
required. The same preview defaults to keeping the newest version and lets
you change retention before confirming exact deletions. Unmatched rows and
multiple selections cannot start this action. All unresolved Nerdio outcomes
or an unavailable recovery store block pruning. V2 rechecks the destination
and version snapshot before deleting, then refreshes comparison results and
restores the selected app when possible. Uncertain deletions are never retried
automatically.

The headless equivalents are `Get-EwNerdioPublishPlan` and
`Publish-EwNerdioBatch`, `Get-EwNerdioShellAppVersionPrunePlan` and
`Remove-EwNerdioShellAppVersion`. The removal command accepts
`-ExpectedVersionNames` and `-ExpectedRemovalVersions` to reject a stale
preview. Nerdio sessions are shared explicitly across the module's Job workers
in memory; expiry, disconnect and provider-configuration changes require
reconnection. Live publishing requires provider access and explicit
authorization; automated tests use mocks.

### Microsoft 365 Apps

The Intune and Nerdio views each have a Microsoft 365 Apps tab. Sign in to the
matching provider, load the folder containing the Office Deployment Tool (ODT)
configuration XML, and select one configuration with a valid, non-empty ID.
Choose the channel, company and session type, then preview and build or preview
and publish. Use Save settings to persist the shared, non-secret selections.
Nerdio build-only can use API-only sign-in; publishing additionally requires
the connected Azure tenant, subscription and storage destination.

The folder must contain `Uninstall-Microsoft365Apps.xml` with a
`Configuration.Remove` element for Nerdio builds and Intune publishing.
Intune build-only can run without this file, but publishing requires rebuilding
with it because the generated uninstall command references the file. Nerdio also needs a
`shell-app` folder containing `Definition.json`, `Detect.ps1`, `Install.ps1`
and `Uninstall.ps1`. Source XML and scripts are not modified.

The preview shows the resolved Office channel version separately from the ODT
download version. Workbench extracts the signed ODT archive using Windows
`tar.exe` without running the downloaded executable. The built configuration
uses a rolling channel and cannot
use `DownloadPath`. An installation may be newer than the preview; Intune
version detection accepts the previewed version or a newer one. The tool
retains the v1 `TenantId` property and writes company as
`AppSettings\Setup Name="Company"`,
but Microsoft does not document these as tenant association or company
configuration. The verified session tenant is not proof that the installed
Office instance is associated with that tenant. Microsoft's documented
[`TenantAssociationKey`](https://learn.microsoft.com/microsoft-365-apps/deploy/office-deployment-tool-configuration-options#tenantassociationkey-property-part-of-property-element)
is a different value and is not generated from the tenant ID.

Publishing requires confirmation before building. Intune creates a new app,
shows existing configuration-ID matches and can optionally supersede one
using an update relationship without uninstalling it. Nerdio can create a
Shell App or add a version to a selected Shell App. Adding the same version
requires explicit attestation that the configuration changed; Nerdio may
still reject it. Preview inputs and provider targets are rechecked before
writes, but these checks are not atomic locks.

Existing packages are replaced only after explicit approval. Builds retain
their staged source and downloaded tool under the output folder's
`<application>\Builds\<GUID>` directory; remove these directories manually
when no longer needed. Cancellation takes effect between stages and does not
interrupt an active build, upload or provider request. Review any partial
result before proceeding; no retry, rollback or provider cleanup is automatic.
Unknown Intune outcomes are stored without secrets and block writes for that
configuration until reviewed and acknowledged in the Intune Microsoft 365
tab. Nerdio pending and unknown outcomes use the Shell Apps recovery controls.

Headless workflows use `Get-EwM365BuildPlan`, `Get-EwM365IntunePublishPlan` or
`Get-EwM365NerdioPublishPlan`, and the corresponding
`Publish-EwM365IntuneApp` or `Publish-EwM365NerdioApp` command. An M365
`New-EwPackage` call without a preview creates one automatically and still
requires the matching provider session.

### Optional Intune connection check

In an authorized tenant, the following read-only check verifies that a
background Job can access the Graph session. It does not publish an app.

```powershell
Connect-EwIntune
$job = Start-EwJob -ScriptBlock {
    Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
    $context = Get-MgContext -ErrorAction Stop
    if ($null -eq $context) { throw 'No Graph context is available in this Job.' }
    [PSCustomObject]@{
        TenantId = $context.TenantId
        AppCount = @(Get-EwIntuneApp).Count
    }
}
do {
    Start-Sleep -Seconds 1
    $snapshot = Get-EwJob -Id $job.Id
} while ($snapshot.State -in @('NotStarted', 'Running', 'Stopping'))
$snapshot.Output
$snapshot.Errors
Remove-EwJob -Id $job.Id -Confirm:$false
```

## Repository structure

```
evergreen-ui/
├── README.md
├── CHANGELOG.md
│
├── EvergreenUI/                        # In-progress v2 module
├── EvergreenUI-v1/                     # v1 reference module
│   ├── EvergreenUI.psd1                # Module manifest
│   ├── EvergreenUI.psm1                # Root module (dot-sources Public + Private)
│   │
│   ├── en-US/
│   │   └── EvergreenUI-help.xml        # Comment-based help
│   │
│   ├── Public/
│   │   └── Start-EvergreenWorkbench.ps1  # Only exported function
│   │
│   ├── Private/
│   │   ├── themes/
│   │   │   ├── Set-LightTheme.ps1
│   │   │   └── Set-DarkTheme.ps1
│   │   ├── Format-LogEntry.ps1
│   │   ├── Get-EvergreenAppList.ps1
│   │   ├── Get-FilterableProperties.ps1
│   │   ├── Get-InstallPackageDefinitions.ps1
│   │   ├── Get-InstallPackageLatestVersion.ps1
│   │   ├── Get-IntunePackageLatestVersion.ps1
│   │   ├── Get-M365AppConfigurations.ps1
│   │   ├── Get-SafeFolderName.ps1
│   │   ├── Get-UIConfig.ps1
│   │   ├── Invoke-AppDownload.ps1
│   │   ├── Invoke-AzureSignIn.ps1      # Contains all Azure/Nerdio auth helpers
│   │   ├── Invoke-FilterUpdate.ps1
│   │   ├── Invoke-IntuneDefinitionUpdate.ps1
│   │   ├── Invoke-IntuneGraphWin32Import.ps1
│   │   ├── Invoke-IntunePackageBuild.ps1
│   │   ├── Invoke-LibraryUpdate.ps1
│   │   ├── Invoke-LocalPackageInstall.ps1
│   │   ├── Invoke-M365AppPackageBuild.ps1
│   │   ├── Invoke-M365AppShellAppBuild.ps1
│   │   ├── Merge-ConfigSection.ps1
│   │   ├── New-FilterPanel.ps1
│   │   ├── New-WpfRunspace.ps1
│   │   ├── Set-DwmTitleBarColor.ps1
│   │   ├── Set-IntuneGraphWin32Supersedence.ps1
│   │   ├── Set-UIConfig.ps1
│   │   ├── Test-EvergreenModule.ps1
│   │   ├── Test-LocalPackageDetection.ps1
│   │   ├── Write-UILog.ps1
│   │   └── Write-UpdateOutput.ps1
│   │
│   └── Resources/
│       ├── EvergreenUI.xaml            # WPF UI definition (~3,900 lines)
│       ├── Install.ps1                 # Generic Intune package installer
│       ├── NerdioShellApps.psm1        # Bundled Nerdio Shell Apps helper module
│       ├── m365-app.json               # Microsoft 365 Apps App.json template
│       └── evergreenbulk.png
│
└── tests/                              # Pester tests
    └── EvergreenUI.tests.ps1
```

## Contributing

This module follows the same conventions as the [Evergreen](https://github.com/EUCPilots/evergreen-module) and [evergreen-apps](https://github.com/EUCPilots/evergreen-apps) repositories:

- Strict mode (`Set-StrictMode -Version Latest`) in all scripts
- `$ErrorActionPreference = 'Stop'` at script scope
- PowerShell 5.1 and 7+ compatible syntax (no `??=`, no ternary in 5.1 code paths)
- PSScriptAnalyzer clean (default ruleset)
- Pester tests for all Public functions

## Licence

[MIT](LICENSE)
