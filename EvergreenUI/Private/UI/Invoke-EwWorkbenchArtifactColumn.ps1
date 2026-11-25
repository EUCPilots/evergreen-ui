Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchArtifactColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    if (-not $State.Contains('ArtifactHiddenColumns')) {
        $State.ArtifactHiddenColumns = [System.Collections.Generic.List[string]]::new()
        $saved = if ($State.Settings.Contains('ArtifactHiddenColumns')) {
            $State.Settings.ArtifactHiddenColumns
        } else { '' }
        if ($saved -is [string]) {
            foreach ($name in ($saved -split ',')) {
                $name = $name.Trim()
                if (-not $name) { continue }
                if ($name -in @('Version', 'URI')) {
                    Write-EwWorkbenchLog -State $State -Message "Ignoring invalid saved hidden artifact columns: $name must remain visible." -Level Warning
                }
                elseif ($name -notin $State.ArtifactHiddenColumns) {
                    $State.ArtifactHiddenColumns.Add($name)
                }
            }
        }
        else {
            Write-EwWorkbenchLog -State $State -Message 'Invalid saved ArtifactHiddenColumns; expected a comma-separated string. Showing all artifact columns.' -Level Warning
        }
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($artifact in $State.AllArtifacts) {
        if ($null -eq $artifact) { continue }
        foreach ($property in $artifact.PSObject.Properties) {
            if ($seen.Add($property.Name)) {
                $names.Add($property.Name)
            }
        }
    }
    $preferred = @('Version', 'Architecture', 'Channel', 'Release', 'Type', 'Language', 'Date')
    $orderedNames = @(
        $preferred | Where-Object { $seen.Contains($_) }
        $names | Where-Object { $_ -notin $preferred -and $_ -ne 'URI' }
        if ($seen.Contains('URI')) { 'URI' }
    )

    $menu = $State.ShowArtifactColumnsButton.ContextMenu
    $menu.Items.Clear()
    $State.ArtifactsGrid.Columns.Clear()
    foreach ($name in $orderedNames) {
        $column = [System.Windows.Controls.DataGridTextColumn]::new()
        $column.Header = $name
        $column.Binding = [System.Windows.Data.Binding]::new($name)
        $column.ElementStyle = $State.ArtifactsGrid.FindResource('WorkbenchGridTextStyle')
        $column.Width = if ($name -eq 'URI') {
            [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
        } else {
            $width = switch ($name) {
                { $_ -in @('Version', 'Architecture', 'Release') } { 110 }
                'Type' { 90 }
                default { 120 }
            }
            [System.Windows.Controls.DataGridLength]::new($width)
        }
        $column.MinWidth = if ($name -eq 'URI') { 200 } else { 60 }
        $required = $name -in @('Version', 'URI')
        $column.Visibility = if (-not $required -and $name -in $State.ArtifactHiddenColumns) {
            [System.Windows.Visibility]::Collapsed
        } else { [System.Windows.Visibility]::Visible }
        $State.ArtifactsGrid.Columns.Add($column)

        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = $name
        $item.Tag = $column
        $item.IsCheckable = $true
        $item.IsChecked = $column.Visibility -eq [System.Windows.Visibility]::Visible
        $item.StaysOpenOnClick = $true
        $item.IsEnabled = -not $required
        if ($required) {
            $item.ToolTip = "$name must remain visible."
            [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($item, $true)
        }
        else {
            $item.Add_Click({
                param($eventSource, $clickArgs)
                $propertyName = [string]$eventSource.Header
                $eventSource.Tag.Visibility = if ($eventSource.IsChecked) {
                    [System.Windows.Visibility]::Visible
                } else { [System.Windows.Visibility]::Collapsed }
                # Keep choices for properties absent from this application's schema.
                $oldNames = @($State.ArtifactHiddenColumns | Where-Object { $_ -eq $propertyName })
                foreach ($oldName in $oldNames) {
                    $null = $State.ArtifactHiddenColumns.Remove($oldName)
                }
                if (-not $eventSource.IsChecked) {
                    $State.ArtifactHiddenColumns.Add($propertyName)
                }
                & $State.ModuleInvoker -Name 'Save-EwWorkbenchUiSetting' -Parameters @{
                    State = $State
                    Name = 'ArtifactHiddenColumns'
                    Value = $State.ArtifactHiddenColumns -join ','
                }
                $clickArgs.Handled = $true
            }.GetNewClosure())
        }
        $null = $menu.Items.Add($item)
    }
}
