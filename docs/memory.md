# EvergreenUI — Session Memory

> This file is the authoritative record of design decisions, implementation state,
> and next steps. Update it at the end of every working session.
>
> Last updated: 2026-03-13

---

## Working Directory

```
/Users/aaron/projects/_EUCPilots/evergreen-ui
```

All file paths in this document are relative to that root unless otherwise stated.

---

## Project Purpose

**EvergreenUI** is a WPF-based graphical frontend for the
[Evergreen PowerShell module](https://github.com/EUCPilots/evergreen-module).
It ships as a **separate module** (`EvergreenUI`) so it never pollutes the core `Evergreen`
module — mirroring the same separation used across the EUCPilots repo.

Constraints that must never be violated:
- Windows only — no Linux/macOS support
- No external DLLs — pure PowerShell + built-in WPF assemblies only
- Supports PowerShell 5.1 (Desktop) **and** PowerShell 7+ (Core on Windows)
- `Set-StrictMode -Version Latest` in every file
- UI style: Microsoft Fluent UI, referencing `Start-CitrixExportGui.ps1` as the pattern
- Brand palette: Evergreen teal (`#009485` light / `#4DB8AD` dark)

---

## Repository Structure

```
evergreen-ui/
├── MEMORY.md                          ← this file
├── CHANGELOG.md
├── LICENSE
├── README.md
├── docs/
│   ├── plan.md                        ← full architecture spec (canonical reference)
│   └── filter-design.md              ← dynamic filter panel design spec
├── prototype/
│   └── EvergreenUI-Prototype.html    ← HTML/CSS interactive prototype (theming reference)
├── EvergreenUI/                       ← the actual PowerShell module
│   ├── EvergreenUI.psd1
│   ├── EvergreenUI.psm1
│   ├── Public/
│   │   └── Start-EvergreenUI.ps1
│   └── Private/
│       ├── themes/
│       │   ├── Set-LightTheme.ps1   ✅ implemented
│       │   └── Set-DarkTheme.ps1    ✅ implemented
│       ├── New-WpfRunspace.ps1      ✅ implemented
│       ├── Write-UILog.ps1          ✅ implemented
│       ├── Test-EvergreenModule.ps1 ✅ implemented
│       ├── Get-FilterableProperties.ps1 ✅ implemented
│       ├── Invoke-FilterUpdate.ps1  ✅ implemented
│       ├── New-FilterPanel.ps1      ⚠️  stub — filter state init only, no WPF controls yet
│       ├── Get-UIConfig.ps1         ✅ implemented
│       ├── Set-UIConfig.ps1         ✅ implemented
│       ├── Get-EvergreenAppList.ps1 ✅ implemented
│       ├── Invoke-AppDownload.ps1   ✅ implemented
│       └── Invoke-LibraryUpdate.ps1 ✅ implemented
└── tests/
    └── EvergreenUI.tests.ps1        ✅ Pester scaffold exists
```

---

## Implementation Status by Phase

| Phase | Description | Status |
|---|---|---|
| 1 | Module scaffold — `psd1`, `psm1`, folder structure | ✅ Done (see known issues below) |
| 2 | Shared helpers — runspace factory, log, theme, config, filter helpers | ✅ Done |
| 3 | Shell window — nav rail, log panel, theme toggle, Evergreen status | ✅ Done |
| 4 | Apps view — `Find-EvergreenApp` list + `Get-EvergreenApp` detail + filter panel | ❌ Not started |
| 5 | Download view — `Save-EvergreenApp` with sequential queue | ❌ Not started |
| 6 | Library view — library CRUD + `Start-EvergreenLibraryUpdate` | ❌ Not started |
| 7 | Settings + persistence — config.json read/write, startup theme, last-used paths | ❌ Not started |
| 8 | Polish — keyboard shortcuts, validation, error handling, help tooltips | ❌ Not started |

---

## Known Issues / TODOs Before Phase 4

1. **`New-FilterPanel.ps1` — Phase 4 work** — the stub initialises `$syncHash.FilterState`
   correctly but does not yet build any WPF controls. This is intentional (Phase 4 work).

2. **Phase 3 shell — content panels are placeholder stubs** — `AppsPanel`, `DownloadPanel`,
   and `LibraryPanel` show "coming in Phase X" TextBlocks. These are replaced in Phases 4–6.

---

## Confirmed Design Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Window model | Single window with view-swap (no secondary windows) |
| 2 | View switching | Toggle `Visibility` on named `Grid` panels — no `Frame`, no `TabControl` |
| 3 | App list caching | Session-only — `Find-EvergreenApp` result cached in `$syncHash.AppList`; no disk TTL |
| 4 | Multi-app downloads | **Queue — sequential**. `$syncHash.DownloadQueue` is a `List[PSCustomObject]` |
| 5 | Library update scope | **Whole library only** — `Start-EvergreenLibraryUpdate -Path` called against full path |
| 6 | Log panel | **Collapsible** via `GridSplitter`; has **Copy log** and **Save log** buttons |
| 7 | Path persistence | Output path + library path + theme → `$env:APPDATA\EvergreenUI\config.json` |
| 8 | Navigation | Left-rail `RadioButton` toggle-group (Fluent `NavigationView` pattern) |
| 9 | Threading | STA UI thread + worker `Runspace`s via `New-WpfRunspace`; UI updates via `Dispatcher.Invoke` |
| 10 | XAML delivery | Inline `[xml]$xaml = @"..."@` here-strings — no external `.xaml` files at runtime |

---

## UI Shell Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  Evergreen        [Evergreen module: v2503.x  ● Installed]          │  ← title bar
├──────────┬──────────────────────────────────────────────────────────┤
│          │                                                           │
│  Apps    │   <content area — view panels swapped here>              │
│          │                                                           │
│  Download│                                                           │
│          │                                                           │
│  Library │                                                           │
│          │                                                           │
│  ──────  │                                                           │
│  Settings│                                                           │
│          │                                                           │
├──────────┴──────────────────────────────────────────────────────────┤
│  [●] Light theme          [Copy log] [Save log]   [Progress log ▾]  │  ← status/log bar
│  ─────────────────────────────────────────────────────────────────  │  ← GridSplitter
│  [HH:mm:ss] [INFO] Log output...                                    │  ← log panel
└─────────────────────────────────────────────────────────────────────┘
```

---

## syncHash Contract

Every key that any private function touches must be documented here.
Functions must not add undocumented keys.

| Key | Type | Set by | Read by |
|---|---|---|---|
| `Window` | `System.Windows.Window` | `Start-EvergreenUI` | all |
| `LogTextBox` | `TextBox` | `Start-EvergreenUI` | `Write-UILog` |
| `LogScrollViewer` | `ScrollViewer` | `Start-EvergreenUI` | `Write-UILog` |
| `IsRunning` | `bool` | `Start-EvergreenUI` / runspaces | `Run` button handler |
| `IsAdmin` | `bool` | `Start-EvergreenUI` | settings view |
| `AppList` | `PSCustomObject[]` | `Get-EvergreenAppList` | Apps / Download views |
| `CurrentAppResults` | `PSObject[]` | Download view runspace | `Invoke-FilterUpdate` |
| `FilterState` | `hashtable` (prop→`HashSet[string]`) | `New-FilterPanel` | `Invoke-FilterUpdate` |
| `VersionsListView` | `ListView` | Download view | `Invoke-FilterUpdate` |
| `ResultsCountLabel` | `TextBlock` | Download view | `Invoke-FilterUpdate` |
| `DownloadQueue` | `List[PSCustomObject]` | Download view | `Invoke-AppDownload` |
| `EvergreenVersion` | `string` | `Start-EvergreenUI` on load | title bar TextBlock |
| `Config` | `PSCustomObject` | `Get-UIConfig` on load | `Set-UIConfig` on close |

---

## Brush / Resource Dictionary Keys

All theme functions must keep these keys in sync. Never add a key in one theme file without adding it to the other.

| Key | Light | Dark |
|---|---|---|
| `WindowBackgroundBrush` | `#F3F4F4` | `#141D1C` |
| `TextPrimaryBrush` | `#1A1A1A` | `#E8F2F0` |
| `TextSecondaryBrush` | `#4D5A58` | `#90AAA7` |
| `AccentBrush` | `#009485` | `#4DB8AD` |
| `AccentHoverBrush` | `#01786C` | `#67B9C9` |
| `AccentLightBrush` | `#D9F2EF` | `#0D2926` |
| `ControlBackgroundBrush` | `#FFFFFF` | `#1C2826` |
| `ControlBorderBrush` | `#DDE2E1` | `#2E3F3C` |
| `ButtonForegroundBrush` | `#FFFFFF` | `#000000` |
| `ToggleThumbBrush` | `#FFFFFF` | `#000000` |

---

## Dynamic Filter Panel Design

Full spec in `docs/filter-design.md`. Summary:

**Display-only properties** (never filterable): `Version`, `URI`, `Date`, `Expiry`, `SHA256`, `Hash`, `Checksum`, `Size`

**Control type by cardinality:**
| Unique values | Control |
|---|---|
| 2–6 | `CheckBoxStrip` — horizontal row of CheckBoxes |
| 7–20 | `MultiListBox` — scrollable ListBox, `SelectionMode=Multiple`, 4 rows visible |
| 21+ | `TextBox` — free-text contains-match |

**Defaults:** All values selected on load. Empty selection = "no filter" (shows all rows).

**Synthetic Type:** If no `Type` property but `URI` exists, derive file extension from URI and
create a synthetic `_DerivedType` / "File type (derived)" filter. Handled in `Get-FilterableProperties`.

---

## Download Queue Item Schema

```powershell
[PSCustomObject]@{
    AppName      = 'MicrosoftEdge'   # string
    Version      = '123.0.2420.97'   # string
    Platform     = 'Windows'          # string or $null
    Architecture = 'x64'              # string or $null
    Channel      = 'Stable'           # string or $null
    Uri          = 'https://...'      # string
    Status       = 'Pending'          # 'Pending' | 'Downloading' | 'Done' | 'Failed'
}
```

---

## Config File Schema

Path: `$env:APPDATA\EvergreenUI\config.json`

```json
{
  "OutputPath":   "D:\\Installers",
  "LibraryPath":  "D:\\EvergreenLibrary",
  "Theme":        "Light",
  "LogVerbosity": "Normal",
  "LogHeight":    150
}
```

Handled by `Get-UIConfig` (read, with defaults merge) and `Set-UIConfig` (write, non-terminating).

---

## Style Names to Define in Shell XAML

| Style key | Target type | Notes |
|---|---|---|
| `FluentButton` | `Button` | Accent background, rounded 4px, hover opacity 0.8 |
| `FluentSecondaryButton` | `Button` | `ControlBackgroundBrush` bg, border, same shape |
| `FluentTextBox` | `TextBox` | 1px border, 8px padding, `ControlBackgroundBrush` |
| `FluentListView` | `ListView` | No border, alternating row shade, hover highlight |
| `FluentCheckBox` | `CheckBox` | Accent tick colour |
| `FluentRadioButton` | `RadioButton` | Full-width pill, nav-rail item |
| `NavRailRadioButton` | `RadioButton` | Active = 3px left inset border in `AccentBrush` |
| `StatusDot` | `Ellipse` | 8×8px, colour set in code-behind per status |

---

## Evergreen Cmdlet Reference

| What the UI needs | Cmdlet |
|---|---|
| List all available apps | `Find-EvergreenApp` |
| Get versions for a specific app | `Get-EvergreenApp -Name <string>` |
| Download a specific version | `Save-EvergreenApp -InputObject <psobject> -Path <string>` |
| List library contents | `Get-EvergreenLibrary -Path <string>` |
| Get an app from the library | `Get-EvergreenAppFromLibrary -Name <string> -Path <string>` |
| Update the whole library | `Start-EvergreenLibraryUpdate -Path <string>` |

App results output shape reference: https://stealthpuppy.com/apptracker/
Raw data: https://github.com/aaronparker/apptracker

---

## Reference Files

| File | Purpose |
|---|---|
| `Start-CitrixExportGui.ps1` (project root) | Pattern reference for WPF here-string XAML, runspace threading, Dispatcher.Invoke, theme toggle, browse dialogs |
| `prototype/EvergreenUI-Prototype.html` | Visual/theming reference — colour palette, layout proportions, nav rail appearance |
| `docs/plan.md` | Full architecture spec including ASCII wireframes for every view |
| `docs/filter-design.md` | Detailed filter panel property taxonomy and control-type rules |

---

## Next Actions (in order)

1. ✅ Phase 1 gaps — all resolved (`psd1` fixed, three private functions created)
2. ✅ Phase 3 — shell window complete; nav, theme toggle, log panel, GridSplitter, Settings view all wired
3. **Phase 4** — Apps view (`AppsPanel`):
  - App selector (ComboBox) calls `Get-EvergreenAppList` on load; results cached in `$syncHash.AppList`
  - On selection: `Get-EvergreenApp -Name` in a runspace → `$syncHash.CurrentAppResults`
  - Complete `New-FilterPanel` WPF control construction (`CheckBoxStrip`, `MultiListBox`, `TextBox`)
  - Filter change → `Invoke-FilterUpdate` → update `VersionsListView` and `ResultsCountLabel`
  - "Add to queue" button appends selected row to `$syncHash.DownloadQueue`
4. **Phase 5** — Download view (`DownloadPanel`):
  - Queue ListView bound to `$syncHash.DownloadQueue`
  - "Download all" button → sequential `Invoke-AppDownload` in a runspace
5. **Phase 6** — Library view (`LibraryPanel`):
  - Library path display + "Update library" button → `Invoke-LibraryUpdate` in a runspace
6. Phases 7–8 per `docs/plan.md` (settings persistence polish, keyboard shortcuts)
