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
                    $null = $group.Children.Add($control)
                    $null = $State.ArtifactFiltersPanel.Children.Add($group)
                    $State.ArtifactFilterControls[$filter.Name] = @{ Control = $control }
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
        if ($filterState.Control.SelectedIndex -gt 0) {
            $selectedValue = [string]$filterState.Control.SelectedItem
            $filtered = @($filtered | Where-Object {
                (& $getArtifactValue -Artifact $_ -PropertyName $propertyName) -eq $selectedValue
            })
        }
    }

    $State.ArtifactsGrid.ItemsSource = [object[]]$filtered
    $State.ArtifactCountLabel.Text = "Showing $($filtered.Count) of $($State.AllArtifacts.Count) artifacts"
    $State.QueueDownloadButton.IsEnabled = $State.ArtifactsGrid.SelectedItems.Count -gt 0 -and $null -eq $State.ActiveJobId
}
