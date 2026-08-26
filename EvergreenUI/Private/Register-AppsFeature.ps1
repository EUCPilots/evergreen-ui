function Register-AppsFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Apps browse and version loading feature.

    .DESCRIPTION
    Sets up event handlers for the Apps navigation view, including app catalog loading,
    search/filtering, version loading with caching, favorite app management, version column
    visibility toggling, filtering, CSV export, library integration, and queue management.
    Manages async operations via New-WpfRunspace for responsive UI.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Apps feature.

    .PARAMETER RegisterBackgroundOperation
    Scriptblock to register background async operations with completion handlers.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    Handles app catalog cache, version loading cache, filter panel creation, and column visibility persistence.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls,
        [scriptblock]$RegisterBackgroundOperation
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls
    $appSearchBox = $Controls.AppSearchBox
    $appsListBox = $Controls.AppsListBox
    $filterWrapPanel = $Controls.FilterWrapPanel
    $appCountLabel = $Controls.AppCountLabel
    $appDetailEmpty = $Controls.AppDetailEmpty
    $appDetailLoading = $Controls.AppDetailLoading
    $appDetailLoadingLabel = $Controls.AppDetailLoadingLabel
    $appDetailContent = $Controls.AppDetailContent
    $appDetailTitle = $Controls.AppDetailTitle
    $refreshAppsButton = $Controls.RefreshAppsButton
    $loadAppVersionsButton = $Controls.LoadAppVersionsButton
    $clearFiltersButton = $Controls.ClearFiltersButton
    $exportCsvButton = $Controls.ExportCsvButton
    $addToLibraryButton = $Controls.AddToLibraryButton
    $addToQueueButton = $Controls.AddToQueueButton
    $appsActionStatusLabel = $Controls.AppsActionStatusLabel
    $getEvergreenAppList = ${function:Get-EvergreenAppList}.GetNewClosure()

    # Verify required controls exist
    if ($null -eq $SyncHash.VersionsListView) {
        Write-Verbose 'EvergreenUI: VersionsListView not found; Apps feature registration skipped.'
        return
    }

    # Helper scriptblock: Normalize directory path (trim whitespace and quotes)
    $normalizeDirectoryPath = {
        param([string]$PathValue)

        if ([string]::IsNullOrWhiteSpace($PathValue)) {
            return ''
        }

        return $PathValue.Trim().Trim('"')
    }

    # Helper scriptblock: Update AppsListBox ItemsSource with search and sort
    $updateAppsComboSource = {
        param([string]$SearchText = '')

        $allApps = @($SyncHash.AppList)
        if ($allApps.Count -eq 0) {
            if ($null -ne $appsListBox) { $appsListBox.ItemsSource = @() }
            if ($null -ne $appCountLabel) { $appCountLabel.Text = '' }
            return
        }

        # Stamp IsFavourite on each item based on current config
        $favouriteSet = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($SyncHash.Config.FavouriteApps),
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

        if ($null -ne $appsListBox) { $appsListBox.ItemsSource = $sorted }
        if ($null -ne $appCountLabel) { $appCountLabel.Text = " $($sorted.Count) of $($allApps.Count)" }
    }.GetNewClosure()

    # Helper scriptblock: Load app catalog (with optional force refresh)
    $loadAppCatalog = {
        param([switch]$Force)

        if ($null -ne $refreshAppsButton) { $refreshAppsButton.IsEnabled = $false }
        try {
            [void](& $getEvergreenAppList -SyncHash $SyncHash -Force:$Force)
            & $updateAppsComboSource -SearchText $(if ($null -ne $appSearchBox) { $appSearchBox.Text } else { '' })
        }
        finally {
            if ($null -ne $refreshAppsButton) { $refreshAppsButton.IsEnabled = $true }
        }
    }

    # Helper scriptblock: Rebuild VersionsListView GridView columns based on app result properties
    $rebuildVersionColumns = {
        param([PSObject[]]$AppResults)

        if ($null -eq $AppResults -or $AppResults.Count -eq 0) { return }

        # Guard against double-wrapped data
        if ($AppResults[0] -is [System.Array]) {
            $AppResults = @($AppResults[0])
            if ($AppResults.Count -eq 0) { return }
        }

        $allProps = [string[]]$AppResults[0].PSObject.Properties.Name

        # Well-known preferred widths for common columns
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
        $SyncHash.VersionsListView.View = $gv
        # Clear saved column widths so stale hide/show state from a previous app does not carry over.
        $SyncHash.VersionsColSavedWidths = @{}
    }

    # Helper scriptblock: Get cache file path for an app (creates cache directory if needed)
    $getAppCacheFile = {
        param([string]$AppName)
        $cacheDir = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\cache'
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            $null = New-Item -ItemType Directory -Path $cacheDir -Force
        }
        Join-Path -Path $cacheDir -ChildPath "$AppName.json"
    }

    # Helper scriptblock: Display app results (updates version list, filter panel, visibility)
    $displayAppResults = {
        param([PSObject[]]$AppResults)
        $SyncHash.CurrentAppResults = @($AppResults)
        & $rebuildVersionColumns -AppResults $SyncHash.CurrentAppResults
        $filterProps = @(Get-FilterableProperty -AppResults $SyncHash.CurrentAppResults)
        New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $SyncHash -OnChangeCallback {
            Invoke-FilterUpdate -SyncHash $SyncHash
        }
        Invoke-FilterUpdate -SyncHash $SyncHash
        if ($null -ne $appDetailEmpty) { $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($null -ne $appDetailContent) { $appDetailContent.Visibility = [System.Windows.Visibility]::Visible }
        & $updateAddToLibraryButtonState
    }

    # Helper scriptblock: Enable AddToLibraryButton only when app is loaded AND valid EvergreenLibrary.json exists
    $updateAddToLibraryButtonState = {
        if ($null -eq $addToLibraryButton) { return }

        $appSelected = $null -ne $appsListBox.SelectedItem -and $SyncHash.CurrentAppResults.Count -gt 0
        $libraryPath = $SyncHash.Config.LibraryPath
        $jsonExists = (-not [string]::IsNullOrWhiteSpace($libraryPath)) -and
        (Test-Path -LiteralPath (Join-Path -Path $libraryPath -ChildPath 'EvergreenLibrary.json'))
        $addToLibraryButton.IsEnabled = $appSelected -and $jsonExists
    }

    # Helper scriptblock: Apply sort to versions list
    $applyVersionsListSort = {
        [void](Set-ListViewSort -ListView $SyncHash.VersionsListView `
            -Property ([string]$SyncHash.VersionsSortProperty) `
            -Direction ([string]$SyncHash.VersionsSortDirection))
    }

    # Helper scriptblock: Load versions for selected app (async with cache)
    $loadAppVersions = {
        $selectedApp = $appsListBox.SelectedItem
        if ($null -eq $selectedApp) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Select an application first.' -Level Warning
            return
        }

        $appName = [string]$selectedApp.Name
        if ($null -ne $loadAppVersionsButton) { $loadAppVersionsButton.IsEnabled = $false }

        # Show loading state
        if ($null -ne $appDetailContent) { $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Visible }
        if ($null -ne $appDetailLoadingLabel) { $appDetailLoadingLabel.Text = "Retrieving details for $appName `nwith Get-EvergreenApp..." }

        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Loading versions for $appName..." -Level Info
        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Get-EvergreenApp -Name '$appName'" -Level Cmd

        $runspace = New-WpfRunspace -SyncHash $SyncHash
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
                    if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Text = "Last refresh: $lastWrite" }
                    if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Visible }
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Cached $($results.Count) versions for $currentAppName." -Level Info
                }
                catch {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to write cache for ${currentAppName}: $_" -Level Warning
                }

                & $displayAppResults -AppResults $results

                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Loaded $($SyncHash.CurrentAppResults.Count) versions for $currentAppName." -Level Info
            }
            catch {
                $SyncHash.CurrentAppResults = @()
                if ($null -ne $SyncHash.VersionsListView) { $SyncHash.VersionsListView.ItemsSource = @() }
                if ($null -ne $SyncHash.ResultsCountLabel) { $SyncHash.ResultsCountLabel.Text = 'Showing 0 of 0' }
                if ($null -ne $filterWrapPanel) { $filterWrapPanel.Children.Clear() }

                if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed }
                if ($null -ne $appDetailEmpty) { $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible }

                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to load versions for ${currentAppName}: $_" -Level Error
            }
            finally {
                if ($null -ne $loadAppVersionsButton) { $loadAppVersionsButton.IsEnabled = $true }
            }
        }

        # Store async state in syncHash so the tick handler and cancellation logic can reach it
        $SyncHash.PendingLoadPS = $ps
        $SyncHash.PendingLoadRunspace = $runspace
        $SyncHash.PendingLoadAppName = $appName

        & $RegisterBackgroundOperation -Feature 'Load' -OperationId 'Evergreen' `
            -PowerShellInstance $ps -RunspaceInstance $runspace `
            -CompletionAction $completionAction_Load -CallbackState @{ AppName = $appName }
    }

    # Store helper scriptblocks in SyncHash for access by other features
    $SyncHash['UpdateAppsComboSource'] = $updateAppsComboSource.GetNewClosure()
    $SyncHash['LoadAppCatalog'] = $loadAppCatalog.GetNewClosure()
    $SyncHash['RebuildVersionColumns'] = $rebuildVersionColumns.GetNewClosure()
    $SyncHash['GetAppCacheFile'] = $getAppCacheFile.GetNewClosure()
    $SyncHash['DisplayAppResults'] = $displayAppResults.GetNewClosure()
    $SyncHash['UpdateAddToLibraryButtonState'] = $updateAddToLibraryButtonState.GetNewClosure()
    $SyncHash['LoadAppVersions'] = $loadAppVersions.GetNewClosure()
    $SyncHash['ApplyVersionsListSort'] = $applyVersionsListSort.GetNewClosure()

    # Event handler: RefreshAppsButton - Force refresh app catalog
    if ($null -ne $refreshAppsButton) {
        $refreshAppsButton.add_Click({
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Refreshing Evergreen app catalog...' -Level Info
                & $loadAppCatalog -Force
            }.GetNewClosure())
    }

    # Event handler: AppSearchBox.TextChanged - Update list as user types
    if ($null -ne $appSearchBox) {
        $appSearchBox.add_TextChanged({
                & $updateAppsComboSource -SearchText $appSearchBox.Text
            }.GetNewClosure())
    }

    # Event handler: FavouriteStarButton clicks in AppsListBox DataTemplate
    # These bubble up from inside the template, so capture with routed event handler
    if ($null -ne $appsListBox) {
        $appsListBox.AddHandler(
            [System.Windows.Controls.Button]::ClickEvent,
            [System.Windows.RoutedEventHandler]({
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
                    [string[]]@($SyncHash.Config.FavouriteApps)
                )
                if ($favList.Contains($appName)) {
                    [void]$favList.Remove($appName)
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Removed '$appName' from favourites." -Level Info
                }
                else {
                    $favList.Add($appName)
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Added '$appName' to favourites." -Level Info
                }
                $SyncHash.Config.FavouriteApps = $favList.ToArray()

                # Persist immediately so the change survives if the window is closed
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

                # Refresh list: re-stamps IsFavourite on all items and re-sorts
                & $updateAppsComboSource -SearchText $appSearchBox.Text
            }.GetNewClosure())
        )
    }

    # Event handler: LoadAppVersionsButton - Load selected app's versions
    if ($null -ne $loadAppVersionsButton) {
        $loadAppVersionsButton.add_Click({
                & $loadAppVersions
            }.GetNewClosure())
    }

    # Event handler: AppsListBox.SelectionChanged - Handle app selection
    if ($null -ne $appsListBox) {
        $appsListBox.add_SelectionChanged({
                # Cancel any in-progress version load before starting a new one
                if ($null -ne $SyncHash.PendingLoadTimer -and $SyncHash.PendingLoadTimer.IsEnabled) {
                    $SyncHash.PendingLoadTimer.Stop()
                    $SyncHash.PendingLoadTimer = $null
                }
                if ($null -ne $SyncHash.PendingLoadPS) {
                    try { $SyncHash.PendingLoadPS.Stop() } catch {}
                    try { $SyncHash.PendingLoadPS.Dispose() } catch {}
                    $SyncHash.PendingLoadPS = $null
                }
                if ($null -ne $SyncHash.PendingLoadRunspace) {
                    try { $SyncHash.PendingLoadRunspace.Dispose() } catch {}
                    $SyncHash.PendingLoadRunspace = $null
                }
                $SyncHash.PendingLoadAsync = $null
                $SyncHash.PendingLoadAppName = $null

                $SyncHash.CurrentAppResults = @()
                if ($null -ne $SyncHash.VersionsListView) { $SyncHash.VersionsListView.ItemsSource = @() }
                if ($null -ne $SyncHash.ResultsCountLabel) { $SyncHash.ResultsCountLabel.Text = 'Showing 0 of 0' }
                if ($null -ne $filterWrapPanel) { $filterWrapPanel.Children.Clear() }
                $SyncHash.FilterState = @{}
                if ($null -ne $addToLibraryButton) { $addToLibraryButton.IsEnabled = $false }
                if ($null -ne $appsActionStatusLabel) { $appsActionStatusLabel.Text = '' }

                $selectedApp = $appsListBox.SelectedItem
                if ($null -ne $selectedApp) {
                    if ($null -ne $appDetailTitle) { $appDetailTitle.Text = "$($selectedApp.Name)" }

                    # Load from cache if available; otherwise show the panel empty (user clicks Refresh)
                    $cachePath = & $getAppCacheFile -AppName $selectedApp.Name
                    if (Test-Path -LiteralPath $cachePath) {
                        $lastWrite = (Get-Item -LiteralPath $cachePath).LastWriteTime.ToString('g')
                        if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Text = "Last refresh: $lastWrite" }
                        if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Visible }
                        try {
                            $rawJson = Get-Content -LiteralPath $cachePath -Raw
                            $parsed = ConvertFrom-Json -InputObject $rawJson
                            # Guard against double-wrapping
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
                            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Loaded $($cachedResults.Count) cached versions for $($selectedApp.Name)." -Level Info
                            & $displayAppResults -AppResults $cachedResults
                        }
                        catch {
                            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Cache read failed for $($selectedApp.Name), click Refresh to load: $_" -Level Warning
                            if ($null -ne $filterWrapPanel) { $filterWrapPanel.Children.Clear() }
                            $SyncHash.FilterState = @{}
                            if ($null -ne $appDetailEmpty) { $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed }
                            if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed }
                            if ($null -ne $appDetailContent) { $appDetailContent.Visibility = [System.Windows.Visibility]::Visible }
                        }
                    }
                    else {
                        if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($null -ne $appDetailEmpty) { $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($null -ne $appDetailContent) { $appDetailContent.Visibility = [System.Windows.Visibility]::Visible }
                    }
                }
                else {
                    if ($null -ne $SyncHash.AppLastRefreshedLabel) { $SyncHash.AppLastRefreshedLabel.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($null -ne $appDetailEmpty) { $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible }
                    if ($null -ne $appDetailContent) { $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($null -ne $appDetailLoading) { $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed }
                }
            }.GetNewClosure())
    }

    # Event handler: VersionsListView column header click (sorting)
    $SyncHash.VersionsListView.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]({
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
            if ([string]$SyncHash.VersionsSortProperty -eq $sortProperty -and [string]$SyncHash.VersionsSortDirection -eq 'Ascending') {
                $newDirection = 'Descending'
            }

            $SyncHash.VersionsSortProperty = $sortProperty
            $SyncHash.VersionsSortDirection = $newDirection

            & $applyVersionsListSort
        }.GetNewClosure())
    )

    # Event handler: VersionsListView column header right-click (show/hide columns)
    $SyncHash.VersionsListView.AddHandler(
        [System.Windows.UIElement]::PreviewMouseRightButtonDownEvent,
        [System.Windows.Input.MouseButtonEventHandler]({
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

            $gv = $SyncHash.VersionsListView.View -as [System.Windows.Controls.GridView]
            if ($null -eq $gv -or $gv.Columns.Count -eq 0) { return }

            $nonToggleable = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('Version', 'URI'),
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $menu = [System.Windows.Controls.ContextMenu]::new()
            $menuStyle = $SyncHash.Window.TryFindResource('FluentContextMenu')
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
                $menuItemStyle = $SyncHash.Window.TryFindResource('FluentMenuItem')
                if ($null -ne $menuItemStyle) {
                    $item.Style = $menuItemStyle
                }
                # Store the column reference in Tag so the click handler can retrieve it
                # without relying on loop-variable closure behaviour.
                $item.Tag = $col
                $item.add_Click({
                        param($clickSender, $clickArgs)
                        [void]$clickArgs
                        $theCol = $clickSender.Tag -as [System.Windows.Controls.GridViewColumn]
                        if ($null -eq $theCol) { return }
                        $colName = [string]$theCol.Header
                        if ($theCol.Width -gt 0) {
                            # Visible: save current width then collapse to zero.
                            $SyncHash.VersionsColSavedWidths[$colName] = $theCol.Width
                            $theCol.Width = 0
                        }
                        else {
                            # Hidden: restore the saved width.
                            $restoreWidth = if ($SyncHash.VersionsColSavedWidths.ContainsKey($colName)) {
                                $SyncHash.VersionsColSavedWidths[$colName]
                            }
                            else {
                                100
                            }
                            $theCol.Width = $restoreWidth
                        }
                    }.GetNewClosure())

                [void]$menu.Items.Add($item)
                $hasToggleableColumns = $true
            }

            if (-not $hasToggleableColumns) { return }

            $menu.PlacementTarget = $colHeader
            $menu.IsOpen = $true
            $routedEventArgs.Handled = $true
        }.GetNewClosure()),
        $true
    )

    # Event handler: ClearFiltersButton - Reset all filters
    if ($null -ne $clearFiltersButton) {
        $clearFiltersButton.add_Click({
                if ($null -eq $SyncHash.CurrentAppResults -or $SyncHash.CurrentAppResults.Count -eq 0) {
                    return
                }

                $filterProps = Get-FilterableProperty -AppResults $SyncHash.CurrentAppResults
                New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $SyncHash -OnChangeCallback {
                    Invoke-FilterUpdate -SyncHash $SyncHash
                }
                Invoke-FilterUpdate -SyncHash $SyncHash
            }.GetNewClosure())
    }

    # Event handler: ExportCsvButton - Export versions to CSV
    if ($null -ne $exportCsvButton) {
        $exportCsvButton.add_Click({
                $selectedApp = $appsListBox.SelectedItem
                $items = @($SyncHash.VersionsListView.Items)

                if ($null -eq $selectedApp -or $items.Count -eq 0) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'No version data to export. Load an app first.' -Level Warning
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
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Exported $($items.Count) rows to $($dlg.FileName)" -Level Info
                    }
                    catch {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Export failed: $_" -Level Error
                    }
                }
            }.GetNewClosure())
    }

    # Event handler: AddToLibraryButton - Add current app with filter to EvergreenLibrary.json
    if ($null -ne $addToLibraryButton) {
        $addToLibraryButton.add_Click({
                $selectedApp = $appsListBox.SelectedItem
                $libraryPath = $SyncHash.Config.LibraryPath
                $libraryJsonPath = Join-Path -Path $libraryPath -ChildPath 'EvergreenLibrary.json'

                if ($null -eq $selectedApp -or [string]::IsNullOrWhiteSpace($libraryPath)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Select an application and ensure a library path is configured.' -Level Warning
                    return
                }
                if (-not (Test-Path -LiteralPath $libraryJsonPath)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "EvergreenLibrary.json not found at: $libraryPath" -Level Error
                    return
                }

                # Build filter string from FilterState - skip synthetic _DerivedType property.
                $filterClauses = @()
                foreach ($propName in $SyncHash.FilterState.Keys) {
                    if ($propName -eq '_DerivedType') { continue }

                    $selected = @($SyncHash.FilterState[$propName])
                    $allValues = @($SyncHash.CurrentAppResults |
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
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to read EvergreenLibrary.json: $_" -Level Error
                    return
                }

                $appName = [string]$selectedApp.Name

                # EvergreenLibrary.json has a root wrapper object with an Applications array.
                $wrapper = $libraryRoot | Where-Object { $_.PSObject.Properties.Name -contains 'Applications' } | Select-Object -First 1
                if ($null -eq $wrapper) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'EvergreenLibrary.json does not contain an Applications array. Cannot add entry.' -Level Error
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
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Added '$appName' to library (filter: '$filterString')." -Level Info

                    # Show inline success feedback and auto-clear after 3 seconds
                    if ($null -ne $appsActionStatusLabel) {
                        $getThemeStatusBrush = {
                            param(
                                [Parameter(Mandatory = $true)]
                                [string]$ResourceKey,

                                [Parameter(Mandatory = $true)]
                                [System.Windows.Media.Brush]$FallbackBrush
                            )

                            $themeBrush = $null
                            if ($null -ne $SyncHash.Window -and $null -ne $SyncHash.Window.Resources -and $SyncHash.Window.Resources.Contains($ResourceKey)) {
                                $candidate = $SyncHash.Window.Resources[$ResourceKey]
                                if ($candidate -is [System.Windows.Media.Brush]) {
                                    $themeBrush = [System.Windows.Media.Brush]$candidate
                                }
                            }

                            if ($null -ne $themeBrush) {
                                return $themeBrush
                            }

                            return $FallbackBrush
                        }

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
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to write EvergreenLibrary.json: $_" -Level Error
                    if ($null -ne $appsActionStatusLabel) {
                        $getThemeStatusBrush = {
                            param(
                                [Parameter(Mandatory = $true)]
                                [string]$ResourceKey,

                                [Parameter(Mandatory = $true)]
                                [System.Windows.Media.Brush]$FallbackBrush
                            )

                            $themeBrush = $null
                            if ($null -ne $SyncHash.Window -and $null -ne $SyncHash.Window.Resources -and $SyncHash.Window.Resources.Contains($ResourceKey)) {
                                $candidate = $SyncHash.Window.Resources[$ResourceKey]
                                if ($candidate -is [System.Windows.Media.Brush]) {
                                    $themeBrush = [System.Windows.Media.Brush]$candidate
                                }
                            }

                            if ($null -ne $themeBrush) {
                                return $themeBrush
                            }

                            return $FallbackBrush
                        }

                        $appsActionStatusLabel.Foreground = & $getThemeStatusBrush -ResourceKey 'StatusErrorBrush' -FallbackBrush ([System.Windows.Media.Brushes]::OrangeRed)
                        $appsActionStatusLabel.Text = 'Failed to update library'
                    }
                }
            }.GetNewClosure())
    }

    # Event handler: AddToQueueButton - Add selected app versions to download queue
    if ($null -ne $addToQueueButton) {
        $addToQueueButton.add_Click({
                $selectedApp = $appsListBox.SelectedItem
                $selectedVersions = @($SyncHash.VersionsListView.SelectedItems)

                if ($null -eq $selectedApp -or $selectedVersions.Count -eq 0) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Select one or more version rows before adding to queue.' -Level Warning
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

                    $isDuplicate = $SyncHash.DownloadQueue | Where-Object { $_.Uri -eq $queueItem.Uri }
                    if ($isDuplicate) {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Already queued: $($queueItem.AppName) $($queueItem.Version)" -Level Warning
                        continue
                    }

                    $SyncHash.DownloadQueue.Add($queueItem)
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Queued: $($queueItem.AppName) $($queueItem.Version)" -Level Info
                }
                & ($SyncHash['RefreshQueueView'])
            }.GetNewClosure())
    }

    Write-Verbose 'EvergreenUI: Apps feature registered.'
}
