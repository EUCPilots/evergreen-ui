# Evergreen Workbench

A WPF-based graphical frontend for the [Evergreen](https://eucpilots.com/evergreen/) PowerShell module.

Evergreen Workbench ships as a separate PowerShell module so it never modifies the core Evergreen module. It targets Windows only, requires no external DLLs, and supports both **PowerShell 5.1** (Desktop) and **PowerShell 7+**.

## Features

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

## Requirements

| Requirement | Minimum |
|---|---|
| Operating system | Windows 10 / Windows Server 2019 or later |
| PowerShell | 5.1 (Desktop) or 7.0+ |
| .NET | .NET Framework 4.7.2+ (for PS 5.1) or .NET 6+ (for PS 7+) |
| Evergreen module | 2603.2832.0 or later (installed from PSGallery) |

No additional DLLs are required. The UI is built entirely using WPF assemblies that ship with Windows.

## Installation

To install from the PowerShell Gallery:

```powershell
Install-Module -Name EvergreenUI
```

To run from source:

```powershell
# Install the Evergreen dependency first
Install-Module -Name Evergreen -Scope CurrentUser

# Clone the repository and import the module directly
git clone https://github.com/EUCPilots/evergreen-ui.git
Import-Module ./evergreen-ui/EvergreenUI/EvergreenUI.psd1
```

## Usage

```powershell
Import-Module EvergreenUI
Start-EvergreenWorkbench
```

## Repository structure

```
evergreen-ui/
├── README.md
├── CHANGELOG.md
│
├── EvergreenUI/                        # The PowerShell module
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
