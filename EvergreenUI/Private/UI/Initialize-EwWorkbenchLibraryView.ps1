Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchLibraryView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$State)

    foreach ($kind in @('Library', 'LibraryUpdate')) {
        $button = if ($kind -eq 'Library') { $State.LoadLibraryButton } else { $State.UpdateLibraryButton }
        $button.Add_Click({
            if ($null -ne $State.ActiveJobId) { return }
            $State.LibraryJobPath = [string]$State.LibraryPathBox.Text
            $selected = $State.LibraryListView.SelectedItem
            $State.LibrarySelectedName = if ($null -ne $selected) { [string]$selected.Name } else { '' }
            $State.LoadedLibraryPath = ''
            try {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                    State = $State; Kind = $kind
                    Name = if ($kind -eq 'Library') { 'Load Evergreen library' } else { 'Update Evergreen library' }
                    ScriptBlock = {
                        param($Path, $Update)
                        if ($Update) { $null = Update-EwLibrary -Path $Path -Confirm:$false }
                        Get-EwLibrary -Path $Path
                    }
                    ArgumentList = @($State.LibraryJobPath, ($kind -eq 'LibraryUpdate'))
                }
            }
            catch {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryActionState' -Parameters @{ State = $State }
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = $_.Exception.Message; Level = 'Error' }
            }
        }.GetNewClosure())
    }
    $State.LibraryListView.Add_SelectionChanged({
        $application = $State.LibraryListView.SelectedItem
        $versions = [Collections.Generic.List[object]]::new()
        if ($null -ne $application -and $null -ne $application.PSObject.Properties['SourceItem'] -and
            $null -ne $application.SourceItem -and $null -ne $application.SourceItem.PSObject.Properties['Versions']) {
            $applicationPath = if ($null -ne $application.SourceItem.PSObject.Properties['ApplicationPath']) {
                [string]$application.SourceItem.ApplicationPath
            }
            elseif ($null -ne $application.PSObject.Properties['Path']) { [string]$application.Path }
            else { '' }
            $index = 0
            foreach ($version in @($application.SourceItem.Versions)) {
                if ($null -ne $version) {
                    $row = [ordered]@{ Index = $index }
                    foreach ($field in 'Version', 'Architecture', 'Type', 'URI') {
                        $property = $version.PSObject.Properties[$field]
                        if ($field -eq 'URI' -and $null -eq $property) { $property = $version.PSObject.Properties['URL'] }
                        $row[$field] = if ($null -ne $property) { [string]$property.Value } else { '' }
                    }
                    $folders = [Collections.Generic.List[string]]::new()
                    $paths = @(
                        $property = $version.PSObject.Properties['Path']
                        if ($null -ne $property) {
                            foreach ($recorded in @($property.Value)) {
                                $recordedPath = [string]$recorded
                                if ([string]::IsNullOrWhiteSpace($recordedPath)) { continue }
                                try {
                                    $resolvedPath = if ([IO.Path]::IsPathFullyQualified($recordedPath)) {
                                        [IO.Path]::GetFullPath($recordedPath)
                                    }
                                    elseif ([IO.Path]::IsPathFullyQualified($applicationPath)) {
                                        [IO.Path]::GetFullPath($recordedPath, $applicationPath)
                                    }
                                    if ($null -ne $resolvedPath) {
                                        $folder = [IO.Path]::GetDirectoryName($resolvedPath)
                                        if (-not [string]::IsNullOrEmpty($folder) -and -not $folders.Contains($folder)) {
                                            $folders.Add($folder)
                                        }
                                        $resolvedPath
                                    }
                                    else {
                                        & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                                            State = $State; Level = 'Warning'; PreserveStatus = $true
                                            Message = "Could not resolve a library location for $($application.Name): application folder is unavailable."
                                        }
                                        "Unresolved path: $recordedPath"
                                    }
                                }
                                catch [System.Management.Automation.MethodInvocationException] {
                                    $reason = $_.Exception.InnerException
                                    if ($reason -isnot [ArgumentException] -and $reason -isnot [NotSupportedException] -and
                                        $reason -isnot [IO.PathTooLongException]) { throw }
                                    & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                                        State = $State; Level = 'Warning'; PreserveStatus = $true
                                        Message = "Could not resolve a library location for $($application.Name): $($reason.Message)"
                                    }
                                    'Invalid path'
                                }
                            }
                        }
                    )
                    $row['Location'] = if ($paths.Count -gt 0) { $paths -join '; ' } else { 'Not recorded' }
                    $row['Folders'] = $folders.ToArray()
                    $versions.Add([PSCustomObject]$row)
                }
                $index++
            }
        }
        $State.LibraryVersionsListView.ItemsSource = $versions.ToArray()
        $State.LibraryDetailsText.Text = if ($null -ne $application) {
            "Versions for $($application.Name): $($versions.Count)"
        } else { 'Select an application to view its library versions' }
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryActionState' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.LibraryVersionsListView.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryActionState' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.LibraryPathBox.AddHandler([System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
        [System.Windows.RoutedEventHandler]{
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryActionState' -Parameters @{ State = $State }
        }.GetNewClosure())
    $State.LibraryPathBox.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryActionState' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.RemoveLibraryAppButton.Add_Click({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryRemoval' -Parameters @{ State = $State; EntireApplication = $true }
    }.GetNewClosure())
    $State.RemoveLibraryVersionsButton.Add_Click({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchLibraryRemoval' -Parameters @{ State = $State; EntireApplication = $false }
    }.GetNewClosure())
    foreach ($grid in @($State.LibraryListView, $State.LibraryVersionsListView)) {
        $isVersionGrid = $grid -eq $State.LibraryVersionsListView
        $openFolderMenuItem = $grid.ContextMenu.Items[0]
        $getFolders = {
            param($Item)
            if ($null -eq $Item) { return @() }
            if ($isVersionGrid) {
                $property = $Item.PSObject.Properties['Folders']
                return @(if ($null -ne $property) { $property.Value })
            }
            $folder = if ($null -ne $Item.PSObject.Properties['SourceItem'] -and $null -ne $Item.SourceItem -and
                $null -ne $Item.SourceItem.PSObject.Properties['ApplicationPath']) {
                [string]$Item.SourceItem.ApplicationPath
            }
            elseif ($null -ne $Item.PSObject.Properties['Path']) { [string]$Item.Path }
            return @(if (-not [string]::IsNullOrWhiteSpace($folder)) { $folder })
        }.GetNewClosure()
        $grid.Add_PreviewMouseRightButtonDown({
            $row = [System.Windows.Controls.ItemsControl]::ContainerFromElement($grid, $args[1].OriginalSource)
            if ($row -is [System.Windows.Controls.DataGridRow] -and -not $row.IsSelected) {
                if ($isVersionGrid) { $grid.SelectedItems.Clear() }
                $row.IsSelected = $true
            }
            $grid.Tag = if ($row -is [System.Windows.Controls.DataGridRow]) { $row.Item } else { $null }
        }.GetNewClosure())
        $grid.Add_ContextMenuOpening({
            $item = if ($null -ne $grid.Tag) { $grid.Tag } else { $grid.SelectedItem }
            if ($null -eq $item) {
                $args[1].Handled = $true
                return
            }
            $folders = @(& $getFolders $item)
            $openFolderMenuItem.Tag = $folders
            $openFolderMenuItem.IsEnabled = $folders.Count -gt 0
        }.GetNewClosure())
        $grid.ContextMenu.Add_Closed({ $grid.Tag = $null }.GetNewClosure())
        $openFolderMenuItem.Add_Click({
            foreach ($folder in @($openFolderMenuItem.Tag)) {
                try {
                    & $State.ModuleInvoker -Name 'Open-EwWorkbenchFolder' -Parameters @{ Path = [string]$folder }
                }
                catch {
                    & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                        State = $State; Level = 'Error'
                        Message = "Could not open the library folder: $($_.Exception.Message)"
                    }
                }
            }
        }.GetNewClosure())
    }
}
