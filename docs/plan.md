# EvergreenUI PowerShell Module — Design Plan

## Overview

**EvergreenUI** is a WPF-based graphical frontend for the Evergreen PowerShell module. It ships as a
separate module (`EvergreenUI`) so it never pollutes the core `Evergreen` module, mirroring the same
separation used across the EUCPilots repo. It targets Windows only, requires no external DLLs, and
supports both PowerShell 5.1 (WPF via `PresentationFramework`) and PowerShell 7+ (same assemblies,
loaded via `Add-Type`).

---

## Module Structure

```
EvergreenUI/
├── EvergreenUI.psd1                  # Module manifest
├── EvergreenUI.psm1                  # Root module – dot-sources Public + Private
│
├── Public/
│   └── Start-EvergreenUI.ps1         # Only exported function – launches the GUI
│
├── Private/
│   ├── themes/
│   │   ├── Set-LightTheme.ps1
│   │   └── Set-DarkTheme.ps1
│   ├── New-WpfRunspace.ps1           # Factory: creates a clean STA runspace
│   ├── Write-UILog.ps1               # Thread-safe dispatcher-based log helper
│   ├── Test-EvergreenModule.ps1      # Checks Evergreen is installed / importable
│   ├── Get-EvergreenAppList.ps1      # Wraps Find-EvergreenApp for UI consumption
│   ├── Invoke-AppDownload.ps1        # Wraps Get-EvergreenApp + Save-EvergreenApp
│   └── Invoke-LibraryUpdate.ps1     # Wraps Start-EvergreenLibraryUpdate
│
└── XAML/
    ├── MainWindow.xaml               # Shell: navigation + content host
    ├── Views/
    │   ├── AppsView.xaml             # Find / inspect apps
    │   ├── DownloadView.xaml         # Download an app (Get + Save)
    │   └── LibraryView.xaml         # Library management
    └── Shared/
        ├── Styles.xaml               # Fluent brushes, button/textbox styles
        └── DataTemplates.xaml        # ListView item templates
```

> **XAML as here-strings** – All XAML lives as `[xml]$xaml = @"..."@` inside each script (same
> pattern as `Start-CitrixExportGui.ps1`). The `/XAML/` folder above documents intent; at runtime
> everything is inlined so there is no file-system dependency.

---

## UI Architecture

### Shell: Left-nav + Content Area (Fluent NavigationView pattern)

```
┌─────────────────────────────────────────────────────────────┐
│  Evergreen          [Evergreen module: v1.x.x  ●Installed]  │  ← Title bar row
├──────────┬──────────────────────────────────────────────────┤
│          │                                                   │
│  Apps    │   <Content view switches here>                    │
│          │                                                   │
│  Library │                                                   │
│          │                                                   │
│  ──────  │                                                   │
│  Settings│                                                   │
│          │                                                   │
├──────────┴──────────────────────────────────────────────────┤
│  [●] Light theme                         [Progress log ▾]   │  ← Status bar
└─────────────────────────────────────────────────────────────┘
```

The navigation rail is a `StackPanel` of styled `RadioButton` controls (toggle-group trick) – no
`TabControl` chrome, purely Fluent-styled. Content is swapped by toggling `Visibility` on named
`Grid` panels rather than using a `Frame`, keeping everything in a single STA thread with no
navigation overhead.

### Collapsible Log Panel

A `GridSplitter`-enabled row at the bottom hosts the progress log (same `Consolas` / `TextBox`
pattern from the Citrix example). It can be collapsed to a single-line status strip by dragging the
splitter up, preserving screen space during normal browsing.

---

## Views

### 1. Apps View  (`Find-EvergreenApp` + `Get-EvergreenApp`)

**Purpose:** Browse the full Evergreen app catalogue, inspect version/URI data, and hand off to the
Download view.

**Layout:**
```
┌─ Apps ──────────────────────────────────────────────────────┐
│  Search: [___________________________]  [Search]            │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Name              │ Application   │ Publisher         │  │
│  │ ──────────────────┼───────────────┼────────────────── │  │
│  │ MicrosoftEdge     │ Microsoft E.. │ Microsoft         │  │
│  │ GoogleChrome      │ Google Chr..  │ Google            │  │
│  │ ...                                                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Selected: MicrosoftEdge                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Version │ Platform  │ Channel │ URI                   │  │
│  │ 123.0.. │ Windows   │ Stable  │ https://...           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  [Get latest version info]          [Download this app ▶]  │
└─────────────────────────────────────────────────────────────┘
```

**Cmdlets used:**
| Action | Cmdlet |
|---|---|
| Populate list on load | `Find-EvergreenApp` |
| Filter list (search box) | `Find-EvergreenApp -Name <query>` |
| Populate version detail grid | `Get-EvergreenApp -Name <selected>` |

**Key behaviours:**
- App list loads asynchronously in a runspace on view activation; list is cached for the session.
- Search filters client-side (already-loaded list) first; falls back to `Find-EvergreenApp -Name`
  if no local match after 500 ms debounce.
