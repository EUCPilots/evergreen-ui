# EvergreenUI — Filter Design Specification

## The Core Problem

`Get-EvergreenApp` returns a `PSObject[]` where:
- **Every app** has `Version` and `URI` — the only guaranteed properties
- **Most apps** have some subset of a well-known set of properties
- **Some apps** have unique properties found nowhere else
- **Property names are inconsistent across apps** — `Ring` vs `Channel` vs `Release` all serve the
  same semantic purpose (update cadence) on different apps
- **Property values are inconsistent within the same property** — `Architecture` is always
  `x64`/`x86`/`arm64`, but `Type` could be `Msi`/`msi`/`MSI` depending on the app

This means a static filter UI is impossible. The filter panel must be **built at runtime** from
the actual data returned for the selected app.

---

## Real-World Property Inventory

Compiled from the Evergreen API, documentation, and apptracker data:

| Property | Present on | Example values | Notes |
|---|---|---|---|
| `Version` | All apps | `145.0.3800.97` | Always present; display-only |
| `URI` | All apps | `https://...` | Always present; display-only |
| `Architecture` | ~85% of apps | `x64`, `x86`, `arm64` | Most filterable property |
| `Type` | ~70% of apps | `msi`, `exe`, `zip`, `pkg` | Derivable from URI extension if absent |
| `Channel` | Browser-type apps | `Stable`, `Beta`, `Dev` | Edge, Chrome, Firefox |
| `Release` | Edge, Acrobat | `Enterprise`, `Consumer` | Coexists with Channel on Edge |
| `Ring` | OneDrive, Teams | `Production`, `Preview`, `Insider` | Semantically same as Channel |
| `Language` | Acrobat, Firefox | `English`, `English (UK)`, `de-DE` | Can be very long list |
| `Platform` | VS Code, some others | `Windows`, `win32-x64` | Occasionally redundant with Arch |
| `Track` | Some apps | `LTSC`, `Current` | Office, some Adobe |
| `Product` | Some apps | `Standard`, `Enterprise`, `Pro` | Acrobat variants |
| `Date` | ~50% of apps | `2026-03-08T08:24:00` | Display-only; not filterable |
| `Expiry` | Edge | `2027-03-06T18:22:00` | Display-only; not filterable |
| `SHA256` | Edge, some others | `8D91C95B...` | Display-only |
| `Size` | Edge | `183.91` (MB) | Display-only |
| `Hash` | Some apps | `9E7A29B4...` | Display-only |

### Property Classification

```
FILTERABLE (enumerate unique values → build filter controls):
  Tier 1 — Common, well-known:   Architecture, Type, Channel, Ring, Release, Language
  Tier 2 — Less common, generic: Platform, Track, Product, + any unrecognised property
                                  that is not display-only

DISPLAY-ONLY (show in grid, never filter):
  Version, URI, Date, Expiry, SHA256, Hash, Size
```

---

## Design Approach: Dynamic Runtime Filter Panel

### How it works

1. User selects an app and clicks **Get versions** → `Get-EvergreenApp` runs in a runspace
2. When results return, the code:
   a. Calls `$results[0].PSObject.Properties.Name` to get the property list
   b. Removes display-only properties from that list
   c. For each remaining property, calls `$results.$prop | Sort-Object -Unique` to get distinct values
   d. Builds a filter control for each property (see control types below)
3. Filter controls appear in a `WrapPanel` inside a `GroupBox "Filters"` — positioned between the
   app selector row and the versions `ListView`
4. As the user changes filter selections, the versions `ListView` `ItemsSource` is re-evaluated
   **client-side** (no re-query) — all filtering is `Where-Object` against the cached
   `$syncHash.CurrentAppResults` array

### Filter control type selection

| Unique value count | Control type | Rationale |
|---|---|---|
| 2–6 values | `CheckBox` strip (horizontal) | Architecture: ☑ x64 ☑ x86 ☐ arm64 |
| 7–20 values | Compact `ListBox` (multi-select, 4 rows visible) | Language list |
| 21+ values | `TextBox` (contains-match) | Free-text fallback for very long lists |
| Boolean-ish | `CheckBox` single | Properties with only True/False/Yes/No |

