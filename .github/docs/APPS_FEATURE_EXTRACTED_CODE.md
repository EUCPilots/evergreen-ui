# Apps Feature - Extracted Code for Register-AppsFeature.ps1

## Overview
This document contains all extracted code related to the Apps feature from `Start-EvergreenWorkbench.ps1`, organized for implementation in `Register-AppsFeature.ps1` within the modularized feature registration architecture.

---

## 1. Control References

### Control Lookups (WPF FindName)
```powershell
# Core navigation and panels
$appsPanel = $window.FindName('AppsPanel')

# Buttons
$refreshAppsButton = $window.FindName('RefreshAppsButton')
$loadAppVersionsButton = $window.FindName('LoadAppVersionsButton')
$clearFiltersButton = $window.FindName('ClearFiltersButton')
$exportCsvButton = $window.FindName('ExportCsvButton')
$addToLibraryButton = $window.FindName('AddToLibraryButton')
$addToQueueButton = $window.FindName('AddToQueueButton')

# Input controls
$appSearchBox = $window.FindName('AppSearchBox')

# List views and containers
$appsListBox = $window.FindName('AppsListBox')
$filterWrapPanel = $window.FindName('FilterWrapPanel')

# Detail view elements
$syncHash.VersionsListView = $window.FindName('VersionsListView')
$syncHash.ResultsCountLabel = $window.FindName('ResultsCountLabel')
$appCountLabel = $window.FindName('AppCountLabel')
$appDetailEmpty = $window.FindName('AppDetailEmpty')
$appDetailLoading = $window.FindName('AppDetailLoading')
$appDetailLoadingLabel = $window.FindName('AppDetailLoadingLabel')
$appDetailContent = $window.FindName('AppDetailContent')
$appDetailTitle = $window.FindName('AppDetailTitle')
$syncHash.AppLastRefreshedLabel = $window.FindName('AppLastRefreshedLabel')
$appsActionStatusLabel = $window.FindName('AppsActionStatusLabel')
```

### SyncHash State Properties (Apps Feature)
```powershell
# Results and filtering state
CurrentAppResults           = @()      # Currently displayed version results for selected app
FilterState                 = @{}      # Dictionary of filter selections for current app
VersionsColSavedWidths      = @{}      # Saved column widths for show/hide operations

# Sorting state
VersionsSortProperty        = ''       # Property name to sort versions by
VersionsSortDirection       = 'Ascending'  # Sort direction (Ascending/Descending)

# Async load operation state
PendingLoadTimer            = $null    # Timer for debouncing rapid selection changes
PendingLoadPS               = $null    # PowerShell instance for Get-EvergreenApp call
PendingLoadRunspace         = $null    # Runspace for async operation
PendingLoadAsync            = $null    # Async result object
PendingLoadAppName          = $null    # App name of pending operation

# Control references (convenience)
VersionsListView            = $null    # ListView for displaying versions
ResultsCountLabel           = $null    # Label for result count
AppLastRefreshedLabel       = $null    # Label for cache refresh timestamp
```

---

## 2. Helper Scriptblocks

### $updateAppsComboSource
Updates the AppsListBox with filtered and sorted app list.
```powershell
$updateAppsComboSource = {
    param([string]$SearchText = '')

    $allApps = @($syncHash.AppList)
    if ($allApps.Count -eq 0) {
        $appsListBox.ItemsSource = @()
        $appCountLabel.Text = ''
        return
    }

    # Stamp IsFavourite on each item based on current config
    $favouriteSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($syncHash.Config.FavouriteApps),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($app in $allApps) {
        $app.IsFavourite = $favouriteSet.Contains($app.Name)
    }

    $source = if ([string]::IsNullOrWhiteSpace($SearchText)) {
        $allApps
    }
    else {
        $needle = $SearchText.Trim()
        @($allApps | Where-Object { $_.Name -like "*$needle*" -or $_.FriendlyName -like "*$needle*" })
    }

    # Favourites first (descending), then alphabetical by FriendlyName
    $sorted = @($source | Sort-Object -Property @(
            @{ Expression = 'IsFavourite'; Descending = $true },
            @{ Expression = 'FriendlyName' }
        ))

    $appsListBox.ItemsSource = $sorted
    $appCountLabel.Text = " $($sorted.Count) of $($allApps.Count)"
}
```

