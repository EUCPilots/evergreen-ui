Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchArtifactList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$RebuildFilters
    )

    if ($RebuildFilters) {
        $State.AllowFilterEvents = $false
        $State.ArtifactFiltersPanel.Children.Clear()
        $State.ArtifactFilterControls = @{}
        try {
            if ($State.AllArtifacts.Count -gt 0) {
                foreach ($filter in @(Get-EwFilterableProperty -Artifact $State.AllArtifacts)) {
                    $group = [System.Windows.Controls.StackPanel]::new()
                    $group.Margin = [System.Windows.Thickness]::new(0, 0, 10, 6)
                    $label = [System.Windows.Controls.TextBlock]::new()
                    $label.Text = $filter.DisplayName
                    $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
                    $null = $group.Children.Add($label)

                    $filterState = @{
                        Control = $null
                        Type = [string]$filter.ControlType
                        Values = [string[]]$filter.UniqueValues
                    }
                    switch ($filterState.Type) {
                        'CheckBoxStrip' {
                            $control = [System.Windows.Controls.WrapPanel]::new()
                            $valueControls = foreach ($value in $filter.UniqueValues) {
                                $checkBox = [System.Windows.Controls.CheckBox]::new()
                                $checkBox.Content = [string]$value
                                $checkBox.Tag = [string]$value
                                $checkBox.IsChecked = $true
                                $checkBox.Margin = [System.Windows.Thickness]::new(0, 0, 10, 4)
                                [System.Windows.Automation.AutomationProperties]::SetName(
                                    $checkBox,
                                    "$($filter.DisplayName): $value"
                                )
                                $checkBox.Add_Checked({
                                    if ($State.AllowFilterEvents) {
                                        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                                    }
                                }.GetNewClosure())
                                $checkBox.Add_Unchecked({
                                    if ($State.AllowFilterEvents) {
                                        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                                    }
                                }.GetNewClosure())
                                $null = $control.Children.Add($checkBox)
                                $checkBox
                            }
                            $filterState.ValueControls = @($valueControls)
                            $filterState.Control = $control
                        }
                        'MultiListBox' {
                            $control = [System.Windows.Controls.ListBox]::new()
                            $control.SelectionMode = [System.Windows.Controls.SelectionMode]::Multiple
                            $control.MinWidth = 160
                            $control.MaxHeight = 120
                            foreach ($value in $filter.UniqueValues) {
                                $null = $control.Items.Add([string]$value)
                            }
                            foreach ($item in $control.Items) {
                                $null = $control.SelectedItems.Add($item)
                            }
                            [System.Windows.Automation.AutomationProperties]::SetName(
                                $control,
                                "$($filter.DisplayName) filter"
                            )
                            $control.Add_SelectionChanged({
                                if ($State.AllowFilterEvents) {
                                    & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                                }
                            }.GetNewClosure())
                            $filterState.Control = $control
                        }
                        'TextBox' {
                            $control = [System.Windows.Controls.TextBox]::new()
                            $control.MinWidth = 160
                            $control.ToolTip = "Filter artifacts by $($filter.DisplayName)"
                            [System.Windows.Automation.AutomationProperties]::SetName(
                                $control,
                                "$($filter.DisplayName) filter"
                            )
                            $control.Add_TextChanged({
                                if ($State.AllowFilterEvents) {
                                    & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                                }
                            }.GetNewClosure())
                            $filterState.Control = $control
                        }
                        default {
                            $control = [System.Windows.Controls.ComboBox]::new()
                            $control.MinWidth = 120
                            $control.Tag = $filter.Name
                            $control.ToolTip = "Filter artifacts by $($filter.DisplayName)"
                            [System.Windows.Automation.AutomationProperties]::SetName(
                                $control,
                                "$($filter.DisplayName) filter"
                            )
                            $null = $control.Items.Add('All')
                            foreach ($value in $filter.UniqueValues) {
                                $null = $control.Items.Add([string]$value)
                            }
                            $control.SelectedIndex = 0
                            $control.Add_SelectionChanged({
                                if ($State.AllowFilterEvents) {
                                    & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                                }
                            }.GetNewClosure())
                            $filterState.Control = $control
                        }
                    }
                    $null = $group.Children.Add($filterState.Control)
                    $null = $State.ArtifactFiltersPanel.Children.Add($group)
                    $State.ArtifactFilterControls[$filter.Name] = $filterState
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
        switch ($filterState.Type) {
            'CheckBoxStrip' {
                $selectedValues = @($filterState.ValueControls | Where-Object IsChecked | ForEach-Object { [string]$_.Tag })
                if ($selectedValues.Count -eq 0) {
                    $filtered = @()
                }
                elseif ($selectedValues.Count -lt $filterState.Values.Count) {
                    $filtered = @($filtered | Where-Object {
                        $value = & $getArtifactValue -Artifact $_ -PropertyName $propertyName
                        $selectedValues -contains $value
                    })
                }
            }
            'MultiListBox' {
                $selectedValues = @($filterState.Control.SelectedItems | ForEach-Object { [string]$_ })
                if ($selectedValues.Count -eq 0) {
                    $filtered = @()
                }
                elseif ($selectedValues.Count -lt $filterState.Values.Count) {
                    $filtered = @($filtered | Where-Object {
                        $value = & $getArtifactValue -Artifact $_ -PropertyName $propertyName
                        $selectedValues -contains $value
                    })
                }
            }
            'TextBox' {
                $searchText = [string]$filterState.Control.Text
                if (-not [string]::IsNullOrWhiteSpace($searchText)) {
                    $filtered = @($filtered | Where-Object {
                        $property = $_.PSObject.Properties[$propertyName]
                        $null -ne $property -and
                        ([string]$property.Value).IndexOf($searchText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    })
                }
            }
            default {
                $selectedValue = [string]$filterState.Control.SelectedItem
                if (-not [string]::IsNullOrWhiteSpace($selectedValue) -and $selectedValue -ne 'All') {
                    $filtered = @($filtered | Where-Object {
                        (& $getArtifactValue -Artifact $_ -PropertyName $propertyName) -eq $selectedValue
                    })
                }
            }
        }
    }

    $State.ArtifactsGrid.ItemsSource = [object[]]$filtered
    $State.ArtifactCountLabel.Text = "Showing $($filtered.Count) of $($State.AllArtifacts.Count) artifacts"
    $State.QueueDownloadButton.IsEnabled = $State.ArtifactsGrid.SelectedItems.Count -gt 0 -and $null -eq $State.ActiveJobId
}