All CheckBox strips and ListBoxes default to **all values selected** (i.e. nothing is filtered
out until the user deselects something). This is the least-surprise default — the user sees
everything first and narrows down.

### Filter panel layout

```
┌─ Filters ──────────────────────────────────────────────────────────────────────┐
│                                                                                │
│  Architecture          Type              Channel          Release              │
│  ☑ x64  ☑ x86         ☑ msi  ☑ exe      ☑ Stable         ☑ Enterprise        │
│  ☑ arm64               ☐ zip             ☐ Beta            ☐ Consumer          │
│                                          ☐ Dev                                 │
│                                                                                │
│  Language                                                  [Clear all filters] │
│  ┌──────────────┐                                                              │
│  │☑ English     │                                                              │
│  │☑ English(UK) │                                                              │
│  │☐ German      │                                                              │
│  │☐ French      │                                                              │
│  └──────────────┘                                                              │
└────────────────────────────────────────────────────────────────────────────────┘
```

The `WrapPanel` flows left-to-right; each property group is a `StackPanel` with a header
`TextBlock` and the appropriate control below. The panel height is fixed at `Auto` (grows as
needed) with the `GridSplitter` available if the user wants to compress it.

---

## Implementation Detail

### Private helper: `Get-FilterableProperties`

```powershell
function Get-FilterableProperties {
    param([PSObject[]]$AppResults)

    # Properties that are never filterable
    $displayOnlyProps = @(
        'Version', 'URI', 'Date', 'Expiry',
        'SHA256', 'Hash', 'Size', 'Checksum'
    )

    if ($null -eq $AppResults -or $AppResults.Count -eq 0) { return @() }

    $AppResults[0].PSObject.Properties.Name |
        Where-Object { $_ -notin $displayOnlyProps } |
        ForEach-Object {
            $propName  = $_
            $allValues = $AppResults.$propName | Sort-Object -Unique
            [PSCustomObject]@{
                Name         = $propName
                UniqueValues = $allValues
                Count        = @($allValues).Count
                ControlType  = switch ($allValues.Count) {
                    { $_ -le 6  } { 'CheckBoxStrip' }
                    { $_ -le 20 } { 'MultiListBox'  }
                    default       { 'TextBox'        }
                }
            }
        }
}
```

### Private helper: `New-FilterPanel`

Accepts the output of `Get-FilterableProperties` and a parent `WrapPanel` reference. Builds and
injects the filter controls at runtime using the WPF object model (no XAML parsing at this stage —
controls are instantiated directly as `[System.Windows.Controls.*]` objects).

Each control registers a change handler that calls `Invoke-FilterUpdate`.

### Private helper: `Invoke-FilterUpdate`

Reads the current state of all filter controls from `$syncHash.FilterState` (a hashtable keyed by
property name, value is a `[System.Collections.Generic.HashSet[string]]` of selected values).
Applies a chained `Where-Object` against `$syncHash.CurrentAppResults` and updates the
`ListView.ItemsSource`.

```powershell
function Invoke-FilterUpdate {
    $filtered = $syncHash.CurrentAppResults

    foreach ($prop in $syncHash.FilterState.Keys) {
        $allowedValues = $syncHash.FilterState[$prop]
        if ($allowedValues.Count -eq 0) { continue }   # nothing selected = show all
        $filtered = $filtered | Where-Object {
            $allowedValues.Contains([string]$_.$prop)
        }
    }

    $syncHash.Window.Dispatcher.Invoke([action]{
        $syncHash.VersionsListView.ItemsSource = $filtered
    }, 'Normal')
}
```

### Friendly property name mapping

A lookup table provides display-friendly labels and optional grouping hints:

```powershell
$script:PropFriendlyNames = @{
    'Architecture' = 'Architecture'
    'Type'         = 'File type'
    'Channel'      = 'Channel'
    'Ring'         = 'Ring / Channel'
    'Release'      = 'Release'
    'Language'     = 'Language'
    'Platform'     = 'Platform'
    'Track'        = 'Track'
    'Product'      = 'Product variant'
}
# Any property not in this table gets displayed as-is (PascalCase preserved)
```

### Type column derivation fallback

If an app's results do not include a `Type` property but URI values are available, the UI
derives the extension from `[System.IO.Path]::GetExtension($_.URI).TrimStart('.')` and uses
that as a synthetic filterable property — labelled **File type (derived)** — so the user can
still filter by `msi`/`exe`/`zip` even when the app doesn't explicitly return a `Type` field.