- Selecting a row in the version detail grid pre-populates the Download view and enables the
  **Download this app** button.

---

### 2. Download View  (`Get-EvergreenApp` + `Save-EvergreenApp`)

**Purpose:** Download one or more app versions to a chosen output folder.

**Layout:**
```
┌─ Download ───────────────────────────────────────────────────┐
│  Application:  [MicrosoftEdge           ▾] [Refresh]        │
│  Output path:  [_________________________] [Browse]         │
│                                                              │
│  Available versions                                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  ☑ │ Version  │ Platform  │ Channel │ Architecture    │  │
│  │  ☑ │ 123.0..  │ Windows   │ Stable  │ x64             │  │
│  │  ☐ │ 123.0..  │ Windows   │ Stable  │ x86             │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  [Select all]  [Clear]                   [Download ▶]       │
└──────────────────────────────────────────────────────────────┘
```

**Cmdlets used:**
| Action | Cmdlet |
|---|---|
| Refresh version list | `Get-EvergreenApp -Name <app>` |
| Download checked rows | `Save-EvergreenApp -InputObject <rows> -Path <output>` |

**Key behaviours:**
- App name pre-filled when navigating from Apps view.
- Each checked row is piped individually to `Save-EvergreenApp` inside a runspace so progress per
  file can be reported to the log.
- Download button disabled while a download is already running (guard via `$syncHash.IsRunning`).
- After completion, **Open folder** button becomes active.

---

### 3. Library View  (`New-EvergreenLibrary` + `Get-EvergreenLibrary` + `Start-EvergreenLibraryUpdate` + `Get-EvergreenAppFromLibrary`)

**Purpose:** Create, inspect, and maintain an Evergreen library on disk.

**Layout:**
```
┌─ Library ────────────────────────────────────────────────────┐
│  Library path: [_________________________] [Browse] [New]   │
│                                                              │
│  ┌─ Library contents ─────────────────────────────────────┐ │
│  │ App name          │ Count │ Latest version │ Path       │ │
│  │ ─────────────────-┼───────┼────────────────┼─────────── │ │
│  │ MicrosoftEdge     │  2    │ 123.0.x.x      │ ...        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ Selected app ─────────────────────────────────────────┐ │
│  │ Version │ Platform │ Channel │ Architecture │ Path      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  [Refresh library]  [Update library ▶]  [Open folder]       │
└──────────────────────────────────────────────────────────────┘
```

**Cmdlets used:**
| Action | Cmdlet |
|---|---|
| Create new library | `New-EvergreenLibrary -Path <path>` |
| Load library contents | `Get-EvergreenLibrary -Path <path>` |
| Populate app detail | `Get-EvergreenAppFromLibrary -Name <app> -Path <path>` |
| Update library | `Start-EvergreenLibraryUpdate -Path <path>` |

**Key behaviours:**
- Last-used library path persisted to `$env:APPDATA\EvergreenUI\config.json` between sessions.
- **New** button calls `New-EvergreenLibrary` then immediately reloads via `Get-EvergreenLibrary`.
- **Update library** runs `Start-EvergreenLibraryUpdate` in a runspace; log streams output; button
  disabled for the duration.
- Double-clicking a library app row triggers `Get-EvergreenAppFromLibrary` and populates the detail
  grid below.

---

### 4. Settings View

Simple form; no cmdlets. Persists to `$env:APPDATA\EvergreenUI\config.json`.

| Setting | Control | Notes |
|---|---|---|
| Default output path | TextBox + Browse | Pre-fills Download view |
| Default library path | TextBox + Browse | Pre-fills Library view |
| Theme | Toggle (Light/Dark) | Persisted, applied on startup |
| Log verbosity | RadioButton (Normal / Verbose) | Controls `-Verbose` on cmdlet calls |

---

## Threading Model

Identical to `Start-CitrixExportGui.ps1`:

1. **UI thread** – STA, owns the `Window` and all controls.
2. **Worker runspaces** – Created per operation via `New-WpfRunspace.ps1`, passed a `$syncHash`
   containing control references. All UI updates dispatched back via
   `$syncHash.Window.Dispatcher.Invoke(...)`.
3. **`$syncHash`** – `[hashtable]::Synchronized(@{})` holding shared state: `IsRunning`, control
   references, the loaded app list cache, and current library path.

No `Start-Job` / `Invoke-Command` – runspaces only, for clean STA compatibility with PS 5.1.

---

## Shared Private Helpers

### `New-WpfRunspace.ps1`
Factory that:
- Creates a `[runspacefactory]::CreateRunspace()`
- Sets `ApartmentState = "STA"` and `ThreadOptions = "ReuseThread"`
- Injects `$syncHash` via `SessionStateProxy.SetVariable`
- Opens and returns the runspace ready for a `[powershell]::Create()` to attach to

### `Write-UILog.ps1`
```powershell
function Write-UILog {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Level = 'Info'
    )
    # Prefixes [HH:mm:ss] [LEVEL], dispatches to LogTextBox on UI thread
}
```

