Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchArtifactList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$RebuildFilters,

        [System.Collections.IDictionary]$PreservedFilters = @{},

        [AllowEmptyCollection()]
        [object[]]$FilterMetadata
    )

    if ($RebuildFilters) {
        Invoke-EwWorkbenchArtifactColumn -State $State
        $State.AllowFilterEvents = $false
        $State.ArtifactFiltersPanel.Children.Clear()
        $State.ArtifactFilterControls = @{}
        try {
            if ($State.AllArtifacts.Count -gt 0) {
                $metadata = if ($PSBoundParameters.ContainsKey('FilterMetadata')) {
                    @($FilterMetadata)
                } else {
                    @(Get-EwFilterableProperty -Artifact $State.AllArtifacts)
                }
                foreach ($filter in $metadata) {
                    $group = [System.Windows.Controls.StackPanel]::new()
                    $group.Margin = [System.Windows.Thickness]::new(0, 0, 10, 6)
                    $label = [System.Windows.Controls.Label]::new()
                    $label.Content = $filter.DisplayName
                    $label.Padding = [System.Windows.Thickness]::new(0)
                    $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
                    $null = $group.Children.Add($label)

                    # A read-only editable ComboBox shows a summary while its drop-down hosts value check boxes.
                    $control = [System.Windows.Controls.ComboBox]::new()
                    $label.Target = $control
                    $control.MinWidth = 120
                    $control.IsEditable = $true
                    $control.IsReadOnly = $true
                    $control.IsTextSearchEnabled = $false
                    $control.Tag = $filter.Name
                    $control.ToolTip = "Filter artifacts by $($filter.DisplayName); select one or more values"
                    [System.Windows.Automation.AutomationProperties]::SetName(
                        $control,
                        "$($filter.DisplayName) filter"
                    )
                    $checkBoxes = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()
                    $preserved = @()
                    if ($PreservedFilters.Contains($filter.Name)) {
                        $preserved = @($PreservedFilters[$filter.Name] | ForEach-Object { [string]$_ })
                    }
                    foreach ($value in $filter.UniqueValues) {
                        $checkBox = [System.Windows.Controls.CheckBox]::new()
                        $checkBox.Content = [string]$value
                        $checkBox.Tag = [string]$value
                        $checkBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
                        $checkBox.IsChecked = [string]$value -in $preserved
                        $refreshFilter = {
                            if ($State.AllowFilterEvents) {
                                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                            }
                        }.GetNewClosure()
                        $checkBox.Add_Checked($refreshFilter)
                        $checkBox.Add_Unchecked($refreshFilter)
                        $checkBoxes.Add($checkBox)
                        $null = $control.Items.Add($checkBox)
                    }
                    if ($preserved.Count -gt 0) {
                        $offered = @($checkBoxes | ForEach-Object { [string]$_.Tag })
                        $missing = @($preserved | Where-Object { $_ -notin $offered })
                        if ($missing.Count -gt 0) {
                            $quoted = ($missing | ForEach-Object { "'$_'" }) -join ', '
                            $outcome = if ($missing.Count -eq $preserved.Count) { 'reset to All' } else { 'removed from the selection' }
                            Write-EwWorkbenchLog -State $State -Message "Filter '$($filter.DisplayName)' value $quoted is no longer supported; $outcome." -Level Warning
                        }
                    }
                    $control.Add_SelectionChanged({
                        param($eventSource, $selectionArgs)
                        # Keyboard selection of a drop-down row toggles its check box instead of selecting it.
                        $selected = $eventSource.SelectedItem
                        if ($selected -isnot [System.Windows.Controls.CheckBox]) {
                            return
                        }
                        $selected.IsChecked = -not [bool]$selected.IsChecked
                        $eventSource.SelectedIndex = -1
                        $selectionArgs.Handled = $true
                        if ($State.AllowFilterEvents) {
                            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                        }
                    }.GetNewClosure())
                    $null = $group.Children.Add($control)
                    $null = $State.ArtifactFiltersPanel.Children.Add($group)
                    $State.ArtifactFilterControls[$filter.Name] = @{ Control = $control; CheckBoxes = $checkBoxes }
                }
            }
            foreach ($oldName in $PreservedFilters.Keys) {
                if (-not $State.ArtifactFilterControls.ContainsKey($oldName)) {
                    Write-EwWorkbenchLog -State $State -Message "Filter '$oldName' is no longer supported; reset to All." -Level Warning
                }
            }
        }
        finally {
            $State.AllowFilterEvents = $true
        }
    }

    $getArtifactValue = {
        param(
            [AllowNull()]
            [object]$Artifact,

            [Parameter(Mandatory)]
            [string]$PropertyName
        )
        if ($null -eq $Artifact) {
            return ''
        }
        if ($PropertyName -eq '_DerivedType') {
            $uriProperty = $Artifact.PSObject.Properties['URI']
            if ($null -eq $uriProperty) {
                return ''
            }
            return [System.IO.Path]::GetExtension([string]$uriProperty.Value).TrimStart('.').ToLowerInvariant()
        }
        $property = $Artifact.PSObject.Properties[$PropertyName]
        if ($null -eq $property) {
            return ''
        }
        return [string]$property.Value
    }.GetNewClosure()

    $filtered = @($State.AllArtifacts)
    foreach ($propertyName in $State.ArtifactFilterControls.Keys) {
        $filterState = $State.ArtifactFilterControls[$propertyName]
        $selectedValues = @($filterState.CheckBoxes | Where-Object { [bool]$_.IsChecked } | ForEach-Object { [string]$_.Tag })
        $filterState.Control.Text = switch ($selectedValues.Count) {
            0 { 'All' }
            1 { $selectedValues[0] }
            default { "$($selectedValues.Count) selected" }
        }
        if ($selectedValues.Count -gt 0) {
            $allowed = [System.Collections.Generic.HashSet[string]]::new([string[]]$selectedValues, [System.StringComparer]::OrdinalIgnoreCase)
            $filtered = @($filtered | Where-Object {
                $allowed.Contains([string](& $getArtifactValue -Artifact $_ -PropertyName $propertyName))
            })
        }
    }

    $State.ArtifactsGrid.ItemsSource = [object[]]$filtered
    $State.ArtifactCountLabel.Text = "Showing $($filtered.Count) of $($State.AllArtifacts.Count) artifacts"
    if ($State.AppsDisplayStale) { $State.ArtifactCountLabel.Text = "STALE: $($State.ArtifactCountLabel.Text)" }
    Show-EwWorkbenchDownloadTray -State $State
}