### $loadAppCatalog
Refreshes the Evergreen app catalog and updates the display.
```powershell
$loadAppCatalog = {
    param([switch]$Force)

    $refreshAppsButton.IsEnabled = $false
    try {
        [void](Get-EvergreenAppList -SyncHash $syncHash -Force:$Force)
        & $updateAppsComboSource -SearchText $appSearchBox.Text
    }
    finally {
        $refreshAppsButton.IsEnabled = $true
    }
}
```

### $rebuildVersionColumns
Dynamically rebuilds the VersionsListView columns based on returned app properties.
```powershell
$rebuildVersionColumns = {
    param([PSObject[]]$AppResults)

    if ($null -eq $AppResults -or $AppResults.Count -eq 0) { return }

    # Guard against double-wrapped data: if element 0 is itself an array, flatten one level.
    if ($AppResults[0] -is [System.Array]) {
        $AppResults = @($AppResults[0])
        if ($AppResults.Count -eq 0) { return }
    }

    $allProps = [string[]]$AppResults[0].PSObject.Properties.Name

    # Well-known preferred widths
    $widths = @{
        Version      = 140
        Architecture = 110
        Channel      = 130
        Release      = 100
        Platform     = 90
        Language     = 90
        Ring         = 110
        Track        = 90
        Type         = 80
        Product      = 110
        Date         = 100
        URI          = 460
    }

    # Order: Version first, URI last, everything else in declared order
    $skip = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('Version', 'URI'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $middle = $allProps | Where-Object { -not $skip.Contains($_) }
    $ordered = @(
        if ($allProps -contains 'Version') { 'Version' }
    ) + @($middle) + @(
        if ($allProps -contains 'URI') { 'URI' }
    )

    $gv = [System.Windows.Controls.GridView]::new()
    foreach ($prop in $ordered) {
        $col = [System.Windows.Controls.GridViewColumn]::new()
        $col.Header = $prop
        $col.DisplayMemberBinding = [System.Windows.Data.Binding]::new($prop)
        $col.Width = if ($widths.ContainsKey($prop)) { $widths[$prop] } else { 100 }
        [void]$gv.Columns.Add($col)
    }
    $syncHash.VersionsListView.View = $gv
    # Clear saved column widths so stale hide/show state from a previous app does not carry over.
    $syncHash.VersionsColSavedWidths = @{}
}
```

### $getAppCacheFile
Returns the cache file path for a given app name, creating the cache directory if needed.
```powershell
$getAppCacheFile = {
    param([string]$AppName)
    $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    Join-Path $cacheDir "$AppName.json"
}
```

### $displayAppResults
Populates the detail panel from a result array (used for both live and cached data).
```powershell
$displayAppResults = {
    param([PSObject[]]$AppResults)
    $syncHash.CurrentAppResults = @($AppResults)
    & $rebuildVersionColumns -AppResults $syncHash.CurrentAppResults
    $filterProps = @(Get-FilterableProperty -AppResults $syncHash.CurrentAppResults)
    New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
        Invoke-FilterUpdate -SyncHash $syncHash
    }
    Invoke-FilterUpdate -SyncHash $syncHash
    $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed
    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
    & $updateAddToLibraryButtonState
}
```

### $updateAddToLibraryButtonState
Enables AddToLibraryButton only when an app is loaded AND a valid EvergreenLibrary.json exists.
```powershell
$updateAddToLibraryButtonState = {
    $appSelected = $null -ne $appsListBox.SelectedItem -and $syncHash.CurrentAppResults.Count -gt 0
    $libraryPath = $syncHash.Config.LibraryPath
    $jsonExists = (-not [string]::IsNullOrWhiteSpace($libraryPath)) -and
    (Test-Path -LiteralPath (Join-Path $libraryPath 'EvergreenLibrary.json'))
    $addToLibraryButton.IsEnabled = $appSelected -and $jsonExists
}
```

