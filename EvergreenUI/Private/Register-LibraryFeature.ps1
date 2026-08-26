function Register-LibraryFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Library management feature.

    .DESCRIPTION
    Sets up event handlers for the Library navigation view, including library path
    selection, library refresh, library creation, and integration with Evergreen
    library updates via Start-EvergreenLibraryUpdate.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Library feature.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls
    $libraryPathViewBox = $Controls.LibraryPathViewBox
    $browseLibraryButton = $Controls.BrowseLibraryButton
    $libraryNewButton = $Controls.LibraryNewButton
    $libraryRefreshButton = $Controls.LibraryRefreshButton
    $libraryOpenFolderButton = $Controls.LibraryOpenFolderButton

    # Verify required controls exist
    if ($null -eq $SyncHash.LibraryContentsListView -or $null -eq $libraryPathViewBox) {
        Write-Verbose 'EvergreenUI: Required Library controls not found; Library feature registration skipped.'
        return
    }

    # Helper scriptblock: Get library item display name from various property names
    $getLibraryItemName = {
        param([PSObject]$Item)
        if ($null -eq $Item) { return '' }

        foreach ($candidate in @('Name', 'AppName', 'Application', 'Product')) {
            if ($Item.PSObject.Properties.Name -contains $candidate -and -not [string]::IsNullOrWhiteSpace([string]$Item.$candidate)) {
                return [string]$Item.$candidate
            }
        }

        return [string]$Item
    }

    # Helper scriptblock: Load and display library contents
    $refreshLibraryView = {
        $path = $libraryPathViewBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            $SyncHash.LibraryStatusLabel.Text = 'Set a library path to load library contents.'
            $SyncHash.LibraryContentsListView.ItemsSource = @()
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            return
        }

        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            $SyncHash.LibraryStatusLabel.Text = "Library path does not exist: $path"
            $SyncHash.LibraryContentsListView.ItemsSource = @()
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            return
        }

        try {
            $SyncHash.Config.LibraryPath = $path
            & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Get-EvergreenLibrary -Path '$path'" -Level Cmd
            $items = @()
            $libraryWarnings = @()
            $libraryObj = Get-EvergreenLibrary -Path $path -ErrorAction Stop -WarningVariable libraryWarnings
            foreach ($w in $libraryWarnings) {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Get-EvergreenLibrary: $w" -Level Warning
            }
            $inventory = if ($libraryObj.PSObject.Properties.Name -contains 'Inventory') {
                @($libraryObj.Inventory)
            }
            else {
                @($libraryObj)
            }

            foreach ($entry in $inventory) {
                $appName = if ($entry.PSObject.Properties.Name -contains 'ApplicationName') {
                    [string]$entry.ApplicationName
                }
                else {
                    & $getLibraryItemName -Item $entry
                }
                $versions = if ($entry.PSObject.Properties.Name -contains 'Versions') { $entry.Versions } else { $null }
                $versionCount = if ($null -ne $versions) { @($versions).Count } else { 0 }
                $appPath = Join-Path -Path $path -ChildPath $appName

                $items += [PSCustomObject]@{
                    Name         = $appName
                    VersionCount = $versionCount
                    Path         = $appPath
                    SourceItem   = $entry
                }
            }

            $SyncHash.LibraryData = @($items)
            $SyncHash.LibraryContentsListView.ItemsSource = $SyncHash.LibraryData
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            $SyncHash.LibraryStatusLabel.Text = "Loaded $($SyncHash.LibraryData.Count) library apps."
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Library loaded from $path ($($SyncHash.LibraryData.Count) apps)." -Level Info
        }
        catch {
            $SyncHash.LibraryData = @()
            $SyncHash.LibraryContentsListView.ItemsSource = @()
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            $SyncHash.LibraryStatusLabel.Text = 'Failed to load library.'
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to load library: $_" -Level Error
        }
    }

    # Helper scriptblock: Load and display version details for selected library app
    $loadLibraryAppDetails = {
        param([PSObject]$SelectedLibraryItem)

        if ($null -eq $SelectedLibraryItem) {
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            return
        }

        $appName = [string]$SelectedLibraryItem.Name
        $versions = $null
        if ($SelectedLibraryItem.PSObject.Properties.Name -contains 'SourceItem' -and
            $null -ne $SelectedLibraryItem.SourceItem -and
            $SelectedLibraryItem.SourceItem.PSObject.Properties.Name -contains 'Versions') {
            $versions = $SelectedLibraryItem.SourceItem.Versions
        }

        if ($null -eq $versions) {
            $SyncHash.LibraryDetailsListView.ItemsSource = @()
            $SyncHash.LibraryStatusLabel.Text = "No version details found for $appName."
            return
        }

        $versionArray = @($versions)

        # Build columns dynamically from the first item's properties, Version always first
        $gridView = [System.Windows.Controls.GridView]::new()
        if ($versionArray.Count -gt 0) {
            $allProps = $versionArray[0].PSObject.Properties.Name
            $orderedProps = @('Version') + ($allProps | Where-Object { $_ -ne 'Version' })
            foreach ($prop in $orderedProps) {
                $col = [System.Windows.Controls.GridViewColumn]::new()
                $col.Header = $prop
                $col.DisplayMemberBinding = [System.Windows.Data.Binding]::new($prop)
                $col.Width = if ($prop -match 'URI|Url|Path') { 400 } elseif ($prop -eq 'Version') { 130 } else { 110 }
                $gridView.Columns.Add($col)
            }
        }
        $SyncHash.LibraryDetailsListView.View = $gridView
        $SyncHash.LibraryDetailsListView.ItemsSource = $versionArray
        $SyncHash.LibraryStatusLabel.Text = "Details loaded for $appName."
    }

    # Helper scriptblock: Apply sort to library contents list
    $applyLibraryContentsSort = {
        [void](Set-ListViewSort -ListView $SyncHash.LibraryContentsListView `
            -Property ([string]$SyncHash.LibraryContentsSortProperty) `
            -Direction ([string]$SyncHash.LibraryContentsSortDirection))
    }

    # Helper scriptblock: Apply sort to library details list
    $applyLibraryDetailsSort = {
        [void](Set-ListViewSort -ListView $SyncHash.LibraryDetailsListView `
            -Property ([string]$SyncHash.LibraryDetailsSortProperty) `
            -Direction ([string]$SyncHash.LibraryDetailsSortDirection))
    }

    # Store helper scriptblocks in SyncHash for access by other features
    $SyncHash['RefreshLibraryView'] = $refreshLibraryView.GetNewClosure()
    $SyncHash['LoadLibraryAppDetails'] = $loadLibraryAppDetails.GetNewClosure()
    $SyncHash['ApplyLibraryContentsSort'] = $applyLibraryContentsSort.GetNewClosure()
    $SyncHash['ApplyLibraryDetailsSort'] = $applyLibraryDetailsSort.GetNewClosure()

    # Event handler: Browse and select library path
    if ($null -ne $browseLibraryButton) {
        $browseLibraryButton.add_Click({
                $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dlg.Description = 'Select Evergreen library folder'
                $dlg.SelectedPath = $libraryPathViewBox.Text
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $libraryPathViewBox.Text = $dlg.SelectedPath
                    $SyncHash.Config.LibraryPath = $dlg.SelectedPath
                    & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                    & $refreshLibraryView
                    if ($null -ne $SyncHash.UpdateAddToLibraryButtonState) {
                        & ($SyncHash['UpdateAddToLibraryButtonState'])
                    }
                }
            }.GetNewClosure())
    }

    # Event handler: Create new library
    if ($null -ne $libraryNewButton) {
        $libraryNewButton.add_Click({
                $path = $libraryPathViewBox.Text
                if ([string]::IsNullOrWhiteSpace($path)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Set a library path before creating a new library.' -Level Warning
                    return
                }

                try {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "New-EvergreenLibrary -Path '$path'" -Level Cmd
                    New-EvergreenLibrary -Path $path -ErrorAction Stop | Out-Null
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Created Evergreen library: $path" -Level Info
                    $SyncHash.Config.LibraryPath = $path
                    & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                    & $refreshLibraryView
                    if ($null -ne $SyncHash.UpdateAddToLibraryButtonState) {
                        & ($SyncHash['UpdateAddToLibraryButtonState'])
                    }
                }
                catch {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Failed to create library: $_" -Level Error
                }
            }.GetNewClosure())
    }

    # Event handler: Refresh library view
    if ($null -ne $libraryRefreshButton) {
        $libraryRefreshButton.add_Click({
                & $refreshLibraryView
            }.GetNewClosure())
    }

    # Event handler: Open library folder in explorer
    if ($null -ne $libraryOpenFolderButton) {
        $libraryOpenFolderButton.add_Click({
                $path = $libraryPathViewBox.Text
                if ([string]::IsNullOrWhiteSpace($path)) {
                    return
                }

                if (Test-Path -LiteralPath $path -PathType Container) {
                    Start-Process -FilePath 'explorer.exe' -ArgumentList $path | Out-Null
                }
                else {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Library path does not exist: $path" -Level Warning
                }
            }.GetNewClosure())
    }

    # Event handler: Library contents list double-click (load details)
    if ($null -ne $SyncHash.LibraryContentsListView) {
        $SyncHash.LibraryContentsListView.add_MouseDoubleClick({
                $selected = $SyncHash.LibraryContentsListView.SelectedItem
                & $loadLibraryAppDetails -SelectedLibraryItem $selected
            }.GetNewClosure())

        # Event handler: Library contents list selection changed
        $SyncHash.LibraryContentsListView.add_SelectionChanged({
                $selected = $SyncHash.LibraryContentsListView.SelectedItem
                if ($null -eq $selected) {
                    $SyncHash.LibraryDetailsListView.ItemsSource = @()
                    return
                }
                & $loadLibraryAppDetails -SelectedLibraryItem $selected
            }.GetNewClosure())

        # Event handler: Library contents list column sorting
        $SyncHash.LibraryContentsListView.AddHandler(
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

                $property = [string]$header.Content
                if ([string]::IsNullOrWhiteSpace($property)) {
                    return
                }

                $newDirection = 'Ascending'
                if ($SyncHash.LibraryContentsSortProperty -eq $property -and $SyncHash.LibraryContentsSortDirection -eq 'Ascending') {
                    $newDirection = 'Descending'
                }

                $SyncHash.LibraryContentsSortProperty = $property
                $SyncHash.LibraryContentsSortDirection = $newDirection

                & $applyLibraryContentsSort
            }.GetNewClosure())
        )
    }

    # Event handler: Library details list column sorting
    if ($null -ne $SyncHash.LibraryDetailsListView) {
        $SyncHash.LibraryDetailsListView.AddHandler(
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

                $property = [string]$header.Content
                if ([string]::IsNullOrWhiteSpace($property)) {
                    return
                }

                $newDirection = 'Ascending'
                if ($SyncHash.LibraryDetailsSortProperty -eq $property -and $SyncHash.LibraryDetailsSortDirection -eq 'Ascending') {
                    $newDirection = 'Descending'
                }

                $SyncHash.LibraryDetailsSortProperty = $property
                $SyncHash.LibraryDetailsSortDirection = $newDirection

                & $applyLibraryDetailsSort
            }.GetNewClosure())
        )
    }

    # Event handler: Start library update
    if ($null -ne $SyncHash.LibraryUpdateButton) {
        $SyncHash.LibraryUpdateButton.add_Click({
                if ($SyncHash.IsRunning) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Another operation is currently running.' -Level Warning
                    return
                }

                $path = $libraryPathViewBox.Text
                if ([string]::IsNullOrWhiteSpace($path)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Set a library path before updating.' -Level Warning
                    return
                }

                if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Library path does not exist: $path" -Level Error
                    return
                }

                $SyncHash.Config.LibraryPath = $path
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

                $SyncHash.IsRunning = $true
                $SyncHash.LibraryUpdateButton.IsEnabled = $false
                if ($null -ne $SyncHash.LibraryUpdateProgressBar) {
                    $SyncHash.LibraryUpdateProgressBar.Visibility = [System.Windows.Visibility]::Visible
                }

                $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
                $formatLogEntryPath = Join-Path -Path $privateRoot -ChildPath 'Format-LogEntry.ps1'
                $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
                $invokeLibraryUpdatePath = Join-Path -Path $privateRoot -ChildPath 'Invoke-LibraryUpdate.ps1'

                $rs = New-WpfRunspace -SyncHash $SyncHash
                $ps = [powershell]::Create()
                $ps.Runspace = $rs

                [void]$ps.AddScript({
                        param(
                            [string]$FormatLogEntryPath,
                            [string]$WriteUILogPath,
                            [string]$InvokeLibraryUpdatePath
                        )

                        . $FormatLogEntryPath
                        . $WriteUILogPath
                        . $InvokeLibraryUpdatePath

                        try {
                            Import-Module Evergreen -ErrorAction Stop | Out-Null
                            Invoke-LibraryUpdate -SyncHash $syncHash
                        }
                        catch {
                            & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Library update run failed: $_" -Level Error
                        }
                        finally {
                            $syncHash.Window.Dispatcher.Invoke([action] {
                                    $syncHash.IsRunning = $false
                                    if ($null -ne $syncHash.LibraryUpdateButton) {
                                        $syncHash.LibraryUpdateButton.IsEnabled = $true
                                    }
                                    if ($null -ne $syncHash.LibraryUpdateProgressBar) {
                                        $syncHash.LibraryUpdateProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
                                    }
                                    & ($syncHash['RefreshLibraryView'])
                                }, 'Normal')
                        }
                    }).AddArgument($formatLogEntryPath).AddArgument($writeUILogPath).AddArgument($invokeLibraryUpdatePath)

                [void]$ps.BeginInvoke()
            }.GetNewClosure())
    }

    Write-Verbose 'EvergreenUI: Library feature registration complete.'
}