### `Test-EvergreenModule.ps1`
Checks `Get-Module -ListAvailable -Name Evergreen` and reports installed version to
`$syncHash.SdkStatusTextBlock` (same pattern as the Citrix SDK check).

---

## Module Manifest Highlights (`EvergreenUI.psd1`)

```powershell
@{
    ModuleVersion     = '0.1.0'
    GUID              = '<new-guid>'
    Author            = '<author>'
    Description       = 'WPF GUI frontend for the Evergreen PowerShell module'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Evergreen')
    FunctionsToExport = @('Start-EvergreenUI')
    PrivateData       = @{
        PSData = @{
            Tags = @('Evergreen', 'GUI', 'WPF', 'EUC', 'EvergreenUI')
        }
    }
}
```

`RequiredModules = @('Evergreen')` means PowerShell auto-checks the dependency on import.

---

## Fluent UI Design Conventions

All UI follows the same resource-dictionary / `DynamicResource` approach from
`Start-CitrixExportGui.ps1`:

| Token | Light | Dark |
|---|---|---|
| `WindowBackgroundBrush` | `#F0F0F0` | `#202020` |
| `ControlBackgroundBrush` | `#FFFFFF` | `#2D2D2D` |
| `TextPrimaryBrush` | `#000000` | `#FFFFFF` |
| `TextSecondaryBrush` | `#606060` | `#B0B0B0` |
| `AccentBrush` | `#3D6EA5` | `#60CDFF` |
| `ControlBorderBrush` | `#C8C8C8` | `#404040` |

Additional shared styles beyond the Citrix example:
- `FluentListView` – `ListView` with alternating row shading, no border, hover highlight via
  `ControlTemplate` triggers.
- `FluentCheckBox` – borderless, accent-coloured tick.
- `FluentRadioButton` – used as navigation items; styled as full-width pill buttons.
- `StatusDot` – 8×8 `Ellipse` coloured green/amber/red for module status indicators.

---

## Build / Delivery Order

| Phase | Deliverable | Scope |
|---|---|---|
| 1 | Module scaffold | `psd1`, `psm1`, folder structure, empty Public/Private stubs |
| 2 | Shared helpers | `New-WpfRunspace`, `Write-UILog`, `Test-EvergreenModule`, theme functions |
| 3 | Shell window | `Start-EvergreenUI` – navigation rail, log panel, theme toggle, Evergreen status |
| 4 | Apps view | `Find-EvergreenApp` list + `Get-EvergreenApp` detail grid |
| 5 | Download view | `Save-EvergreenApp` with per-file progress |
| 6 | Library view | Full library CRUD + `Start-EvergreenLibraryUpdate` |
| 7 | Settings + persistence | `config.json` read/write, last-used paths, startup theme |
| 8 | Polish | Keyboard shortcuts, input validation, error handling, help tooltips |

---

## Confirmed Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Window model | Single window with view-swap (no secondary windows) |
| 2 | App list caching | Session-only (`Find-EvergreenApp` result cached in `$syncHash`; no TTL persistence) |
| 3 | Multi-app downloads | **Queue – sequential downloads.** Download view accepts multiple app/version selections; each item is downloaded in turn inside a single runspace, logging per-file progress. |
| 4 | Library update scope | **Whole library only.** No per-app update; `Start-EvergreenLibraryUpdate -Path` called against the full library path. |
| 5 | Log panel | **Collapsible** via `GridSplitter`; includes **Copy log** and **Save log** buttons. |
| 6 | Path persistence | Last-used output path, library path, and theme persisted to `$env:APPDATA\EvergreenUI\config.json`. |

---

## Revised Download View — Queue Model

```
┌─ Download ────────────────────────────────────────────────────┐
│  Application:  [MicrosoftEdge           ▾]  [Get versions]   │
│                                                               │
│  Available versions                    [☑ Select all] [Clear] │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  ☑ │ Version   │ Platform │ Channel  │ Architecture    │  │
│  │  ☑ │ 123.0..   │ Windows  │ Stable   │ x64             │  │
│  │  ☐ │ 123.0..   │ Windows  │ Stable   │ x86             │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  [+ Add to queue]                                             │
│                                                               │
│  Download queue                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  App              │ Version   │ Architecture │ Status   │  │
│  │  MicrosoftEdge    │ 123.0..   │ x64          │ Pending  │  │
│  │  GoogleChrome     │ 125.0..   │ x64          │ Pending  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Output path:  [_______________________________]  [Browse]   │
│                                                               │
│  [Remove selected]  [Clear queue]         [Download all ▶]   │
└───────────────────────────────────────────────────────────────┘
```

Queue state lives in `$syncHash.DownloadQueue` as an `[System.Collections.Generic.List[PSCustomObject]]`.
Each item carries: `AppName`, `Version`, `Platform`, `Architecture`, `Channel`, `Uri`, `Status`
(`Pending` → `Downloading` → `Done` / `Failed`). Status column updates in-place via
`Dispatcher.Invoke` as each item is processed sequentially in the worker runspace.