### $loadAppVersions
Initiates async load of versions for the selected app via Get-EvergreenApp.
```powershell
$loadAppVersions = {
    $selectedApp = $appsListBox.SelectedItem
    if ($null -eq $selectedApp) {
        Write-UILog -SyncHash $syncHash -Message 'Select an application first.' -Level Warning
        return
    }

    $appName = [string]$selectedApp.Name
    $loadAppVersionsButton.IsEnabled = $false

    # Show loading state
    $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed
    $appDetailLoading.Visibility = [System.Windows.Visibility]::Visible
    $appDetailLoadingLabel.Text = "Retrieving details for $appName `nwith Get-EvergreenApp..."

    Write-UILog -SyncHash $syncHash -Message "Loading versions for $appName..." -Level Info
    Write-UILog -SyncHash $syncHash -Message "Get-EvergreenApp -Name '$appName'" -Level Cmd

    $runspace = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
            param([string]$Name)
            Get-EvergreenApp -Name $Name -ErrorAction Stop
        }).AddArgument($appName)

    $completionAction_Load = {
        param($Operation, $Result, $State)

        $currentAppName = $State.AppName

        try {
            $results = @()
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $results = @($Result.Output)
            }
            elseif ($Result.Error) {
                throw $Result.Error
            }

            # Save results to cache
            $cachePath = & $getAppCacheFile -AppName $currentAppName
            try {
                $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding UTF8 -Force
                $lastWrite = (Get-Item -LiteralPath $cachePath).LastWriteTime.ToString('g')
                $syncHash.AppLastRefreshedLabel.Text = "Last refresh: $lastWrite"
                $syncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Visible
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to write cache for ${currentAppName}: $_" -Level Warning
            }

            & $displayAppResults -AppResults $results

            Write-UILog -SyncHash $syncHash -Message "Loaded $($syncHash.CurrentAppResults.Count) versions for $currentAppName." -Level Info
        }
        catch {
            $syncHash.CurrentAppResults = @()
            $syncHash.VersionsListView.ItemsSource = @()
            $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
            $filterWrapPanel.Children.Clear()

            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible

            Write-UILog -SyncHash $syncHash -Message "Failed to load versions for ${currentAppName}: $_" -Level Error
        }
        finally {
            $loadAppVersionsButton.IsEnabled = $true
        }
    }

    # Store async state in syncHash so the tick handler and cancellation logic can reach it
    $syncHash.PendingLoadPS = $ps
    $syncHash.PendingLoadRunspace = $runspace
    $syncHash.PendingLoadAppName = $appName

    & $registerBackgroundOperation -Feature 'Load' -OperationId 'Evergreen' `
        -PowerShellInstance $ps -RunspaceInstance $runspace `
        -CompletionAction $completionAction_Load -CallbackState @{ AppName = $appName }
}
```

### $applyVersionsListSort
Applies current sort settings to the VersionsListView.
```powershell
$applyVersionsListSort = {
    [void](Set-ListViewSort -ListView $syncHash.VersionsListView -Property ([string]$syncHash.VersionsSortProperty) -Direction ([string]$syncHash.VersionsSortDirection))
}
```

---

## 3. Event Handler Registrations

### RefreshAppsButton.Click
```powershell
$refreshAppsButton.add_Click({
    Write-UILog -SyncHash $syncHash -Message 'Refreshing Evergreen app catalog...' -Level Info
    & $loadAppCatalog -Force
})
```

### AppSearchBox.TextChanged
```powershell
$appSearchBox.add_TextChanged({
    & $updateAppsComboSource -SearchText $appSearchBox.Text
})
```

### AppsListBox - Favourite Star Button Handler (Routed Event)
Captures favourite star button clicks that bubble up from inside the DataTemplate.
```powershell
$appsListBox.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler] {
        param($clickSender, $clickArgs)

        # Walk visual tree to confirm this click originated from FavouriteStarButton
        $element = $clickArgs.OriginalSource -as [System.Windows.DependencyObject]
        $starButton = $null
        while ($null -ne $element) {
            $btn = $element -as [System.Windows.Controls.Button]
            if ($null -ne $btn -and [string]$btn.Name -eq 'FavouriteStarButton') {
                $starButton = $btn
                break
            }
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if ($null -eq $starButton) { return }

        $appName = [string]$starButton.Tag
        if ([string]::IsNullOrEmpty($appName)) { return }

        # Toggle favourite status in config
        $favList = [System.Collections.Generic.List[string]]::new(
            [string[]]@($syncHash.Config.FavouriteApps)
        )
        if ($favList.Contains($appName)) {
            [void]$favList.Remove($appName)
            Write-UILog -SyncHash $syncHash -Message "Removed '$appName' from favourites." -Level Info
        }
        else {
            $favList.Add($appName)
            Write-UILog -SyncHash $syncHash -Message "Added '$appName' to favourites." -Level Info
        }
        $syncHash.Config.FavouriteApps = $favList.ToArray()

        # Persist immediately so the change survives if the window is closed
        Set-UIConfig -Config $syncHash.Config

        # Refresh list: re-stamps IsFavourite on all items and re-sorts
        & $updateAppsComboSource -SearchText $appSearchBox.Text
    }
)
```

### LoadAppVersionsButton.Click
```powershell
$loadAppVersionsButton.add_Click({
    & $loadAppVersions
})
```

### AppsListBox.SelectionChanged
Handles app selection and loads cached versions or clears the detail view.
```powershell
$appsListBox.add_SelectionChanged({
    # Cancel any in-progress version load before starting a new one
    if ($null -ne $syncHash.PendingLoadTimer -and $syncHash.PendingLoadTimer.IsEnabled) {
        $syncHash.PendingLoadTimer.Stop()
        $syncHash.PendingLoadTimer = $null
    }
    if ($null -ne $syncHash.PendingLoadPS) {
        try { $syncHash.PendingLoadPS.Stop() } catch {}
        try { $syncHash.PendingLoadPS.Dispose() } catch {}
        $syncHash.PendingLoadPS = $null
    }
    if ($null -ne $syncHash.PendingLoadRunspace) {
        try { $syncHash.PendingLoadRunspace.Dispose() } catch {}
        $syncHash.PendingLoadRunspace = $null
    }
    $syncHash.PendingLoadAsync = $null
    $syncHash.PendingLoadAppName = $null

    $syncHash.CurrentAppResults = @()
    $syncHash.VersionsListView.ItemsSource = @()
    $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
    $filterWrapPanel.Children.Clear()
    $syncHash.FilterState = @{}
    $addToLibraryButton.IsEnabled = $false
    if ($null -ne $appsActionStatusLabel) { $appsActionStatusLabel.Text = '' }

    $selectedApp = $appsListBox.SelectedItem
    if ($null -ne $selectedApp) {
        $appDetailTitle.Text = "$($selectedApp.Name)"

        # Load from cache if available; otherwise show the panel empty (user clicks Refresh)
        $cachePath = & $getAppCacheFile -AppName $selectedApp.Name
        if (Test-Path -LiteralPath $cachePath) {
            $lastWrite = (Get-Item -LiteralPath $cachePath).LastWriteTime.ToString('g')
            $syncHash.AppLastRefreshedLabel.Text = "Last refresh: $lastWrite"
            $syncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Visible
            try {
                $rawJson = Get-Content -LiteralPath $cachePath -Raw
                $parsed = ConvertFrom-Json -InputObject $rawJson
                # Guard against double-wrapping: @() can treat the Object[] returned by
                # ConvertFrom-Json as a single item in certain PS/WPF execution contexts,
                # producing Object[]{ Object[]{realItems} }. Detect and flatten one level.
                $cachedResults = if ($parsed -is [System.Array] -and
                    $parsed.Count -gt 0 -and
                    $parsed[0] -is [System.Array]) {
                    [object[]]$parsed[0]
                }
                elseif ($parsed -is [System.Array]) {
                    [object[]]$parsed
                }
                else {
                    @($parsed)
                }
                Write-UILog -SyncHash $syncHash -Message "Loaded $($cachedResults.Count) cached versions for $($selectedApp.Name)." -Level Info
                & $displayAppResults -AppResults $cachedResults
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Cache read failed for $($selectedApp.Name), click Refresh to load: $_" -Level Warning
                $filterWrapPanel.Children.Clear()
                $syncHash.FilterState = @{}
                $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed
                $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
            }
        }
        else {
            $syncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
        }
    }
    else {
        $syncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Collapsed
        $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible
        $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed
        $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
    }
})
```

### VersionsListView - Column Sorting (Routed Event)
```powershell
$syncHash.VersionsListView.AddHandler(
    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [System.Windows.RoutedEventHandler] {
        param($eventSender, $routedEventArgs)

        $header = $routedEventArgs.OriginalSource -as [System.Windows.Controls.GridViewColumnHeader]
        if ($null -eq $header -or $null -eq $header.Column) {
            return
        }

        if ($header.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Padding) {
            return
        }

        $sortProperty = ''
        $binding = $header.Column.DisplayMemberBinding -as [System.Windows.Data.Binding]
        if ($null -ne $binding -and $null -ne $binding.Path) {
            $sortProperty = [string]$binding.Path.Path
        }

        if ([string]::IsNullOrWhiteSpace($sortProperty)) {
            return
        }

        $newDirection = 'Ascending'
        if ([string]$syncHash.VersionsSortProperty -eq $sortProperty -and [string]$syncHash.VersionsSortDirection -eq 'Ascending') {
            $newDirection = 'Descending'
        }

        $syncHash.VersionsSortProperty = $sortProperty
        $syncHash.VersionsSortDirection = $newDirection

        & $applyVersionsListSort
    }
)
```

### VersionsListView - Right-Click Column Menu (PreviewMouseRightButtonDown)
Right-click on a column header shows a context menu to show or hide that column.
Version and URI are structural columns and cannot be hidden.
```powershell
$syncHash.VersionsListView.add_PreviewMouseRightButtonDown({
    param($eventSender, $routedEventArgs)

    # Walk the visual tree from the click source to find a GridViewColumnHeader.
    $element = $routedEventArgs.OriginalSource -as [System.Windows.DependencyObject]
    $colHeader = $null
    while ($null -ne $element) {
        if ($element -is [System.Windows.Controls.GridViewColumnHeader]) {
            $colHeader = $element
            break
        }
        $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
    }

    # Ignore clicks on the padding filler header at the far right.
    if ($null -eq $colHeader -or $null -eq $colHeader.Column) { return }
    if ($colHeader.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Padding) { return }

    $gv = $syncHash.VersionsListView.View -as [System.Windows.Controls.GridView]
    if ($null -eq $gv -or $gv.Columns.Count -eq 0) { return }

    $nonToggleable = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('Version', 'URI'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $menu = [System.Windows.Controls.ContextMenu]::new()
    $menuStyle = $syncHash.Window.TryFindResource('FluentContextMenu')
    if ($null -ne $menuStyle) {
        $menu.Style = $menuStyle
    }
    $hasToggleableColumns = $false
    foreach ($col in $gv.Columns) {
        $propName = $col.Header -as [string]
        if ([string]::IsNullOrEmpty($propName)) { continue }
        if ($nonToggleable.Contains($propName)) { continue }

        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = $propName
        $item.IsCheckable = $true
        $item.IsChecked = ($col.Width -gt 0)
        $menuItemStyle = $syncHash.Window.TryFindResource('FluentMenuItem')
        if ($null -ne $menuItemStyle) {
            $item.Style = $menuItemStyle
        }
        # Store the column reference in Tag so the click handler can retrieve it
        # without relying on loop-variable closure behaviour.
        $item.Tag = $col
        $item.add_Click({
            param($clickSender, $clickArgs)
            $theCol = $clickSender.Tag -as [System.Windows.Controls.GridViewColumn]
            if ($null -eq $theCol) { return }
            $colName = [string]$theCol.Header
            if ($theCol.Width -gt 0) {
                # Visible: save current width then collapse to zero.
                $syncHash.VersionsColSavedWidths[$colName] = $theCol.Width
                $theCol.Width = 0
            }
            else {
                # Hidden: restore the saved width.
                $restoreWidth = if ($syncHash.VersionsColSavedWidths.ContainsKey($colName)) {
                    $syncHash.VersionsColSavedWidths[$colName]
                }
                else {
                    100
                }
                $theCol.Width = $restoreWidth
            }
        })

        [void]$menu.Items.Add($item)
        $hasToggleableColumns = $true
    }

    if (-not $hasToggleableColumns) { return }

    $menu.PlacementTarget = $colHeader
    $menu.IsOpen = $true
    $routedEventArgs.Handled = $true
})
```

### ClearFiltersButton.Click
```powershell
$clearFiltersButton.add_Click({
    if ($null -eq $syncHash.CurrentAppResults -or $syncHash.CurrentAppResults.Count -eq 0) {
        return
    }

    $filterProps = Get-FilterableProperty -AppResults $syncHash.CurrentAppResults
    New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
        Invoke-FilterUpdate -SyncHash $syncHash
    }
    Invoke-FilterUpdate -SyncHash $syncHash
})
```

### ExportCsvButton.Click
```powershell
$exportCsvButton.add_Click({
    $selectedApp = $appsListBox.SelectedItem
    $items = @($syncHash.VersionsListView.Items)

    if ($null -eq $selectedApp -or $items.Count -eq 0) {
        Write-UILog -SyncHash $syncHash -Message 'No version data to export. Load an app first.' -Level Warning
        return
    }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = 'Export to CSV'
    $dlg.FileName = "$($selectedApp.Name).csv"
    $dlg.DefaultExt = '.csv'
    $dlg.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'

    if ($dlg.ShowDialog() -eq $true) {
        try {
            $items | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            Write-UILog -SyncHash $syncHash -Message "Exported $($items.Count) rows to $($dlg.FileName)" -Level Info
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Export failed: $_" -Level Error
        }
    }
})
```

### AddToLibraryButton.Click
```powershell
$addToLibraryButton.add_Click({
    $selectedApp = $appsListBox.SelectedItem
    $libraryPath = $syncHash.Config.LibraryPath
    $libraryJsonPath = Join-Path -Path $libraryPath -ChildPath 'EvergreenLibrary.json'

    if ($null -eq $selectedApp -or [string]::IsNullOrWhiteSpace($libraryPath)) {
        Write-UILog -SyncHash $syncHash -Message 'Select an application and ensure a library path is configured.' -Level Warning
        return
    }
    if (-not (Test-Path -LiteralPath $libraryJsonPath)) {
        Write-UILog -SyncHash $syncHash -Message "EvergreenLibrary.json not found at: $libraryPath" -Level Error
        return
    }

    # Build filter string from FilterState - skip synthetic _DerivedType property.
    $filterClauses = @()
    foreach ($propName in $syncHash.FilterState.Keys) {
        if ($propName -eq '_DerivedType') { continue }

        $selected = @($syncHash.FilterState[$propName])
        $allValues = @($syncHash.CurrentAppResults |
            Select-Object -ExpandProperty $propName -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_ } |
            Sort-Object -Unique)

        # All values selected means no restriction on this property
        if ($selected.Count -ge $allValues.Count) { continue }

        if ($selected.Count -eq 1) {
            $filterClauses += "`$_.$propName -eq `"$($selected[0])`""
        }
        else {
            $orParts = $selected | ForEach-Object { "`$_.$propName -eq `"$_`"" }
            $filterClauses += "($($orParts -join ' -or '))"
        }
    }
    $filterString = $filterClauses -join ' -and '

    try {
        $raw = Get-Content -LiteralPath $libraryJsonPath -Raw -Encoding UTF8
        $libraryRoot = ConvertFrom-Json -InputObject $raw
    }
    catch {
        Write-UILog -SyncHash $syncHash -Message "Failed to read EvergreenLibrary.json: $_" -Level Error
        return
    }

    $appName = [string]$selectedApp.Name

    # EvergreenLibrary.json has a root wrapper object with an Applications array.
    # Locate that wrapper and update its Applications list.
    $wrapper = $libraryRoot | Where-Object { $_.PSObject.Properties.Name -contains 'Applications' } | Select-Object -First 1
    if ($null -eq $wrapper) {
        Write-UILog -SyncHash $syncHash -Message 'EvergreenLibrary.json does not contain an Applications array. Cannot add entry.' -Level Error
        return
    }

    $newEntry = [PSCustomObject]@{
        Name         = $appName
        EvergreenApp = $appName
        Filter       = $filterString
    }

    # Overwrite any existing entry for this app, then append the new one
    $wrapper.Applications = @($wrapper.Applications | Where-Object { $_.Name -ne $appName }) + $newEntry

    try {
        $libraryRoot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $libraryJsonPath -Encoding UTF8
        Write-UILog -SyncHash $syncHash -Message "Added '$appName' to library (filter: '$filterString')." -Level Info

        # Show inline success feedback and auto-clear after 3 seconds
        if ($null -ne $appsActionStatusLabel) {
            $appsActionStatusLabel.Foreground = & $getThemeStatusBrush -ResourceKey 'StatusPositiveBrush' -FallbackBrush ([System.Windows.Media.Brushes]::LightGreen)
            $appsActionStatusLabel.Text = "Added '$appName' to library"
            $clearTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $clearTimer.Interval = [TimeSpan]::FromSeconds(3)
            $clearTimer.add_Tick({
                $appsActionStatusLabel.Text = ''
                $clearTimer.Stop()
            }.GetNewClosure())
            $clearTimer.Start()
        }
    }
    catch {
        Write-UILog -SyncHash $syncHash -Message "Failed to write EvergreenLibrary.json: $_" -Level Error
        if ($null -ne $appsActionStatusLabel) {
            $appsActionStatusLabel.Foreground = & $getThemeStatusBrush -ResourceKey 'StatusErrorBrush' -FallbackBrush ([System.Windows.Media.Brushes]::OrangeRed)
            $appsActionStatusLabel.Text = "Failed to update library"
        }
    }
})
```

### AddToQueueButton.Click
```powershell
$addToQueueButton.add_Click({
    $selectedApp = $appsListBox.SelectedItem
    $selectedVersions = @($syncHash.VersionsListView.SelectedItems)

    if ($null -eq $selectedApp -or $selectedVersions.Count -eq 0) {
        Write-UILog -SyncHash $syncHash -Message 'Select one or more version rows before adding to queue.' -Level Warning
        return
    }

    foreach ($selectedVersion in $selectedVersions) {
        $queueItem = [PSCustomObject]@{
            AppName          = [string]$selectedApp.Name
            Version          = if ($selectedVersion.PSObject.Properties.Name -contains 'Version') { [string]$selectedVersion.Version } else { '' }
            Platform         = if ($selectedVersion.PSObject.Properties.Name -contains 'Platform') { [string]$selectedVersion.Platform } else { '' }
            Architecture     = if ($selectedVersion.PSObject.Properties.Name -contains 'Architecture') { [string]$selectedVersion.Architecture } else { '' }
            Channel          = if ($selectedVersion.PSObject.Properties.Name -contains 'Channel') { [string]$selectedVersion.Channel } else { '' }
            Uri              = if ($selectedVersion.PSObject.Properties.Name -contains 'URI') { [string]$selectedVersion.URI } else { '' }
            Status           = 'Pending'
            Path             = ''
            SourceProperties = $selectedVersion
        }

        $isDuplicate = $syncHash.DownloadQueue | Where-Object { $_.Uri -eq $queueItem.Uri }
        if ($isDuplicate) {
            Write-UILog -SyncHash $syncHash -Message "Already queued: $($queueItem.AppName) $($queueItem.Version)" -Level Warning
            continue
        }

        $syncHash.DownloadQueue.Add($queueItem)
        Write-UILog -SyncHash $syncHash -Message "Queued: $($queueItem.AppName) $($queueItem.Version)" -Level Info
    }
    & $refreshQueueView
})
```

---

## 4. Dependencies

### Helper Functions Called
- `Get-EvergreenAppList` - Retrieves and caches the Evergreen app catalog
- `Get-FilterableProperty` - Determines which app properties can be filtered
- `New-FilterPanel` - Dynamically builds filter UI from app properties
- `Invoke-FilterUpdate` - Applies current filter selections to version results
- `Set-ListViewSort` - Applies sort to ListView based on column selection
- `New-WpfRunspace` - Creates STA runspace for async operations
- `Write-UILog` - Thread-safe UI logging
- `Set-UIConfig` - Persists configuration to disk

### Control Dependencies
- `AppsPanel` - Top-level container for Apps view
- `AppsListBox.ItemsSource` - Populated by `$updateAppsComboSource`
- `VersionsListView.ItemsSource` - Populated by `$displayAppResults`
- `FilterWrapPanel.Children` - Populated by `New-FilterPanel`
- Event handlers for column visibility and sorting

### SyncHash Dependencies
- `$syncHash.AppList` - Full app catalog (populated by Get-EvergreenAppList)
- `$syncHash.Config` - User configuration and favourites
- `$syncHash.DownloadQueue` - Download queue (shared with Download feature)
- `$syncHash.Window` - Main window reference
- `$syncHash.ActiveBackgroundOperations` - Async operation tracking

---

## 5. Implementation Notes for Register-AppsFeature.ps1

1. **Initialization Order**: Control references must be loaded before scriptblocks that use them
2. **State Variables**: Initialize all `$syncHash.*` properties in the feature setup
3. **Helper Dependencies**: The `$registerBackgroundOperation` scriptblock is used by `$loadAppVersions` and must be available (may be shared across features)
4. **Event Handler Pattern**: Use `.add_Click()`, `.add_TextChanged()`, `.AddHandler()` for different event types
5. **Closure Context**: Store values in `$syncHash` or use `.GetNewClosure()` for timer-based callbacks
6. **Resource Access**: Theme brushes (StatusPositiveBrush, StatusErrorBrush) are accessed via `$syncHash.Window.TryFindResource()`
7. **Thread Safety**: All UI updates from background operations must use `$syncHash` and dispatcher invocation
8. **Cache Management**: App version cache is stored in `$env:APPDATA\EvergreenUI\cache\` directory

---

## 6. XAML Control Structure Reference

Expected XAML controls and their roles:
```
AppsPanel
├── RefreshAppsButton (Click to reload catalog)
├── AppSearchBox (TextChanged to filter apps)
├── AppsListBox (displays sorted app list)
│   ├── FavouriteStarButton (DataTemplate routed click)
│   └── ItemsSource = $updateAppsComboSource output
├── LoadAppVersionsButton (Click to load versions)
├── ClearFiltersButton (Click to reset filters)
├── ExportCsvButton (Click to export CSV)
├── AddToLibraryButton (Click to add to library)
├── AddToQueueButton (Click to queue downloads)
├── AppsActionStatusLabel (displays operation feedback)
├── AppDetailEmpty (Visibility when no selection)
├── AppDetailLoading (Visibility during load)
├── AppDetailContent (Visibility when data available)
│   ├── AppDetailTitle (app name)
│   ├── FilterWrapPanel (dynamic filter controls)
│   ├── VersionsListView (version results with columns)
│   ├── ResultsCountLabel (result count)
│   └── AppLastRefreshedLabel (cache timestamp)
└── AppCountLabel (total/filtered count)
```
