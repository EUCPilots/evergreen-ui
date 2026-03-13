#Requires -Version 5.1
<#
.SYNOPSIS
    Builds WPF filter controls at runtime and injects them into the filter WrapPanel.

.DESCRIPTION
    Accepts the output of Get-FilterableProperties and a reference to the parent
    WrapPanel in the UI. For each filterable property it creates the appropriate
    WPF control (CheckBox strip, multi-select ListBox, or TextBox), wires up
    change handlers that call Invoke-FilterUpdate, and appends the group to the
    WrapPanel.

    All WPF controls are instantiated directly as .NET objects (no XAML parsing
    at this stage) so the function can run on the UI thread without needing a
    separate XamlReader call.

    The $syncHash.FilterState hashtable is (re-)initialised by this function
    with all values selected by default for each property.

.PARAMETER FilterProperties
    Output from Get-FilterableProperties — array of property metadata objects.

.PARAMETER WrapPanel
    The System.Windows.Controls.WrapPanel that hosts the filter groups.

.PARAMETER SyncHash
    Shared synchronised hashtable. FilterState key is written here.

.PARAMETER OnChangeCallback
    A scriptblock to invoke whenever a filter control value changes.
    Typically: { Invoke-FilterUpdate -SyncHash $syncHash }

.NOTES
    TODO: Implement WPF control construction in Phase 4.
#>
function New-FilterPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSObject[]]$FilterProperties,

        [Parameter(Mandatory)]
        [System.Windows.Controls.WrapPanel]$WrapPanel,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash,

        [Parameter(Mandatory)]
        [scriptblock]$OnChangeCallback
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Clear existing controls and reset filter state
    $WrapPanel.Children.Clear()
    $SyncHash.FilterState = @{}

    if ($FilterProperties.Count -eq 0) {
        $emptyText = [System.Windows.Controls.TextBlock]::new()
        $emptyText.Text = 'No filterable properties for this app result set.'
        $emptyText.Foreground = $SyncHash.Window.Resources['TextSecondaryBrush']
        $emptyText.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        [void]$WrapPanel.Children.Add($emptyText)
        return
    }

    foreach ($prop in $FilterProperties) {
        $propName     = [string]$prop.Name
        $displayName  = [string]$prop.DisplayName
        $controlType  = [string]$prop.ControlType
        $uniqueValues = [string[]]$prop.UniqueValues

        # Initialise filter state — all values selected
        $SyncHash.FilterState[$propName] = [System.Collections.Generic.HashSet[string]]::new(
            $uniqueValues,
            [System.StringComparer]::OrdinalIgnoreCase
        )

        $groupBorder = [System.Windows.Controls.Border]::new()
        $groupBorder.BorderThickness = [System.Windows.Thickness]::new(1)
        $groupBorder.BorderBrush = $SyncHash.Window.Resources['ControlBorderBrush']
        $groupBorder.Background = $SyncHash.Window.Resources['ControlBackgroundBrush']
        $groupBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $groupBorder.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
        $groupBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 10)
        $groupBorder.MinWidth = 200

        $groupPanel = [System.Windows.Controls.StackPanel]::new()

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $displayName
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
        $label.Foreground = $SyncHash.Window.Resources['TextPrimaryBrush']
        $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        [void]$groupPanel.Children.Add($label)

        switch ($controlType) {
            'CheckBoxStrip' {
                $strip = [System.Windows.Controls.WrapPanel]::new()

                foreach ($value in $uniqueValues) {
                    $valueText = [string]$value

                    $checkbox = [System.Windows.Controls.CheckBox]::new()
                    $checkbox.Content = $valueText
                    $checkbox.IsChecked = $true
                    $checkbox.Margin = [System.Windows.Thickness]::new(0, 0, 10, 6)
                    $checkbox.Style = $SyncHash.Window.Resources['FluentCheckBox']

                    $checkbox.add_Checked({
                        [void]$SyncHash.FilterState[$propName].Add($valueText)
                        & $OnChangeCallback
                    }.GetNewClosure())

                    $checkbox.add_Unchecked({
                        [void]$SyncHash.FilterState[$propName].Remove($valueText)
                        & $OnChangeCallback
                    }.GetNewClosure())

                    [void]$strip.Children.Add($checkbox)
                }

                [void]$groupPanel.Children.Add($strip)
            }

            'MultiListBox' {
                $listBox = [System.Windows.Controls.ListBox]::new()
                $listBox.SelectionMode = [System.Windows.Controls.SelectionMode]::Multiple
                $listBox.MinWidth = 220
                $listBox.MaxHeight = 120
                $listBox.BorderBrush = $SyncHash.Window.Resources['ControlBorderBrush']
                $listBox.Background = $SyncHash.Window.Resources['ControlBackgroundBrush']
                $listBox.Foreground = $SyncHash.Window.Resources['TextPrimaryBrush']

                foreach ($value in $uniqueValues) {
                    [void]$listBox.Items.Add([string]$value)
                }

                foreach ($item in $listBox.Items) {
                    [void]$listBox.SelectedItems.Add($item)
                }

                $listBox.add_SelectionChanged({
                    $selected = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                    foreach ($item in $listBox.SelectedItems) {
                        [void]$selected.Add([string]$item)
                    }
                    $SyncHash.FilterState[$propName] = $selected
                    & $OnChangeCallback
                }.GetNewClosure())

                [void]$groupPanel.Children.Add($listBox)
            }

            default {
                $textBox = [System.Windows.Controls.TextBox]::new()
                $textBox.MinWidth = 220
                $textBox.ToolTip = 'Type to filter values (contains match). Leave blank to include all values.'
                $textBox.Style = $SyncHash.Window.Resources['FluentTextBox']

                $allValues = [string[]]$uniqueValues

                $textBox.add_TextChanged({
                    $needle = $textBox.Text

                    $selected = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )

                    foreach ($candidate in $allValues) {
                        if ([string]::IsNullOrWhiteSpace($needle) -or
                            $candidate.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            [void]$selected.Add($candidate)
                        }
                    }

                    $SyncHash.FilterState[$propName] = $selected
                    & $OnChangeCallback
                }.GetNewClosure())

                [void]$groupPanel.Children.Add($textBox)
            }
        }

        $groupBorder.Child = $groupPanel
        [void]$WrapPanel.Children.Add($groupBorder)
    }
}
