# Plan: XAML and UI Component Fixes

Address the issues identified in the EvergreenUI XAML and PowerShell UI-handler review.
Work through each priority tier in order. Do not refactor beyond the stated scope.

## High priority

### 1. Missing AutomationProperties.Name on interactive controls

Add `AutomationProperties.Name` to every interactive control that lacks one.
Focus first on controls that have no visible text label: icon-only buttons, status-dot Ellipses, PasswordBox, and every ToggleButton.

Affected controls (non-exhaustive):

- `NavToggleButton` - hamburger icon button
- `CopyLogButton`, `SaveLogButton`, `LogToggleButton`
- All eight status-dot Ellipses: `EvergreenStatusDot`, `IntuneConnectionStatusDot`, `NerdioImportAuthStatusDot`, `M365IntuneAuthStatusDot`, `M365NerdioAuthStatusDot`, `ImportAuthStatusDot`, `NerdioApiAuthStatusDot`, `NerdioAzureAuthStatusDot`, `InstallElevationStatusDot`
- `NmeClientSecretBox` (PasswordBox)
- `ShowImportTabCheckBox`, `ShowInstallTabCheckBox` (ToggleButtons)
- All eight nav RadioButtons

### 2. NerdioImportNewButton - unimplemented feature visible in UI

`NerdioImportNewButton` is enabled but its handler only logs "not implemented yet".
Set `IsEnabled="False"` on the button in XAML and add a ToolTip explaining the feature is planned.
Do not remove the button or its handler.

### 3. ListView column overflow and missing TextTrimming

All GridViewColumn cells that use DisplayMemberBinding render plain TextBlocks with no TextTrimming.
Long values (URIs, file paths) are clipped without an ellipsis or hover tooltip.

For each ListView, replace DisplayMemberBinding columns whose content can be long with a CellTemplate containing:

- `TextBlock TextTrimming="CharacterEllipsis"`
- `ToolTip="{Binding <property>}"` so the full value is accessible on hover

Affected columns:

- `VersionsListView`: Uri (460px)
- `DownloadQueueListView`: URI (530px)
- `LibraryContentsListView`: Path (750px)
- `NerdioDefinitionsListView`: App, Shell App, Status columns

For any column that is a fixed width shorter than typical content for that field, also add trimming.

## Medium priority

### 4. Control naming - AppsComboBox declared as ListBox

`AppsComboBox` is a `ListBox` element (XAML line 995).
Rename the `x:Name` to `AppsListBox` in XAML.
Update every reference in `Start-EvergreenWorkbench.ps1` from `AppsComboBox` to `AppsListBox`
(FindName call, syncHash key, and all subsequent usages of the variable).

### 5. Control naming - ShowImportTabCheckBox / ShowInstallTabCheckBox

Both controls are `ToggleButton` elements.
Rename in XAML and all PowerShell references:

- `ShowImportTabCheckBox` -> `ShowImportTabToggle`
- `ShowInstallTabCheckBox` -> `ShowInstallTabToggle`

### 6. LibraryDetailsListView - empty GridView

The XAML declares `<GridView/>` with no columns (line ~1451).
Add the stable columns statically in XAML: App (Version), Architecture, Type, URI.
Keep the code-behind path that replaces the GridView columns dynamically when the app returns
properties that differ from the static defaults, but the fallback should be the XAML columns
rather than an empty view.

### 7. Add ToolTips to unlabelled buttons

Add `ToolTip` to:

- `NavToggleButton`: "Collapse/expand navigation"
- `CopyLogButton`: "Copy log to clipboard"
- `SaveLogButton`: "Save log to file"

The `LogToggleButton` already has a text label ("Show progress log") so no separate ToolTip is needed.

### 8. Date column binding StringFormat

`VersionsListView` Date column (line 1226):

```xml
DisplayMemberBinding="{Binding Date}"
```

Change to:

```xml
DisplayMemberBinding="{Binding Date, StringFormat='{}{0:yyyy-MM-dd}'}"
```

Only apply this if the Date property is a DateTime. Confirm in `Get-EvergreenAppList.ps1`
whether `Date` is already a pre-formatted string; if so, leave the binding as-is.

## Low priority

### 9. StartupViewComboBox default selection

Set `SelectedIndex="0"` on `StartupViewComboBox` in XAML as a safe default
(aligned with `NavApps.IsChecked="True"`).

### 10. catch {} blocks missing Write-Verbose

In `Start-EvergreenWorkbench.ps1`, add `Write-Verbose -Message "EvergreenUI: $_"` inside the
best-effort catch blocks that currently have the justifying comment but no verbose output:
- Line ~104: icon load failure
- Line ~198: about panel metadata

### 11. Browse button naming consistency

Standardise all browse button names to the `Browse*Button` prefix pattern.
The following currently use the suffix pattern and should be renamed in both XAML and PS references:
- `LibraryBrowseButton` -> `BrowseLibraryButton`
- `NerdioBrowseDefinitionsButton` -> `BrowseNerdioDefinitionsButton`
- `IntuneBrowseDefinitionsButton` -> `BrowseIntuneDefinitionsButton`
- `M365BrowseConfigButton` -> `BrowseM365ConfigButton`

Check all PS wiring after rename.

### 12. GridSplitter minimum grab size

The GridSplitter between main content and the log panel is 5px (line 3467).
Increase to `Height="8"` to improve usability at high DPI and on touch displays.

## Out of scope for this plan

- Theme brush values (all initialised to Transparent by design; populated at runtime by Set-*Theme functions)
- Nav rail fixed column width (180px) - layout is intentional; DPI scaling handled by WPF
- M365EvergreenVersionLabel defaulting to "-" - runtime-populated placeholder, not a defect
- EvergreenVersionText "checking..." - same pattern, runtime-populated
- Runspace threading race conditions on DownloadQueue - separate investigation needed
