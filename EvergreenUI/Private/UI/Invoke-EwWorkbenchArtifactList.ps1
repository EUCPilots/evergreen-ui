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
        $State.ArtifactFiltersPanel.Children.Clear()
        $State.ArtifactFilterControls = @{}
        if ($State.AllArtifacts.Count -gt 0) {
            foreach ($filter in @(Get-EwFilterableProperty -Artifact $State.AllArtifacts)) {
                $group = [System.Windows.Controls.StackPanel]::new()
                $group.Margin = [System.Windows.Thickness]::new(0, 0, 10, 6)
                $label = [System.Windows.Controls.TextBlock]::new()
                $label.Text = $filter.DisplayName
                $label.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
                $combo = [System.Windows.Controls.ComboBox]::new()
                $combo.MinWidth = 120
                $combo.Tag = $filter.Name
                $combo.ToolTip = "Filter artifacts by $($filter.DisplayName)"
                $null = $combo.Items.Add('All')
                foreach ($value in $filter.UniqueValues) {
                    $null = $combo.Items.Add($value)
                }
                $combo.SelectedIndex = 0
                $combo.Add_SelectionChanged({
                    if ($State.AllowFilterEvents) {
                        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactList' -Parameters @{ State = $State }
                    }
                }.GetNewClosure())
                $null = $group.Children.Add($label)
                $null = $group.Children.Add($combo)
                $null = $State.ArtifactFiltersPanel.Children.Add($group)
                $State.ArtifactFilterControls[$filter.Name] = $combo
            }
        }
    }

    $State.AllowFilterEvents = $false
    try {
        $filtered = @($State.AllArtifacts)
        foreach ($propertyName in $State.ArtifactFilterControls.Keys) {
            $combo = $State.ArtifactFilterControls[$propertyName]
            $selectedValue = [string]$combo.SelectedItem
            if ([string]::IsNullOrWhiteSpace($selectedValue) -or $selectedValue -eq 'All') {
                continue
            }
            if ($propertyName -eq '_DerivedType') {
                $filtered = @($filtered | Where-Object {
                        [System.IO.Path]::GetExtension([string]$_.URI).TrimStart('.').ToLowerInvariant() -eq $selectedValue
                    })
            }
            else {
                $filtered = @($filtered | Where-Object {
                        $property = $_.PSObject.Properties[$propertyName]
                        $null -ne $property -and [string]$property.Value -eq $selectedValue
                    })
            }
        }
    }
    finally {
        $State.AllowFilterEvents = $true
    }
    $State.ArtifactsGrid.ItemsSource = [object[]]$filtered
    $State.ArtifactCountLabel.Text = "$($filtered.Count) artifacts"
    $State.QueueDownloadButton.IsEnabled = $State.ArtifactsGrid.SelectedItems.Count -gt 0 -and $null -eq $State.ActiveJobId
}
