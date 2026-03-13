# EvergreenUI

A WPF-based graphical frontend for the [Evergreen](https://eucpilots.com/evergreen-docs/) PowerShell module.

EvergreenUI ships as a separate PowerShell module so it never modifies the core Evergreen module. It targets Windows only, requires no external DLLs, and supports both **PowerShell 5.1** (Desktop) and **PowerShell 7+**.

> **Status:** Pre-release — design and prototyping phase. Not yet functional.

## Features (planned)

- **Apps view** — search and browse all 500+ Evergreen-supported applications; inspect version and download metadata returned by `Get-EvergreenApp`
- **Dynamic filters** — filter panel builds itself at runtime from whatever properties a given app actually returns (Architecture, Channel, Ring, Language, Type, Release, etc.)
- **Download queue** — select multiple app/version combinations and download them sequentially via `Save-EvergreenApp`
- **Library management** — create, inspect, and update an Evergreen library on disk using `New-EvergreenLibrary`, `Get-EvergreenLibrary`, `Start-EvergreenLibraryUpdate`, and `Get-EvergreenAppFromLibrary`
- **Fluent UI design** — light and dark themes aligned to the Evergreen docs brand palette
- **Real-time log panel** — collapsible progress log with copy and save support
- **Session persistence** — last-used paths and theme stored in `$env:APPDATA\EvergreenUI\config.json`

## Requirements

| Requirement | Minimum |
|---|---|
| Operating system | Windows 10 / Windows Server 2019 or later |
| PowerShell | 5.1 (Desktop) or 7.0+ |
| .NET | .NET Framework 4.7.2+ (for PS 5.1) or .NET 6+ (for PS 7+) |
| Evergreen module | Latest stable (installed from PSGallery) |

No additional DLLs are required. The UI is built entirely using WPF assemblies that ship with Windows.

## Installation

> Not yet published. Steps below describe the intended install experience.

```powershell
# Install the Evergreen dependency first
Install-Module -Name Evergreen -Scope CurrentUser

# Install EvergreenUI from PSGallery (once published)
Install-Module -Name EvergreenUI -Scope CurrentUser
```

## Usage

```powershell
Import-Module EvergreenUI
Start-EvergreenUI
```

## Repository structure

```
EvergreenUI/
├── .gitignore
├── README.md
├── CHANGELOG.md
│
├── docs/                          # Design documents and specifications
│   ├── plan.md                    # Architecture and module design plan
│   └── filter-design.md           # Dynamic filter panel specification
│
├── prototype/                     # Static HTML UI prototype (no live data)
│   └── EvergreenUI-Prototype.html
│
├── EvergreenUI/                   # The PowerShell module
│   ├── EvergreenUI.psd1           # Module manifest
│   ├── EvergreenUI.psm1           # Root module (dot-sources Public + Private)
│   │
│   ├── Public/
│   │   └── Start-EvergreenUI.ps1  # Only exported function — launches the GUI
│   │
│   └── Private/
│       ├── themes/
│       │   ├── Set-LightTheme.ps1
│       │   └── Set-DarkTheme.ps1
│       ├── New-WpfRunspace.ps1
│       ├── Write-UILog.ps1
│       ├── Test-EvergreenModule.ps1
│       ├── Get-FilterableProperties.ps1
│       ├── New-FilterPanel.ps1
│       ├── Invoke-FilterUpdate.ps1
│       ├── Get-UIConfig.ps1
│       └── Set-UIConfig.ps1
│
└── tests/                         # Pester tests
    └── EvergreenUI.tests.ps1
```

## Design documentation

Full design decisions are recorded in the `/docs` folder:

- [`docs/plan.md`](docs/plan.md) — module architecture, view layouts, threading model, build phases
- [`docs/filter-design.md`](docs/filter-design.md) — dynamic filter panel design, property taxonomy, edge case handling

A static interactive HTML prototype is available at [`prototype/EvergreenUI-Prototype.html`](prototype/EvergreenUI-Prototype.html) — open it in any browser to explore the intended UI with dummy data. No server or build step required.

## Contributing

This module follows the same conventions as the [Evergreen](https://github.com/EUCPilots/evergreen-module) and [evergreen-apps](https://github.com/EUCPilots/evergreen-apps) repositories:

- Strict mode (`Set-StrictMode -Version Latest`) in all scripts
- `$ErrorActionPreference = 'Stop'` at script scope
- PowerShell 5.1 and 7+ compatible syntax (no `??=`, no ternary in 5.1 code paths)
- PSScriptAnalyzer clean (default ruleset)
- Pester tests for all Public functions

## Licence

[MIT](LICENSE)
