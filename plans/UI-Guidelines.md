# Evergreen Workbench - UI Guidelines

> Reference for anyone adding or modifying UI elements. All standards here are derived from `EvergreenUI/Resources/EvergreenUI.xaml` and the theme files in `EvergreenUI/Private/themes/`.

---

## 1. Design Foundation

The Workbench follows **Microsoft Fluent Design** principles adapted for a desktop WPF application:

- **Rounded corners** on all interactive controls (4 px standard)
- **Layered depth** via border colours and subtle background fills rather than shadows
- **Accent-first interaction** - hover and selection states use the brand accent colour
- **Dynamic theming** - every colour is a named `DynamicResource` brush; no hardcoded hex values in XAML or PowerShell
- **Segoe UI** is the sole font family, matching Windows system UI

---

## 2. Colour Palette

All colours are referenced by brush name only. Never use hardcoded colour values. The actual RGB values are applied at runtime by `Set-LightTheme.ps1` / `Set-DarkTheme.ps1`.

### 2.1 Brush Reference

| Brush Name | Light (#hex) | Dark (#hex) | Purpose |
|---|---|---|---|
| `WindowBackgroundBrush` | `#F3F4F4` | `#141D1C` | Window, panel, and page backgrounds |
| `ControlBackgroundBrush` | `#FFFFFF` | `#1C2826` | Input fields, list backgrounds, card surfaces |
| `ControlBorderBrush` | `#DDE2E1` | `#2E3F3C` | Borders, dividers, grid-splitter |
| `TextPrimaryBrush` | `#1A1A1A` | `#E8F2F0` | All primary body and label text |
| `TextSecondaryBrush` | `#4D5A58` | `#90AAA7` | Hints, captions, column headers, placeholder text |
| `AccentBrush` | `#009485` | `#4DB8AD` | Primary buttons, selected state, focus borders, active nav |
| `AccentHoverBrush` | `#01786C` | `#67B9C9` | Hover state on accent-coloured elements |
| `AccentLightBrush` | `#D9F2EF` | `#0D2926` | Hover/selection fill on list items, checkbox background |
| `ButtonForegroundBrush` | `#FFFFFF` | `#000000` | Text on primary (accent) buttons |
| `SecondaryButtonBackgroundBrush` | `#E4E8E7` | `#2D4440` | Secondary button backgrounds |
| `SecondaryButtonBorderBrush` | `#9AADAA` | `#5A7B77` | Secondary button borders |
| `StatusPositiveBrush` | `#256E49` | `#89C2A0` | Success indicators, status dots |
| `StatusErrorBrush` | `#A64040` | `#D28484` | Error indicators, validation failures |
| `ToggleThumbBrush` | `#FFFFFF` | `#000000` | Toggle/switch thumb fill |

### 2.2 Rules

- Use `DynamicResource` for XAML bindings: `Background="{DynamicResource AccentBrush}"`
- Use `SetResourceReference()` for runtime-constructed controls:
  ```powershell
  $ctrl.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'ControlBackgroundBrush')
  ```
- Never call `SetValue()` with a hardcoded `SolidColorBrush` for any colour that has a named brush.

---

## 3. Typography

**Font family:** Segoe UI (set globally on the Window - do not override per-control)

| Usage | Size | Weight |
|---|---|---|
| Window/page title (title bar) | 16 px | SemiBold |
| Panel section header | 20 px | SemiBold |
| Tab item label | 13 px | Regular / SemiBold when selected |
| Navigation rail item | 13 px | Regular |
| Body / control content | 13 px (window default) | Regular |
| Column header | 11 px | SemiBold |
| Status bar / log text | 11–12 px | Regular |
| Log console output | 12 px | Regular (Consolas) |

**Rules**

- Section headers use `FontSize=20` and `FontWeight=SemiBold` with `Foreground={DynamicResource TextPrimaryBrush}`.
- Secondary descriptive text uses `Foreground={DynamicResource TextSecondaryBrush}`.
- Never set `FontFamily` explicitly - inherit the window default.

---

## 4. Spacing & Layout

### 4.1 Window Structure

The root grid has 4 rows and 2 columns:

| Region | Size | Notes |
|---|---|---|
| Title bar (row 0) | 48 px height | `AccentBrush` background |
| Main content (row 1) | `*`, min 200 px | Columns: nav rail 140 px + content `*` |
| GridSplitter (row 2) | 5 px height | `ControlBorderBrush` background, `SizeNS` cursor |
| Status / log (row 3) | 175 px, min 40 px | Resizable via splitter |

### 4.2 Content Panel Margins

All content panels use the same outer margin:

```
Margin="22,18,22,12"
```

(22 px left/right, 18 px top, 12 px bottom)

### 4.3 Standard Spacing Values

| Context | Value |
|---|---|
| Between sibling buttons in a row | 6 px right margin |
| Below a section header / divider | 12 px |
| Below a label before its control | 6 px |
| Between stacked form rows | 12–14 px |
| Filter group card: outer margin | `0,0,10,10` |
| Filter group card: inner padding | `10,8,10,10` |
| Navigation rail items: outer margin | `4,1` |
| Tab items: right margin between tabs | `0,0,4,0` |

### 4.4 Horizontal Dividers

Use a `Rectangle` with `Height=1` and `Fill={DynamicResource ControlBorderBrush}` as a section divider beneath panel headers and tab header rows.

---

## 5. Named Styles

All controls must use the appropriate named style from `Window.Resources`. Never apply ad-hoc inline styles to replicate what a named style already provides.

### 5.1 FluentButton (primary action)

```xml
<Button Style="{StaticResource FluentButton}" Content="Load versions"/>
```

| Property | Value |
|---|---|
| Background | `AccentBrush` |
| Foreground | `ButtonForegroundBrush` |
| BorderThickness | 0 |
| Padding | 16, 6 |
| CornerRadius | 4 |
| Cursor | Hand |
| Hover opacity | 0.82 |
| Pressed opacity | 0.65 |
| Disabled opacity | 0.4 |

### 5.2 FluentSecondaryButton (non-destructive secondary action)

```xml
<Button Style="{StaticResource FluentSecondaryButton}" Content="Browse…"/>
```

Based on `FluentButton` with:

| Property | Value |
|---|---|
| Background | `SecondaryButtonBackgroundBrush` |
| Foreground | `TextPrimaryBrush` |
| BorderThickness | 1 |
| BorderBrush | `SecondaryButtonBorderBrush` |

### 5.3 FluentTextBox (single-line text input)

```xml
<TextBox Style="{StaticResource FluentTextBox}" MinWidth="220"/>
```

| Property | Value |
|---|---|
| Background | `ControlBackgroundBrush` |
| Foreground | `TextPrimaryBrush` |
| BorderBrush | `ControlBorderBrush` |
| BorderThickness | 1 (normal) → 1.5 (focused) |
| Padding | 8, 0 |
| MinHeight | 32 |
| CornerRadius | 4 |
| VerticalContentAlignment | Center |
| Hover border | `AccentHoverBrush` |
| Focus border | `AccentBrush` |
| Disabled opacity | 0.5 |

### 5.4 FluentPasswordBox

Identical sizing and behaviour to `FluentTextBox`. Focus border thickness increases to 2.

### 5.5 FluentComboBox (dropdown select)

```xml
<ComboBox Style="{StaticResource FluentComboBox}" Height="32" MinWidth="220"/>
```

| Property | Value |
|---|---|
| Background | `ControlBackgroundBrush` |
| Foreground | `TextPrimaryBrush` |
| BorderBrush | `ControlBorderBrush` |
| BorderThickness | 1 |
| Padding | 8, 0 |
| Height | **32 px** (always set explicitly) |
| CornerRadius | 4 |
| Dropdown popup CornerRadius | 0, 0, 4, 4 |
| Item padding | 8, 6 |
| Selected / highlighted item | Background `AccentLightBrush`, Foreground `AccentBrush` |

> **Always set `Height="32"`** when declaring a ComboBox in XAML, or `$comboBox.Height = 32` in PowerShell. The style does not enforce a fixed height.

Runtime construction:

```powershell
$comboBox = [System.Windows.Controls.ComboBox]::new()
$comboBox.MinWidth = 220
$comboBox.Height   = 32
$comboBox.Style    = $SyncHash.Window.Resources['FluentComboBox']
```

### 5.6 FluentCheckBox

```xml
<CheckBox Style="{StaticResource FluentCheckBox}" Content="Include pre-release"/>
```

| Property | Value |
|---|---|
| Foreground | `TextPrimaryBrush` |
| Height | **32 px** (matches ComboBox / TextBox height) |
| VerticalContentAlignment | Center |
| Cursor | Hand |
| Box size | 14 × 14 px (centred vertically within 32 px) |
| Box CornerRadius | 2 |
| Checked background | `AccentLightBrush` |
| Checked border | `AccentBrush` |
| Check mark | SVG path `M 1.5 7 L 5 10.5 L 12 3`, stroke `AccentBrush`, thickness 1.5 |
| Margin (in strips) | `0,0,10,6` |

### 5.7 FluentListView

```xml
<ListView Style="{StaticResource FluentListView}">
    <ListView.View>
        <GridView>
            <GridViewColumn Header="Name" Width="200"/>
        </GridView>
    </ListView.View>
</ListView>
```

| Property | Value |
|---|---|
| Background | `ControlBackgroundBrush` |
| BorderThickness | 0 |
| ListViewItem MinHeight | 32 |
| ListViewItem Padding | 0 |
| Hover | Background `AccentLightBrush` |
| Selected | Background `AccentLightBrush`, Foreground `AccentBrush`, FontWeight SemiBold |
| Column header FontSize | 11 px |
| Column header FontWeight | SemiBold |
| Column header Foreground | `TextSecondaryBrush` |

### 5.8 FluentTabControl / FluentTabItem

```xml
<TabControl Style="{StaticResource FluentTabControl}">
    <TabItem Style="{StaticResource FluentTabItem}" Header="General"/>
</TabControl>
```

| Property | Value |
|---|---|
| TabItem MinWidth | 160 |
| TabItem MinHeight | 44 |
| TabItem padding | 16, 10 |
| Tab FontSize | 13 px |
| Unselected Foreground | `TextSecondaryBrush` |
| Selected Foreground | `AccentBrush` |
| Selected FontWeight | SemiBold |
| Selection indicator | 2 px underline, CornerRadius 1, fill `AccentBrush` |
| Hover background | `AccentLightBrush` |

### 5.9 NavRailRadioButton

Used exclusively for the left navigation rail. Do not use for other purposes.

```xml
<RadioButton Style="{StaticResource NavRailRadioButton}"
             GroupName="Navigation" Content="Apps"/>
```

| Property | Value |
|---|---|
| Padding | 14, 10 |
| FontSize | 13 px |
| Cursor | Hand |
| GroupName | `"Navigation"` |
| Unselected background | Transparent |
| Selected background | `AccentLightBrush` |
| Selected foreground | `AccentBrush` |
| Selection indicator | 3 px left bar, fill `AccentBrush`, CornerRadius 2 |

### 5.10 StatusDot

```xml
<Ellipse Style="{StaticResource StatusDot}" Fill="{DynamicResource StatusPositiveBrush}"/>
```

| Property | Value |
|---|---|
| Width / Height | 8 px |
| VerticalAlignment | Center |
| Margin | `0,0,5,0` |
| Positive state | `StatusPositiveBrush` |
| Error state | `StatusErrorBrush` |

---

## 6. Control Sizing Reference

| Control | Standard Height | Notes |
|---|---|---|
| TextBox / PasswordBox | 32 px (MinHeight) | Set via style |
| ComboBox | **32 px** | Must be set explicitly |
| CheckBox | **32 px** | Set via style; 14×14 box centred within |
| Button (primary/secondary) | Auto (Padding 6 top/bottom) | Height flows from content + padding |
| ListViewItem | 32 px (MinHeight) | Set via style |
| TabItem | 44 px (MinHeight) | Set via style |
| Title bar | 48 px | Fixed row height |
| Status bar | 40 px | Fixed height |

---

## 7. Border and Card Containers

When grouping related controls (e.g., filter cards, settings sections):

```powershell
$border = [System.Windows.Controls.Border]::new()
$border.BorderThickness = [System.Windows.Thickness]::new(1)
$border.CornerRadius    = [System.Windows.CornerRadius]::new(4)
$border.Margin          = [System.Windows.Thickness]::new(0, 0, 10, 10)
$border.Padding         = [System.Windows.Thickness]::new(10, 8, 10, 10)
$border.MinWidth        = 200
$border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'ControlBorderBrush')
$border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty,  'ControlBackgroundBrush')
```

Standard label inside a card:

```powershell
$label = [System.Windows.Controls.TextBlock]::new()
$label.FontWeight = [System.Windows.FontWeights]::SemiBold
$label.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 6)
$label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextPrimaryBrush')
```

---

## 8. Runtime Control Construction Rules

When building controls programmatically in PowerShell:

1. **Always reference styles via `$SyncHash.Window.Resources['StyleName']`** - styles are only accessible after the Window is loaded.
2. **Always use `SetResourceReference()` for colour/brush properties** - never assign a `SolidColorBrush` directly.
3. **Match explicit sizes**: ComboBox height = 32, CheckBox height = 32, ListBox MinWidth = 220, TextBox MinWidth = 220.
4. **Wire `GetNewClosure()`** on all event handlers that close over loop variables:
   ```powershell
   $checkbox.add_Checked({
       [void]$SyncHash.FilterState[$propName].Add($valueText)
       & $OnChangeCallback
   }.GetNewClosure())
   ```
5. **Initialise state before rendering** - populate `FilterState` (or equivalent) before creating controls so the initial UI reflects the correct defaults.

---

## 9. Icons and Graphics

All icons are inline SVG `Path` elements - no external image files are used for controls.

| Element | Path Data | Stroke | Notes |
|---|---|---|---|
| Checkbox check mark | `M 1.5 7 L 5 10.5 L 12 3` | `AccentBrush`, 1.5 px | Visibility toggled on state |
| ComboBox dropdown arrow | `M 0 0 L 4 4 L 8 0` | `TextSecondaryBrush` | Inside toggle button |

For new icons:

- Use `Path` with `Stroke` (not `Fill`) for line-style icons
- Reference `TextPrimaryBrush` or `TextSecondaryBrush` for neutral icons; `AccentBrush` for active/branded icons
- Keep paths within a 16 × 16 or 20 × 20 viewbox

Status indicators use `Ellipse` (see `StatusDot` style) - not icons.

---

## 10. Interaction States Summary

| State | Background | Foreground / Border |
|---|---|---|
| Default (input) | `ControlBackgroundBrush` | Border `ControlBorderBrush` |
| Hover (input) | - | Border `AccentHoverBrush` |
| Focus (input) | - | Border `AccentBrush`, thickness +0.5 |
| Disabled | - | Opacity 0.4–0.5 |
| List item hover | `AccentLightBrush` | - |
| List item selected | `AccentLightBrush` | Foreground `AccentBrush`, SemiBold |
| Button hover | - | Opacity 0.82 |
| Button pressed | - | Opacity 0.65 |
| Nav selected | `AccentLightBrush` | Foreground `AccentBrush` + left accent bar |
| Tab selected | - | Foreground `AccentBrush`, underline `AccentBrush` |

---

## 11. Key Source Files

| File | Purpose |
|---|---|
| `EvergreenUI/Resources/EvergreenUI.xaml` | All named styles, brush declarations, window XAML |
| `EvergreenUI/Private/themes/Set-LightTheme.ps1` | Applies light-mode colour values to brushes |
| `EvergreenUI/Private/themes/Set-DarkTheme.ps1` | Applies dark-mode colour values to brushes |
| `EvergreenUI/Private/New-FilterPanel.ps1` | Reference implementation for runtime control construction |
| `EvergreenUI/Public/Start-EvergreenWorkbench.ps1` | Main code-behind; all named control references |
