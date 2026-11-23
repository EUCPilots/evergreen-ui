Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $State.AppSearchBox.Text = ''
    $State.LibraryPathBox.Text = [string]$State.Settings.LibraryPath
    $State.IntuneDefinitionsPathBox.Text = [string]$State.Settings.IntuneDefinitionsPath
    $State.PackageOutputPathBox.Text = if ([string]::IsNullOrWhiteSpace([string]$State.Settings.PackageOutputPath)) {
        [string]$State.Settings.OutputPath
    }
    else {
        [string]$State.Settings.PackageOutputPath
    }
    $State.DownloadQueueListView.ItemsSource = $State.Queue
    $State.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::new(0)
    $State.DownloadTrayContent.Visibility = [System.Windows.Visibility]::Collapsed
    $trayHeight = [Math]::Clamp([int]$State.Settings.DownloadTrayHeight, 120, 600)
    $State.Settings.DownloadTrayHeight = $trayHeight
    $appsListWidth = 0
    $savedAppsListWidth = if ($State.Settings.Contains('AppsListWidth')) {
        [string]$State.Settings.AppsListWidth
    }
    else {
        [string]$State.AppsListColumn.Width.Value
    }
    if (-not [int]::TryParse(
            $savedAppsListWidth, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$appsListWidth
        ) -or $appsListWidth -lt $State.AppsListColumn.MinWidth) {
        $appsListWidth = [int]$State.AppsListColumn.Width.Value
        $message = "Invalid saved application list width '$savedAppsListWidth'; using $appsListWidth."
        Write-Verbose -Message "EvergreenUI: $message"
        Write-EwWorkbenchLog -State $State -Message $message -Level Warning
    }
    $State.Settings.AppsListWidth = $appsListWidth
    # Bound the column before layout without discarding the preferred width.
    $State.AppsListColumn.MaxWidth = $State.AppsListColumn.MinWidth
    $State.AppsListColumn.Width = [System.Windows.GridLength]::new($appsListWidth)
    $updateAppsListMaxWidth = {
        if ($State.AppsPanel.ActualWidth -gt 0) {
            $State.AppsListColumn.MaxWidth = [Math]::Max(
                $State.AppsListColumn.MinWidth,
                $State.AppsPanel.ActualWidth - $State.AppsSplitterColumn.Width.Value - $State.ArtifactsColumn.MinWidth
            )
        }
    }.GetNewClosure()
    & $updateAppsListMaxWidth
    $State.AppsPanel.Add_SizeChanged({
        & $updateAppsListMaxWidth
    }.GetNewClosure())
    $updateArtifactControlsLayout = {
        $width = $State.ArtifactControlsGrid.ActualWidth
        $actionsWidth = $State.ArtifactActionsPanel.DesiredSize.Width
        if ($width -le 0 -or $actionsWidth -le 0) {
            return
        }
        $stackActions = $width -lt ($State.ArtifactFiltersPanel.MinWidth + $actionsWidth)
        $isStacked = [System.Windows.Controls.Grid]::GetRow($State.ArtifactActionsPanel) -eq 1
        if ($stackActions -eq $isStacked) {
            return
        }
        if ($stackActions) {
            [System.Windows.Controls.Grid]::SetRow($State.ArtifactActionsPanel, 1)
            [System.Windows.Controls.Grid]::SetColumn($State.ArtifactActionsPanel, 0)
            [System.Windows.Controls.Grid]::SetColumnSpan($State.ArtifactActionsPanel, 2)
            [System.Windows.Controls.Grid]::SetColumnSpan($State.ArtifactFiltersPanel, 2)
        }
        else {
            [System.Windows.Controls.Grid]::SetColumnSpan($State.ArtifactFiltersPanel, 1)
            [System.Windows.Controls.Grid]::SetColumnSpan($State.ArtifactActionsPanel, 1)
            [System.Windows.Controls.Grid]::SetColumn($State.ArtifactActionsPanel, 1)
            [System.Windows.Controls.Grid]::SetRow($State.ArtifactActionsPanel, 0)
        }
    }.GetNewClosure()
    $State.ArtifactControlsGrid.Add_SizeChanged({ & $updateArtifactControlsLayout }.GetNewClosure())
    $State.ArtifactActionsPanel.Add_SizeChanged({ & $updateArtifactControlsLayout }.GetNewClosure())
    $State.EvergreenMenu = [System.Windows.Controls.ContextMenu]::new()
    $State.EvergreenMenu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $State.EvergreenMenu.PlacementTarget = $State.EvergreenMenuButton
    $State.RefreshAppsButton = [System.Windows.Controls.MenuItem]::new()
    $State.RefreshAppsButton.Header = 'Refresh catalog'
    $State.ReloadAppVersionsButton = [System.Windows.Controls.MenuItem]::new()
    $State.ReloadAppVersionsButton.Header = 'Reload selected app versions'
    $State.UpdateEvergreenButton = [System.Windows.Controls.MenuItem]::new()
    $State.UpdateEvergreenButton.Header = 'Update Evergreen'
    $State.ClearWorkbenchCacheButton = [System.Windows.Controls.MenuItem]::new()
    $State.ClearWorkbenchCacheButton.Header = 'Clear Workbench cache'
    $State.OpenCacheFolderButton = [System.Windows.Controls.MenuItem]::new()
    $State.OpenCacheFolderButton.Header = 'Open cache folder'
    $null = $State.EvergreenMenu.Items.Add($State.RefreshAppsButton)
    $null = $State.EvergreenMenu.Items.Add($State.ReloadAppVersionsButton)
    $null = $State.EvergreenMenu.Items.Add([System.Windows.Controls.Separator]::new())
    $null = $State.EvergreenMenu.Items.Add($State.UpdateEvergreenButton)
    $null = $State.EvergreenMenu.Items.Add($State.ClearWorkbenchCacheButton)
    $null = $State.EvergreenMenu.Items.Add($State.OpenCacheFolderButton)
    $State.EvergreenMenuButton.ContextMenu = $State.EvergreenMenu
    $State.EvergreenMenuButton.Add_Click({
        $State.EvergreenMenu.IsOpen = $true
    }.GetNewClosure())
    $State.ArtifactFilterControls = @{}
    $State.AllowFilterEvents = $true
    $State.SuppressAppSelection = $false
    $State.AppsLoading = $false
    $State.AppCatalog = @()
    $State.AllArtifacts = @()
    $State.PendingLastAppName = if ($State.Settings.Contains('LastAppName')) { [string]$State.Settings.LastAppName } else { '' }
    Initialize-EwWorkbenchMaintenanceView -State $State
    $State.Queue.add_CollectionChanged({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())

    $State.NavApps.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Apps' }
    }.GetNewClosure())
    $State.NavLibrary.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Library' }
    }.GetNewClosure())
    $State.NavPackages.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Packages' }
    }.GetNewClosure())
    $State.NavIntune.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Intune' }
    }.GetNewClosure())
    $State.NavNerdio.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Nerdio' }
    }.GetNewClosure())
    $State.NavInstall.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Install' }
    }.GetNewClosure())
    Initialize-EwWorkbenchPackageView -State $State
    Initialize-EwWorkbenchPublishView -State $State
    Initialize-EwWorkbenchNerdioView -State $State
    Initialize-EwWorkbenchM365View -State $State
    Initialize-EwWorkbenchInstallView -State $State
    $State.AppSearchBox.Add_TextChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchAppList' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.RefreshAppsButton.Add_Click({
        try {
            $State.AppsLoading = $true
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Apps'
                Name = 'Refresh application catalog'
                ScriptBlock = { Get-EwApp -Force }
            }
        }
        catch {
            $State.AppsLoading = $false
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.AppsListView.Add_SelectionChanged({
        if ($State.SuppressAppSelection -or $State.AppsLoading -or $null -eq $State.AppsListView.SelectedItem) {
            return
        }
        $selectedApp = $State.AppsListView.SelectedItem
        $State.CurrentApp = $selectedApp
        $State.CurrentAppName = [string]$selectedApp.Name
        $State.PendingLastAppName = ''
        if ([string]$State.Settings.LastAppName -ne $State.CurrentAppName) {
            & $State.ModuleInvoker -Name 'Save-EwWorkbenchUiSetting' -Parameters @{
                State = $State
                Name = 'LastAppName'
                Value = $State.CurrentAppName
            }
        }
        $State.SelectedAppText.Text = "Loading versions for $($selectedApp.FriendlyName)..."
        $State.AllArtifacts = @()
        $State.ArtifactsGrid.ItemsSource = @()
        $State.ArtifactFiltersPanel.Children.Clear()
        $State.ArtifactCountLabel.Text = 'Loading artifacts'
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Artifacts'
                Name = "Load $($selectedApp.Name) artifacts"
                ScriptBlock = {
                    param($AppName)
                    Get-EwApp -Name $AppName
                }
                ArgumentList = @([string]$selectedApp.Name)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.AppsListView.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
        $selectedApp = $args[1].OriginalSource.Tag
        if ($null -eq $selectedApp -or $null -ne $State.ActiveJobId) {
            return
        }
        try {
            $wasFavourite = [bool]$selectedApp.IsFavourite
            if ($wasFavourite) {
                & $State.ModuleInvoker -Name 'Remove-EwFavouriteApp' -Parameters @{ Name = $selectedApp.Name } | Out-Null
            }
            else {
                & $State.ModuleInvoker -Name 'Add-EwFavouriteApp' -Parameters @{ Name = $selectedApp.Name } | Out-Null
            }
            $State.AppCatalog = @(& $State.ModuleInvoker -Name 'Get-EwApp' -Parameters @{})
            $State.SuppressAppSelection = $true
            try {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchAppList' -Parameters @{ State = $State }
                $State.AppsListView.SelectedItem = $State.AppCatalog |
                    Where-Object Name -eq $selectedApp.Name |
                    Select-Object -First 1
            }
            finally {
                $State.SuppressAppSelection = $false
            }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Updated favourite status for $($selectedApp.FriendlyName)."
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not update favourite status: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.ExportArtifactsButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchArtifactExport' -Parameters @{ State = $State }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not export artifacts: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $columnMenu = $State.ShowArtifactColumnsButton.ContextMenu
    $columnMenu.PlacementTarget = $State.ShowArtifactColumnsButton
    $savedHiddenColumns = if ($State.Settings.Contains('ArtifactHiddenColumns')) {
        $State.Settings.ArtifactHiddenColumns
    } else { '' }
    $hiddenColumns = @()
    if ($savedHiddenColumns -is [string]) {
        $hiddenColumns = @($savedHiddenColumns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $optionalColumns = @($State.ArtifactsGrid.Columns | Where-Object { [string]$_.Header -notin @('Version', 'URI') } | ForEach-Object { [string]$_.Header })
        $invalidColumns = @($hiddenColumns | Where-Object { $_ -notin $optionalColumns })
        if ($invalidColumns.Count -gt 0) {
            Write-EwWorkbenchLog -State $State -Message "Ignoring invalid saved hidden artifact columns: $($invalidColumns -join ', '). Version and URI must remain visible." -Level Warning
        }
    }
    else {
        Write-EwWorkbenchLog -State $State -Message 'Invalid saved ArtifactHiddenColumns; expected a comma-separated string. Showing all artifact columns.' -Level Warning
    }
    foreach ($column in $State.ArtifactsGrid.Columns) {
        $required = [string]$column.Header -in @('Version', 'URI')
        $column.Visibility = if (-not $required -and [string]$column.Header -in $hiddenColumns) {
            [System.Windows.Visibility]::Collapsed
        } else { [System.Windows.Visibility]::Visible }
        $menuItem = [System.Windows.Controls.MenuItem]::new()
        $menuItem.Header = [string]$column.Header
        $menuItem.Tag = $column
        $menuItem.IsCheckable = $true
        $menuItem.IsChecked = $column.Visibility -eq [System.Windows.Visibility]::Visible
        $menuItem.StaysOpenOnClick = $true
        $menuItem.IsEnabled = -not $required
        if ($required) {
            $menuItem.ToolTip = "$($column.Header) must remain visible."
            [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($menuItem, $true)
        }
        else {
            $menuItem.Add_Click({
                param($eventSource, $clickArgs)
                $eventSource.Tag.Visibility = if ($eventSource.IsChecked) {
                    [System.Windows.Visibility]::Visible
                } else { [System.Windows.Visibility]::Collapsed }
                $hidden = @($State.ArtifactsGrid.Columns |
                    Where-Object { $_.Visibility -ne [System.Windows.Visibility]::Visible -and [string]$_.Header -notin @('Version', 'URI') } |
                    ForEach-Object { [string]$_.Header })
                & $State.ModuleInvoker -Name 'Save-EwWorkbenchUiSetting' -Parameters @{
                    State = $State
                    Name = 'ArtifactHiddenColumns'
                    Value = $hidden -join ','
                }
                $clickArgs.Handled = $true
            }.GetNewClosure())
        }
        $null = $columnMenu.Items.Add($menuItem)
    }
    $columnMenu.Add_Opened({
        foreach ($item in $columnMenu.Items) {
            $item.IsChecked = $item.Tag.Visibility -eq [System.Windows.Visibility]::Visible
        }
    }.GetNewClosure())
    $State.ShowArtifactColumnsButton.Add_Click({
        $columnMenu.IsOpen = $true
    }.GetNewClosure())
    $State.ArtifactsGrid.Add_SelectionChanged({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.ArtifactsGrid.Add_PreviewMouseRightButtonDown({
        $row = [System.Windows.Controls.ItemsControl]::ContainerFromElement(
            $State.ArtifactsGrid,
            $args[1].OriginalSource
        )
        if ($row -is [System.Windows.Controls.DataGridRow]) {
            $row.IsSelected = $true
        }
    }.GetNewClosure())
    $copyArtifactUriMenuItem = $State.ArtifactsGrid.ContextMenu.Items[0]
    $openArtifactUriMenuItem = $State.ArtifactsGrid.ContextMenu.Items[1]
    $State.ArtifactsGrid.Add_ContextMenuOpening({
        $artifact = $State.ArtifactsGrid.SelectedItem
        $uriProperty = if ($null -ne $artifact) { $artifact.PSObject.Properties['URI'] } else { $null }
        $uri = if ($null -ne $uriProperty) { [string]$uriProperty.Value } else { '' }
        $isHttpUri = $false
        $uriObject = $null
        if (-not [string]::IsNullOrWhiteSpace($uri)) {
            $isHttpUri = [uri]::TryCreate($uri, [System.UriKind]::Absolute, [ref]$uriObject) -and
                $uriObject.Scheme -in @('http', 'https')
        }
        if (-not $isHttpUri) {
            $args[1].Handled = $true
            return
        }
        $copyArtifactUriMenuItem.IsEnabled = $true
        $openArtifactUriMenuItem.IsEnabled = $true
    }.GetNewClosure())
    $copyArtifactUriMenuItem.Add_Click({
        $artifact = $State.ArtifactsGrid.SelectedItem
        $uriProperty = if ($null -ne $artifact) { $artifact.PSObject.Properties['URI'] } else { $null }
        $uri = if ($null -ne $uriProperty) { [string]$uriProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($uri)) {
            return
        }
        try {
            [System.Windows.Clipboard]::SetText($uri)
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not copy artifact URI: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $openArtifactUriMenuItem.Add_Click({
        $artifact = $State.ArtifactsGrid.SelectedItem
        $uriProperty = if ($null -ne $artifact) { $artifact.PSObject.Properties['URI'] } else { $null }
        $uri = if ($null -ne $uriProperty) { [string]$uriProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($uri)) {
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Open-EwWorkbenchLink' -Parameters @{ Uri = [uri]$uri }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not open artifact URI: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $addSelectedArtifacts = {
        $selectedApp = $State.CurrentApp
        if ($null -eq $selectedApp) {
            return 0
        }
        $added = 0
        foreach ($artifact in @($State.ArtifactsGrid.SelectedItems)) {
            $architectureProperty = $artifact.PSObject.Properties['Architecture']
            $uriProperty = $artifact.PSObject.Properties['URI']
            if ($null -eq $uriProperty -or [string]::IsNullOrWhiteSpace([string]$uriProperty.Value)) {
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State
                    Message = "Skipped $($selectedApp.FriendlyName) artifact $($artifact.Version) because it has no download URI."
                    Level = 'Warning'
                }
                continue
            }
            $null = $State.Queue.Add([PSCustomObject]@{
                    Id = [guid]::NewGuid().ToString()
                    AppName = [string]$selectedApp.Name
                    Version = [string]$artifact.Version
                    Architecture = if ($null -ne $architectureProperty) { [string]$architectureProperty.Value } else { '' }
                    URI = [string]$uriProperty.Value
                    Artifact = $artifact
                    Status = 'Pending'
                    SavedPath = ''
                })
            $added++
        }
        if ($added -gt 0) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Added $added selected artifact(s) for $($selectedApp.FriendlyName) to the download queue."
            }
        }
        return $added
    }.GetNewClosure()
    $State.QueueDownloadButton.Add_Click({
        $null = & $addSelectedArtifacts
        $State.DownloadTrayToggleButton.IsChecked = $false
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())

    $State.ThemeCombo.SelectedItem = [string]$State.Settings.Theme
    $State.ThemeCombo.Add_SelectionChanged({
        $themeName = [string]$State.ThemeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($themeName)) {
            return
        }
        try {
            $State.Window.ThemeMode = switch ($themeName) {
                'Light' { [System.Windows.ThemeMode]::Light }
                'Dark' { [System.Windows.ThemeMode]::Dark }
                default { [System.Windows.ThemeMode]::System }
            }
            & $State.ModuleInvoker -Name 'Set-EwWorkbenchTitleBar' -Parameters @{ Window = $State.Window }
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{ Name = 'Theme'; Value = $themeName }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = "Theme set to $themeName." }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not change the theme: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.BrowseLibraryPathButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select the Evergreen library folder'
        if (-not [string]::IsNullOrWhiteSpace($State.LibraryPathBox.Text) -and
            (Test-Path -LiteralPath $State.LibraryPathBox.Text -PathType Container)) {
            $dialog.InitialDirectory = $State.LibraryPathBox.Text
        }
        if ($dialog.ShowDialog($State.Window)) {
            $State.LibraryPathBox.Text = $dialog.FolderName
        }
    }.GetNewClosure())
    $State.SetLibraryPathButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{ Name = 'LibraryPath'; Value = [string]$State.LibraryPathBox.Text }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = 'Library location saved.' }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not save library location: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.LoadLibraryButton.Add_Click({
        $libraryPath = [string]$State.LibraryPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Library'
                Name = 'Load Evergreen library'
                ScriptBlock = {
                    param($Path)
                    Get-EwLibrary -Path $Path
                }
                ArgumentList = @($libraryPath)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.UpdateLibraryButton.Add_Click({
        $libraryPath = [string]$State.LibraryPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'LibraryUpdate'
                Name = 'Update Evergreen library'
                ScriptBlock = {
                    param($Path)
                    $update = Update-EwLibrary -Path $Path
                    $items = @(Get-EwLibrary -Path $Path)
                    [PSCustomObject]@{
                        Result = $update
                        Items = $items
                    }
                }
                ArgumentList = @($libraryPath)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.LibraryListView.Add_SelectionChanged({
        $application = $State.LibraryListView.SelectedItem
        if ($null -eq $application) {
            $State.LibraryDetailsText.Text = 'Select an application to view its library versions'
            $State.LibraryVersionsListView.ItemsSource = @()
            return
        }
        $readProperty = {
            param(
                [Parameter(Mandatory)]
                [psobject]$InputObject,

                [Parameter(Mandatory)]
                [string[]]$Name
            )
            foreach ($propertyName in $Name) {
                $property = $InputObject.PSObject.Properties[$propertyName]
                if ($null -ne $property) {
                    return $property.Value
                }
            }
            return ''
        }.GetNewClosure()
        $versions = [System.Collections.Generic.List[object]]::new()
        $sourceItemProperty = $application.PSObject.Properties['SourceItem']
        if ($null -ne $sourceItemProperty -and $null -ne $sourceItemProperty.Value) {
            $versionsProperty = $sourceItemProperty.Value.PSObject.Properties['Versions']
            if ($null -ne $versionsProperty) {
                foreach ($version in @($versionsProperty.Value)) {
                    if ($null -eq $version) {
                        continue
                    }
                    $versions.Add([PSCustomObject]@{
                            Version = [string](& $readProperty -InputObject $version -Name @('Version'))
                            Architecture = [string](& $readProperty -InputObject $version -Name @('Architecture'))
                            Type = [string](& $readProperty -InputObject $version -Name @('Type'))
                            URI = [string](& $readProperty -InputObject $version -Name @('URI', 'Uri', 'URL', 'Url'))
                        })
                    }
                }
            }
        $State.LibraryDetailsText.Text = "Versions for $($application.Name): $($versions.Count)"
        $State.LibraryVersionsListView.ItemsSource = $versions.ToArray()
    }.GetNewClosure())

    $State.DownloadTrayToggleButton.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.DownloadTrayToggleButton.Add_Unchecked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.ChangeDownloadPathButton.Add_Click({
        $State.NavSettings.IsChecked = $true
        $clickArgs = [System.Windows.RoutedEventArgs]::new(
            [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
        )
        $State.BrowseDownloadFolderButton.RaiseEvent($clickArgs)
    }.GetNewClosure())
    $saveAppsListWidth = {
        $width = [int][Math]::Round($State.AppsListColumn.Width.Value)
        & $State.ModuleInvoker -Name 'Save-EwWorkbenchUiSetting' -Parameters @{
            State = $State
            Name = 'AppsListWidth'
            Value = [string]$width
        }
    }.GetNewClosure()
    $State.AppsListGridSplitter.Add_DragCompleted({
        if (-not $args[1].Canceled) {
            & $saveAppsListWidth
        }
    }.GetNewClosure())
    $State.AppsListGridSplitter.Add_KeyUp({
        if ($args[1].Key -in @([System.Windows.Input.Key]::Left, [System.Windows.Input.Key]::Right)) {
            & $saveAppsListWidth
        }
    }.GetNewClosure())
    $State.DownloadTrayGridSplitter.Add_DragCompleted({
        $height = [int][Math]::Round($State.AppsPanel.RowDefinitions[3].ActualHeight)
        $height = [Math]::Clamp($height, 120, 600)
        $State.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::new($height)
        & $State.ModuleInvoker -Name 'Save-EwWorkbenchUiSetting' -Parameters @{
            State = $State
            Name = 'DownloadTrayHeight'
            Value = [string]$height
        }
    }.GetNewClosure())
    $State.ClearCompletedQueueButton.Add_Click({
        foreach ($item in @($State.Queue | Where-Object Status -in @('Downloaded', 'Failed'))) {
            $State.Queue.Remove($item)
        }
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.DownloadQueueListView.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            $button = $args[1].OriginalSource
            $item = $button.Tag
            if ($null -eq $item) {
                return
            }
            if ([string]$button.Content -eq 'x') {
                if ($item.Status -eq 'Downloading') {
                    & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                        State = $State
                        Message = 'A download cannot be removed while it is running.'
                        Level = 'Warning'
                    }
                    return
                }
                $State.Queue.Remove($item)
                return
            }
            if ([string]$button.Content -eq 'Open folder') {
                try {
                    $folder = Split-Path -Path ([string]$item.SavedPath) -Parent
                    if ([string]::IsNullOrWhiteSpace($folder) -or
                        -not (Test-Path -LiteralPath $folder -PathType Container)) {
                        throw 'The downloaded file folder is not available.'
                    }
                    Start-Process -FilePath $folder -ErrorAction Stop
                }
                catch {
                    & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                        State = $State
                        Message = "Could not open the download folder: $($_.Exception.Message)"
                        Level = 'Error'
                    }
                }
            }
        }.GetNewClosure()
    )
    $startDownloads = {
        if ($null -ne $State.ActiveJobId -and $State.ActiveJobKind -eq 'Downloads') {
            try {
                $null = Stop-EwJob -Id $State.ActiveJobId -Confirm:$false -ErrorAction Stop
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State
                    Message = 'Stopping queued downloads.'
                }
            }
            catch {
                & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                    State = $State
                    Message = "Could not stop downloads: $($_.Exception.Message)"
                    Level = 'Error'
                }
            }
            return
        }
        if ($null -ne $State.ActiveJobId) {
            return
        }
        $items = @(
            foreach ($item in $State.Queue) {
                if ($item.Status -eq 'Pending') {
                    $item.Status = 'Downloading'
                    [PSCustomObject]@{
                        Id = $item.Id
                        AppName = $item.AppName
                        Version = $item.Version
                        Artifact = $item.Artifact
                    }
                }
            }
        )
        if ($items.Count -eq 0) {
            return
        }
        $State.DownloadTrayToggleButton.IsChecked = $true
        $State.DownloadQueueListView.Items.Refresh()
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Downloads'
                Name = 'Download queued artifacts'
                ScriptBlock = {
                    param([object[]]$QueueItems)
                    foreach ($item in $QueueItems) {
                        try {
                            $saved = @(Save-EwArtifact -AppName $item.AppName -Artifact $item.Artifact)
                            if ($saved.Count -eq 0) {
                                throw "No saved file was returned for $($item.AppName) $($item.Version)."
                            }
                            [PSCustomObject]@{
                                QueueId = $item.Id
                                AppName = $item.AppName
                                Version = $item.Version
                                Succeeded = $true
                                Path = [string]$saved[0].Path
                                Error = ''
                            }
                        }
                        catch {
                            [PSCustomObject]@{
                                QueueId = $item.Id
                                AppName = $item.AppName
                                Version = $item.Version
                                Succeeded = $false
                                Path = ''
                                Error = $_.Exception.Message
                            }
                        }
                    }
                }
                ArgumentList = ,([object[]]$items)
            }
        }
        catch {
            foreach ($item in $State.Queue | Where-Object Status -eq 'Downloading') {
                $item.Status = 'Pending'
            }
            $State.DownloadQueueListView.Items.Refresh()
            & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure()
    $State.DownloadTrayActionButton.Add_Click({
        & $startDownloads
    }.GetNewClosure())
    $State.DownloadNowButton.Add_Click({
        $added = & $addSelectedArtifacts
        if ($added -gt 0) {
            $State.DownloadTrayToggleButton.IsChecked = $true
            & $startDownloads
        }
    }.GetNewClosure())
    & $State.ModuleInvoker -Name 'Show-EwWorkbenchDownloadTray' -Parameters @{ State = $State }
}