---

## Where the Filter Panel Appears

### Download View (primary home)

Filter panel sits between the app selector row and the versions `ListView`. Filtering narrows
which rows are **visible** in the list, which in turn controls which rows can be checked for the
download queue. The **Select all** button only checks what is currently visible (post-filter),
not the full unfiltered set.

```
┌─ Download ──────────────────────────────────────────────────────────┐
│  Application: [MicrosoftEdge ▾]          [Get versions]             │
│                                                                      │
│  ┌─ Filters ────────────────────────────────────────────────────┐   │
│  │ Architecture        File type     Channel      Release        │   │
│  │ ☑ x64 ☑ x86        ☑ msi ☐ exe  ☑ Stable     ☑ Enterprise  │   │
│  │ ☐ arm64                           ☐ Beta       ☐ Consumer    │   │
│  │                                   ☐ Dev                      │   │
│  │                                          [Clear all filters]  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Versions (3 of 10 shown)           [☑ Select all visible] [Clear]  │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  ☑ │ Version       │ Channel │ Release    │ Architecture     │    │
│  │  ☑ │ 145.0.3800.97 │ Stable  │ Enterprise │ x64              │    │
│  │  ☑ │ 145.0.3800.97 │ Stable  │ Enterprise │ x86              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  [+ Add to queue]                                                    │
└──────────────────────────────────────────────────────────────────────┘
```

"3 of 10 shown" is a `TextBlock` updated by `Invoke-FilterUpdate` on every filter change.

### Apps View (secondary home)

The Apps view shows a read-only detail grid when a user clicks **Get latest version info** on
a selected app. The same filter panel appears above that detail grid so users can narrow the
results before deciding which specific variant to add to the download queue.

---

## Handling Edge Cases

| Scenario | Behaviour |
|---|---|
| App returns only `Version` + `URI` (no filterable properties) | Filter GroupBox is hidden (`Visibility = Collapsed`); versions list shows all rows |
| Single unique value for a property | Property is shown as a read-only label, not an interactive control (nothing to filter) |
| All values deselected for a property | Treated as "no filter applied for this property" — same as all selected. Prevents user accidentally filtering to zero results. |
| Filter results in zero rows | Empty list with `TextBlock` overlay: "No versions match the current filters. Try clearing some filters." |
| App uses `Ring` AND `Channel` | Both appear as separate filter groups with their own friendly names |
| Type not a property but derivable from URI | Synthetic **File type (derived)** filter created automatically |
| `Language` list has 50+ values | `TextBox` with real-time contains-match replaces the ListBox |

---

## AppParams Integration

Some apps support `-AppParams` on `Get-EvergreenApp` (e.g. `MozillaFirefox` for language
pre-selection, `GitHubRelease` for a custom repo URI). The Download view exposes this as an
optional collapsible **Advanced** section beneath the app selector:

```
┌─ Advanced (click to expand) ──────────────────────────────────────┐
│  AppParams (hashtable):  [Language = "en-GB", "en-US"           ] │
│  [?] These are passed directly to Get-EvergreenApp -AppParams.    │
│       See Evergreen docs for supported parameters per application.│
└───────────────────────────────────────────────────────────────────┘
```

The `TextBox` accepts a comma-separated `Key = Value` format. On **Get versions**, the UI
parses this into a `[hashtable]` and passes it as `-AppParams`. Parsing errors are surfaced in
the log panel with a clear message.

---

## Summary of Changes to Original Plan

| Section | Change |
|---|---|
| Download view layout | Add `GroupBox "Filters"` between app selector and versions ListView |
| Apps view detail grid | Add same filter panel above the detail grid |
| Private helpers | Add `Get-FilterableProperties`, `New-FilterPanel`, `Invoke-FilterUpdate` |
| `$syncHash` | Add `CurrentAppResults`, `FilterState`, `VersionsListView` references |
| Download view | **Select all** scoped to visible (filtered) rows only |
| Download view | "N of M shown" counter `TextBlock` |
| Download view | Optional collapsible **Advanced / AppParams** section |
| Phase 4 build order | Filter panel built before versions ListView is populated |
