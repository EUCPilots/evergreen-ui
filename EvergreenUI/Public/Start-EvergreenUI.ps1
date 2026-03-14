#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the Evergreen Workbench graphical interface.

.DESCRIPTION
    Start-EvergreenUI is the single exported function of the EvergreenUI module.
    It checks that the Evergreen module is available, loads required WPF
    assemblies, builds the main window, and blocks until the window is closed.

    The function must be called from a thread with STA apartment state. In
    PowerShell 5.1 this is always the case. In PowerShell 7+ the host may be
    MTA; the function detects this and re-launches itself on an STA thread
    automatically.

.EXAMPLE
    Start-EvergreenUI

    Opens the Evergreen Workbench window. All interaction happens inside the GUI.

.NOTES
    - Windows only.
    - Requires the Evergreen module to be installed.
    - No parameters are accepted; all configuration is done inside the GUI and
      persisted to $env:APPDATA\EvergreenUI\config.json.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# STA guard (PowerShell 7+ may start MTA)
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Verbose 'Current thread is MTA - restarting on an STA thread.'
    $sta = [powershell]::Create()
    $sta.AddScript({ Import-Module EvergreenUI; Start-EvergreenUI }) | Out-Null
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $sta.Runspace = $runspace
    $sta.Invoke()
    $sta.Dispose()
    $runspace.Dispose()
    return
}

# Dependency check
Test-EvergreenModule

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Load saved config
$config = Get-UIConfig

# Shared state
$syncHash = [hashtable]::Synchronized(@{
        Window                     = $null
        LogTextBox                 = $null
        LogScrollViewer            = $null
        IsRunning                  = $false
        AppList                    = $null
        CurrentAppResults          = $null
        FilterState                = @{}
        VersionsListView           = $null
        ResultsCountLabel          = $null
        DownloadQueueListView      = $null
        QueueCountLabel            = $null
        DownloadAllButton          = $null
        LibraryContentsListView    = $null
        LibraryDetailsListView     = $null
        LibraryStatusLabel         = $null
        LibraryUpdateButton        = $null
        LibraryData                = @()
        ActiveBackgroundOperations = [System.Collections.Generic.List[object]]::new()
        BackgroundOperationsTimer  = $null
        DownloadQueue              = [System.Collections.Generic.List[PSCustomObject]]::new()
        EvergreenVersion           = ''
        Config                     = $config
        PendingLoadTimer           = $null
        PendingLoadPS              = $null
        PendingLoadRunspace        = $null
        PendingLoadAsync           = $null
        PendingLoadAppName         = $null
    })

# Load XAML layout
$xamlPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "Resources") -ChildPath "EvergreenUI.xaml"
$stream   = [System.IO.File]::OpenRead((Resolve-Path -Path $xamlPath).Path)
$window   = [System.Windows.Markup.XamlReader]::Load($stream)
$stream.Dispose()

# Resolve named controls
$syncHash.Window = $window
$syncHash.LogTextBox = $window.FindName('LogTextBox')
$syncHash.LogScrollViewer = $window.FindName('LogScrollViewer')

$rootGrid = $window.FindName('RootGrid')
$evergreenVersionText = $window.FindName('EvergreenVersionText')
$evergreenStatusDot = $window.FindName('EvergreenStatusDot')
$themeToggle = $window.FindName('ThemeToggle')
$themeLabel = $window.FindName('ThemeLabel')

$navApps = $window.FindName('NavApps')
$navDownload = $window.FindName('NavDownload')
$navLibrary = $window.FindName('NavLibrary')
$navSettings = $window.FindName('NavSettings')

$appsPanel = $window.FindName('AppsPanel')
$downloadPanel = $window.FindName('DownloadPanel')
$libraryPanel = $window.FindName('LibraryPanel')
$settingsPanel = $window.FindName('SettingsPanel')

$refreshAppsButton = $window.FindName('RefreshAppsButton')
$appSearchBox = $window.FindName('AppSearchBox')
$appsComboBox = $window.FindName('AppsComboBox')
$loadAppVersionsButton = $window.FindName('LoadAppVersionsButton')
$filterWrapPanel = $window.FindName('FilterWrapPanel')
$clearFiltersButton = $window.FindName('ClearFiltersButton')
$exportCsvButton   = $window.FindName('ExportCsvButton')
$addToQueueButton  = $window.FindName('AddToQueueButton')

$removeQueueItemButton = $window.FindName('RemoveQueueItemButton')
$clearQueueButton = $window.FindName('ClearQueueButton')
$openDownloadFolderButton = $window.FindName('OpenDownloadFolderButton')

$libraryPathViewBox = $window.FindName('LibraryPathViewBox')
$libraryBrowseButton = $window.FindName('LibraryBrowseButton')
$libraryNewButton = $window.FindName('LibraryNewButton')
$libraryRefreshButton = $window.FindName('LibraryRefreshButton')
$libraryOpenFolderButton = $window.FindName('LibraryOpenFolderButton')

$syncHash.LibraryContentsListView = $window.FindName('LibraryContentsListView')
$syncHash.LibraryDetailsListView = $window.FindName('LibraryDetailsListView')
$syncHash.LibraryStatusLabel = $window.FindName('LibraryStatusLabel')
$syncHash.LibraryUpdateButton = $window.FindName('LibraryUpdateButton')

$syncHash.DownloadQueueListView = $window.FindName('DownloadQueueListView')
$syncHash.QueueCountLabel = $window.FindName('QueueCountLabel')
$syncHash.DownloadAllButton = $window.FindName('DownloadAllButton')

$syncHash.VersionsListView = $window.FindName('VersionsListView')
$syncHash.ResultsCountLabel = $window.FindName('ResultsCountLabel')
$appCountLabel = $window.FindName('AppCountLabel')
$appDetailEmpty = $window.FindName('AppDetailEmpty')
$appDetailLoading = $window.FindName('AppDetailLoading')
$appDetailLoadingLabel = $window.FindName('AppDetailLoadingLabel')
$appDetailContent = $window.FindName('AppDetailContent')
$appDetailTitle = $window.FindName('AppDetailTitle')

$copyLogButton = $window.FindName('CopyLogButton')
$saveLogButton = $window.FindName('SaveLogButton')
$logToggleButton = $window.FindName('LogToggleButton')

$outputPathBox = $window.FindName('OutputPathBox')
$evergreenAppsPathBox = $window.FindName('EvergreenAppsPathBox')
$logVerbosityComboBox = $window.FindName('LogVerbosityComboBox')
$startupViewComboBox = $window.FindName('StartupViewComboBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$openEvergreenAppsFolderButton = $window.FindName('OpenEvergreenAppsFolderButton')
$clearCacheButton = $window.FindName('ClearCacheButton')
$openCacheFolderButton = $window.FindName('OpenCacheFolderButton')
# Log row is RowDefinitions[3]; track its height for collapse/restore
$logRowDef = $rootGrid.RowDefinitions[3]

# Apply persisted window size with safe minimums
$window.Width = [Math]::Max(900, [double]$syncHash.Config.WindowWidth)
$window.Height = [Math]::Max(600, [double]$syncHash.Config.WindowHeight)

# Apps view helpers
$updateAppsComboSource = {
    param([string]$SearchText = '')

    $allApps = @($syncHash.AppList)
    if ($allApps.Count -eq 0) {
        $appsComboBox.ItemsSource = @()
        $appCountLabel.Text = ''
        return
    }

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        $appsComboBox.ItemsSource = $allApps
        $appCountLabel.Text = " $($allApps.Count) of $($allApps.Count)"
        return
    }

    $needle = $SearchText.Trim()
    $filtered = $allApps | Where-Object {
        $_.Name -like "*$needle*" -or $_.FriendlyName -like "*$needle*"
    }

    $appsComboBox.ItemsSource = @($filtered)
    $appCountLabel.Text = " $(@($filtered).Count) of $($allApps.Count)"
}

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

# Rebuilds the VersionsListView GridView columns to match the properties returned
# by Get-EvergreenApp for the current app. Version is always first, URI always last.
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
}

# Returns the cache file path for a given app name, creating the cache directory if needed.
$getAppCacheFile = {
    param([string]$AppName)
    $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    Join-Path $cacheDir "$AppName.json"
}

# Populates the detail panel from a result array (used for both live and cached data).
$displayAppResults = {
    param([PSObject[]]$AppResults)
    $syncHash.CurrentAppResults = @($AppResults)
    & $rebuildVersionColumns -AppResults $syncHash.CurrentAppResults
    $filterProps = @(Get-FilterableProperties -AppResults $syncHash.CurrentAppResults)
    New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
        Invoke-FilterUpdate -SyncHash $syncHash
    }
    Invoke-FilterUpdate -SyncHash $syncHash
    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
}

$loadAppVersions = {
    $selectedApp = $appsComboBox.SelectedItem
    if ($null -eq $selectedApp) {
        Write-UILog -SyncHash $syncHash -Message 'Select an application first.' -Level Warning
        return
    }

    $appName = [string]$selectedApp.Name
    $loadAppVersionsButton.IsEnabled = $false

    # Show loading state
    $appDetailContent.Visibility     = [System.Windows.Visibility]::Collapsed
    $appDetailLoading.Visibility     = [System.Windows.Visibility]::Visible
    $appDetailLoadingLabel.Text      = "Retrieving details for $appName with Evergreen..."

    Write-UILog -SyncHash $syncHash -Message "Loading versions for $appName..." -Level Info
    Write-UILog -SyncHash $syncHash -Message "Get-EvergreenApp -Name '$appName'" -Level Cmd

    $runspace = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
            param([string]$Name)
            Get-EvergreenApp -Name $Name -ErrorAction Stop
        }).AddArgument($appName)

    # Store async state in syncHash so the tick handler and cancellation logic can reach it
    $syncHash.PendingLoadPS       = $ps
    $syncHash.PendingLoadRunspace = $runspace
    $syncHash.PendingLoadAppName  = $appName
    $syncHash.PendingLoadAsync    = $ps.BeginInvoke()

    $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $syncHash.PendingLoadTimer = $pollTimer

    $pollTimer.add_Tick({
        # Guard against null (can happen if cancelled between ticks)
        if ($null -eq $syncHash.PendingLoadAsync -or -not $syncHash.PendingLoadAsync.IsCompleted) { return }

        $syncHash.PendingLoadTimer.Stop()
        $syncHash.PendingLoadTimer = $null

        # Grab refs before clearing syncHash slots
        $currentPS       = $syncHash.PendingLoadPS
        $currentRunspace = $syncHash.PendingLoadRunspace
        $currentAsync    = $syncHash.PendingLoadAsync
        $currentAppName  = $syncHash.PendingLoadAppName

        $syncHash.PendingLoadPS       = $null
        $syncHash.PendingLoadRunspace = $null
        $syncHash.PendingLoadAsync    = $null
        $syncHash.PendingLoadAppName  = $null

        try {
            $results = @($currentPS.EndInvoke($currentAsync))
            $currentPS.Dispose()
            $currentRunspace.Dispose()

            # Save results to cache
            $cachePath = & $getAppCacheFile -AppName $currentAppName
            try {
                $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding UTF8 -Force
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to write cache for ${currentAppName}: $_" -Level Warning
            }

            & $displayAppResults -AppResults $results

            Write-UILog -SyncHash $syncHash -Message "Loaded $($syncHash.CurrentAppResults.Count) versions for $currentAppName." -Level Info
        }
        catch {
            try { $currentPS.Dispose() } catch {}
            try { $currentRunspace.Dispose() } catch {}

            $syncHash.CurrentAppResults = @()
            $syncHash.VersionsListView.ItemsSource = @()
            $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
            $filterWrapPanel.Children.Clear()

            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Visible

            Write-UILog -SyncHash $syncHash -Message "Failed to load versions for ${currentAppName}: $_" -Level Error
        }
        finally {
            $loadAppVersionsButton.IsEnabled = $true
        }
    })
    $pollTimer.Start()
}

$refreshQueueView = {
    $syncHash.DownloadQueueListView.ItemsSource = $null
    $syncHash.DownloadQueueListView.ItemsSource = $syncHash.DownloadQueue
    $syncHash.DownloadQueueListView.Items.Refresh()

    $pending = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
    $done = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
    $failed = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
    $total = $syncHash.DownloadQueue.Count
    $syncHash.QueueCountLabel.Text = "Queue: $total items (Pending: $pending, Done: $done, Failed: $failed)"
}

$normalizeDirectoryPath = {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ''
    }

    return $PathValue.Trim().Trim('"')
}

$registerBackgroundOperation = {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Management.Automation.PowerShell]$PowerShellInstance,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.Runspace]$RunspaceInstance,
        [Parameter(Mandatory)]$AsyncResult
    )

    $operation = [PSCustomObject]@{
        Name       = $Name
        PowerShell = $PowerShellInstance
        Runspace   = $RunspaceInstance
        Async      = $AsyncResult
    }

    $syncHash.ActiveBackgroundOperations.Add($operation)

    if ($null -eq $syncHash.BackgroundOperationsTimer) {
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.add_Tick({
                $completed = @($syncHash.ActiveBackgroundOperations | Where-Object { $_.Async.IsCompleted })
                foreach ($op in $completed) {
                    try {
                        [void]$op.PowerShell.EndInvoke($op.Async)
                    }
                    catch {
                        Write-UILog -SyncHash $syncHash -Message "Background operation '$($op.Name)' completed with error: $_" -Level Error
                    }
                    finally {
                        try { $op.PowerShell.Dispose() } catch {}
                        try { $op.Runspace.Dispose() } catch {}
                        [void]$syncHash.ActiveBackgroundOperations.Remove($op)
                    }
                }

                if ($syncHash.ActiveBackgroundOperations.Count -eq 0) {
                    $syncHash.BackgroundOperationsTimer.Stop()
                }
            })
        $syncHash.BackgroundOperationsTimer = $timer
    }

    if (-not $syncHash.BackgroundOperationsTimer.IsEnabled) {
        $syncHash.BackgroundOperationsTimer.Start()
    }
}

$startQueueDownload = {
    if ($syncHash.IsRunning) {
        Write-UILog -SyncHash $syncHash -Message 'A queue operation is already running.' -Level Warning
        return
    }

    if ($syncHash.DownloadQueue.Count -eq 0) {
        Write-UILog -SyncHash $syncHash -Message 'Queue is empty. Add items from Apps view first.' -Level Warning
        return
    }

    $outputPath = & $normalizeDirectoryPath -PathValue $syncHash.Config.OutputPath
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        Write-UILog -SyncHash $syncHash -Message 'Set a download output path in Settings before starting queue downloads.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
        try {
            [void](New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop)
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Could not create output path '$outputPath': $_" -Level Error
            return
        }
    }

    $syncHash.Config.OutputPath = $outputPath
    $outputPathBox.Text = $outputPath
    Set-UIConfig -Config $syncHash.Config

    $syncHash.IsRunning = $true
    $syncHash.DownloadAllButton.IsEnabled = $false

    $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
    $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
    $invokeDownloadPath = Join-Path -Path $privateRoot -ChildPath 'Invoke-AppDownload.ps1'

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param(
                [string]$WriteUILogPath,
                [string]$InvokeDownloadPath
            )

            . $WriteUILogPath
            . $InvokeDownloadPath

            try {
                Import-Module Evergreen -ErrorAction Stop | Out-Null
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to import Evergreen in background runspace: $_" -Level Error
            }

            try {
                Write-UILog -SyncHash $syncHash -Message 'Starting queue download run (sequential).' -Level Info

                foreach ($item in @($syncHash.DownloadQueue)) {
                    if ($item.Status -eq 'Done') { continue }
                    Invoke-AppDownload -SyncHash $syncHash -QueueItem $item
                }

                Write-UILog -SyncHash $syncHash -Message 'Queue download run finished.' -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Queue download run failed: $_" -Level Error
            }
            finally {
                # Pre-compute counts on the background thread before dispatching.
                $pendingCount = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
                $doneCount    = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
                $failedCount  = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
                $totalCount   = $syncHash.DownloadQueue.Count
                $finalQueueText = "Queue: $totalCount items (Pending: $pendingCount, Done: $doneCount, Failed: $failedCount)"

                $syncHash.Window.Dispatcher.Invoke([action] {
                        $syncHash.IsRunning = $false
                        if ($null -ne $syncHash.DownloadAllButton) {
                            $syncHash.DownloadAllButton.IsEnabled = $true
                        }
                        if ($null -ne $syncHash.DownloadQueueListView) {
                            $syncHash.DownloadQueueListView.Items.Refresh()
                        }
                        if ($null -ne $syncHash.QueueCountLabel) {
                            $syncHash.QueueCountLabel.Text = $finalQueueText
                        }
                    }, 'Normal')
            }
        }).AddArgument($writeUILogPath).AddArgument($invokeDownloadPath)

    $async = $ps.BeginInvoke()
    & $registerBackgroundOperation -Name 'QueueDownload' -PowerShellInstance $ps -RunspaceInstance $rs -AsyncResult $async
}

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

$refreshLibraryView = {
    $path = $libraryPathViewBox.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        $syncHash.LibraryStatusLabel.Text = 'Set a library path to load library contents.'
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        return
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $syncHash.LibraryStatusLabel.Text = "Library path does not exist: $path"
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        return
    }

    try {
        $syncHash.Config.LibraryPath = $path
        Set-UIConfig -Config $syncHash.Config

        Write-UILog -SyncHash $syncHash -Message "Get-EvergreenLibrary -Path '$path'" -Level Cmd
        $items = @()
        $libraryObj = Get-EvergreenLibrary -Path $path -ErrorAction Stop
        $inventory = if ($libraryObj.PSObject.Properties.Name -contains 'Inventory') {
            @($libraryObj.Inventory)
        } else {
            @($libraryObj)
        }

        foreach ($entry in $inventory) {
            $appName = if ($entry.PSObject.Properties.Name -contains 'ApplicationName') {
                [string]$entry.ApplicationName
            } else {
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

        $syncHash.LibraryData = @($items)
        $syncHash.LibraryContentsListView.ItemsSource = $syncHash.LibraryData
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = "Loaded $($syncHash.LibraryData.Count) library apps."
        Write-UILog -SyncHash $syncHash -Message "Library loaded from $path ($($syncHash.LibraryData.Count) apps)." -Level Info
    }
    catch {
        $syncHash.LibraryData = @()
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = 'Failed to load library.'
        Write-UILog -SyncHash $syncHash -Message "Failed to load library: $_" -Level Error
    }
}
$syncHash.RefreshLibraryView = $refreshLibraryView

$loadLibraryAppDetails = {
    param([PSObject]$SelectedLibraryItem)

    if ($null -eq $SelectedLibraryItem) {
        $syncHash.LibraryDetailsListView.ItemsSource = @()
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
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = "No version details found for $appName."
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
    $syncHash.LibraryDetailsListView.View = $gridView
    $syncHash.LibraryDetailsListView.ItemsSource = $versionArray
    $syncHash.LibraryStatusLabel.Text = "Details loaded for $appName."
}

$startLibraryUpdate = {
    if ($syncHash.IsRunning) {
        Write-UILog -SyncHash $syncHash -Message 'Another operation is currently running.' -Level Warning
        return
    }

    $path = $libraryPathViewBox.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-UILog -SyncHash $syncHash -Message 'Set a library path before updating.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-UILog -SyncHash $syncHash -Message "Library path does not exist: $path" -Level Error
        return
    }

    $syncHash.Config.LibraryPath = $path
    Set-UIConfig -Config $syncHash.Config

    $syncHash.IsRunning = $true
    $syncHash.LibraryUpdateButton.IsEnabled = $false

    $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
    $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
    $invokeLibraryUpdatePath = Join-Path -Path $privateRoot -ChildPath 'Invoke-LibraryUpdate.ps1'

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param(
                [string]$WriteUILogPath,
                [string]$InvokeLibraryUpdatePath
            )

            . $WriteUILogPath
            . $InvokeLibraryUpdatePath

            try {
                Import-Module Evergreen -ErrorAction Stop | Out-Null
                Invoke-LibraryUpdate -SyncHash $syncHash
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Library update run failed: $_" -Level Error
            }
            finally {
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $syncHash.IsRunning = $false
                        if ($null -ne $syncHash.LibraryUpdateButton) {
                            $syncHash.LibraryUpdateButton.IsEnabled = $true
                        }
                        & $syncHash.RefreshLibraryView
                    }, 'Normal')
            }
        }).AddArgument($writeUILogPath).AddArgument($invokeLibraryUpdatePath)

    $async = $ps.BeginInvoke()
    & $registerBackgroundOperation -Name 'LibraryUpdate' -PowerShellInstance $ps -RunspaceInstance $rs -AsyncResult $async
}

# Apply initial log height from config
$initialLogHeight = [Math]::Max(40, 40 + $config.LogHeight)
$logRowDef.Height = [System.Windows.GridLength]::new($initialLogHeight)

# Event: Window.Loaded
$window.add_Loaded({
        # Apply saved theme (before any logging so colours are correct)
        if ($syncHash.Config.Theme -eq 'Dark') {
            $themeToggle.IsChecked = $true
            Set-DarkTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
        }
        else {
            $themeToggle.IsChecked = $false
            Set-LightTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
        }

        # Populate Evergreen version info in title bar
        try {
            $egModule = Get-Module -Name Evergreen | Select-Object -First 1
            if ($null -ne $egModule) {
                $syncHash.EvergreenVersion = "v$($egModule.Version)"
                $evergreenVersionText.Text = "Evergreen $($syncHash.EvergreenVersion)"
                $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
            }
            else {
                $evergreenVersionText.Text = 'Evergreen: not loaded'
                $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
            }
        }
        catch {
            $evergreenVersionText.Text = 'Evergreen: error'
            $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
        }

        Write-UILog -SyncHash $syncHash -Message "EvergreenUI started. $($syncHash.EvergreenVersion)" -Level Info

        & $loadAppCatalog

        if (-not [string]::IsNullOrWhiteSpace($syncHash.Config.LastAppName)) {
            $savedApp = @($syncHash.AppList | Where-Object { $_.Name -eq $syncHash.Config.LastAppName } | Select-Object -First 1)
            if ($savedApp.Count -gt 0) {
                $appsComboBox.SelectedItem = $savedApp[0]
                $appsComboBox.ScrollIntoView($savedApp[0])
            }
        }

        & $refreshQueueView
        $libraryPathViewBox.Text = $syncHash.Config.LibraryPath

        switch ([string]$syncHash.Config.StartupView) {
            'Download' {
                $navDownload.IsChecked = $true
            }
            'Library' {
                $navLibrary.IsChecked = $true
            }
            'Settings' {
                $navSettings.IsChecked = $true
            }
            default {
                $navApps.IsChecked = $true
            }
        }
    })

# Event: Window.Closing - persist config
$window.add_Closing({
        try {
            $currentLogHeight = [int]$logRowDef.Height.Value - 40
            if ($currentLogHeight -gt 0) {
                $syncHash.Config.LogHeight = $currentLogHeight
            }
            $syncHash.Config.Theme = if ($themeToggle.IsChecked) { 'Dark' } else { 'Light' }
            $syncHash.Config.WindowWidth = [int]$window.Width
            $syncHash.Config.WindowHeight = [int]$window.Height
            $syncHash.Config.LastAppName = if ($null -ne $appsComboBox.SelectedItem) { [string]$appsComboBox.SelectedItem.Name } else { '' }

            $syncHash.Config.StartupView = if ($navDownload.IsChecked) {
                'Download'
            }
            elseif ($navLibrary.IsChecked) {
                'Library'
            }
            elseif ($navSettings.IsChecked) {
                'Settings'
            }
            else {
                'Apps'
            }

            Set-UIConfig -Config $syncHash.Config

            if ($null -ne $syncHash.BackgroundOperationsTimer -and $syncHash.BackgroundOperationsTimer.IsEnabled) {
                $syncHash.BackgroundOperationsTimer.Stop()
            }

            foreach ($op in @($syncHash.ActiveBackgroundOperations)) {
                try { $op.PowerShell.Stop() } catch {}
                try { $op.PowerShell.Dispose() } catch {}
                try { $op.Runspace.Dispose() } catch {}
            }
            $syncHash.ActiveBackgroundOperations.Clear()
        }
        catch {
            # Never block window close for a config-save failure
        }
    })

# Keyboard shortcuts (Phase 8 polish)
# Ctrl+F: focus app search
# Ctrl+,: open settings
# Ctrl+D: start queue download (when Download view active)
# Ctrl+U: start library update (when Library view active)
# Ctrl+L: toggle log panel
# F5: refresh current active view
$window.add_PreviewKeyDown({
        param($sender, $e)

        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $ctrl = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0

        if ($e.Key -eq [System.Windows.Input.Key]::F5) {
            if ($navApps.IsChecked) {
                & $loadAppCatalog -Force
            }
            elseif ($navDownload.IsChecked) {
                & $refreshQueueView
            }
            elseif ($navLibrary.IsChecked) {
                & $refreshLibraryView
            }
            $e.Handled = $true
            return
        }

        if (-not $ctrl) {
            return
        }

        switch ($e.Key) {
            ([System.Windows.Input.Key]::F) {
                $navApps.IsChecked = $true
                [void]$appSearchBox.Focus()
                $appSearchBox.SelectAll()
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::OemComma) {
                $navSettings.IsChecked = $true
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::D) {
                if ($navDownload.IsChecked) {
                    & $startQueueDownload
                    $e.Handled = $true
                }
            }
            ([System.Windows.Input.Key]::U) {
                if ($navLibrary.IsChecked) {
                    & $startLibraryUpdate
                    $e.Handled = $true
                }
            }
            ([System.Windows.Input.Key]::L) {
                $logToggleButton.IsChecked = -not $logToggleButton.IsChecked
                $logToggleButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $e.Handled = $true
            }
        }
    })

# Navigation: Checked handler swaps content panels
$panelMap = @{
    NavApps     = $appsPanel
    NavDownload = $downloadPanel
    NavLibrary  = $libraryPanel
    NavSettings = $settingsPanel
}

$navCheckedHandler = {
    param($s, $e)
    foreach ($entry in $panelMap.GetEnumerator()) {
        $entry.Value.Visibility = if ($entry.Key -eq $s.Name) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
    }
}

foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navSettings)) {
    $navBtn.add_Checked($navCheckedHandler)
}

$navApps.add_Checked({
        if ($null -eq $syncHash.AppList -or $syncHash.AppList.Count -eq 0) {
            & $loadAppCatalog
        }
    })

$navDownload.add_Checked({
        & $refreshQueueView
    })

$navLibrary.add_Checked({
        if ([string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
            $libraryPathViewBox.Text = $syncHash.Config.LibraryPath
        }
        if (-not [string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
            & $refreshLibraryView
        }
    })

$refreshAppsButton.add_Click({
        Write-UILog -SyncHash $syncHash -Message 'Refreshing Evergreen app catalog...' -Level Info
        & $loadAppCatalog -Force
    })

$appSearchBox.add_TextChanged({
        & $updateAppsComboSource -SearchText $appSearchBox.Text
    })

$loadAppVersionsButton.add_Click({
        & $loadAppVersions
    })

$appsComboBox.add_SelectionChanged({
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
        $syncHash.PendingLoadAsync   = $null
        $syncHash.PendingLoadAppName = $null

        $syncHash.CurrentAppResults = @()
        $syncHash.VersionsListView.ItemsSource = @()
        $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
        $filterWrapPanel.Children.Clear()
        $syncHash.FilterState = @{}

        $selectedApp = $appsComboBox.SelectedItem
        if ($null -ne $selectedApp) {
            $appDetailTitle.Text = "$($selectedApp.Name) Version Details"

            # Load from cache if available; otherwise show the panel empty (user clicks Refresh)
            $cachePath = & $getAppCacheFile -AppName $selectedApp.Name
            if (Test-Path -LiteralPath $cachePath) {
                try {
                    $rawJson     = Get-Content -LiteralPath $cachePath -Raw
                    $parsed      = ConvertFrom-Json -InputObject $rawJson
                    # Guard against double-wrapping: @() can treat the Object[] returned by
                    # ConvertFrom-Json as a single item in certain PS/WPF execution contexts,
                    # producing Object[]{ Object[]{realItems} }. Detect and flatten one level.
                    $cachedResults = if ($parsed -is [System.Array] -and
                                        $parsed.Count -gt 0 -and
                                        $parsed[0] -is [System.Array]) {
                        [object[]]$parsed[0]
                    } elseif ($parsed -is [System.Array]) {
                        [object[]]$parsed
                    } else {
                        @($parsed)
                    }
                    Write-UILog -SyncHash $syncHash -Message "Loaded $($cachedResults.Count) cached versions for $($selectedApp.Name)." -Level Info
                    & $displayAppResults -AppResults $cachedResults
                }
                catch {
                    Write-UILog -SyncHash $syncHash -Message "Cache read failed for $($selectedApp.Name), click Refresh to load: $_" -Level Warning
                    $filterWrapPanel.Children.Clear()
                    $syncHash.FilterState = @{}
                    $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Collapsed
                    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
                }
            }
            else {
                $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Collapsed
                $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
            }
        }
        else {
            $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Visible
            $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
        }
    })

$clearFiltersButton.add_Click({
        if ($null -eq $syncHash.CurrentAppResults -or $syncHash.CurrentAppResults.Count -eq 0) {
            return
        }

        $filterProps = Get-FilterableProperties -AppResults $syncHash.CurrentAppResults
        New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
            Invoke-FilterUpdate -SyncHash $syncHash
        }
        Invoke-FilterUpdate -SyncHash $syncHash
    })

$exportCsvButton.add_Click({
        $selectedApp = $appsComboBox.SelectedItem
        $items = @($syncHash.VersionsListView.Items)

        if ($null -eq $selectedApp -or $items.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'No version data to export. Load an app first.' -Level Warning
            return
        }

        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title      = 'Export to CSV'
        $dlg.FileName   = "$($selectedApp.Name).csv"
        $dlg.DefaultExt = '.csv'
        $dlg.Filter     = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'

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

$addToQueueButton.add_Click({
        $selectedApp = $appsComboBox.SelectedItem
        $selectedVersions = @($syncHash.VersionsListView.SelectedItems)

        if ($null -eq $selectedApp -or $selectedVersions.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Select one or more version rows before adding to queue.' -Level Warning
            return
        }

        foreach ($selectedVersion in $selectedVersions) {
            $queueItem = [PSCustomObject]@{
                AppName      = [string]$selectedApp.Name
                Version      = [string]$selectedVersion.Version
                Platform     = if ($selectedVersion.PSObject.Properties.Name -contains 'Platform') { [string]$selectedVersion.Platform } else { '' }
                Architecture = if ($selectedVersion.PSObject.Properties.Name -contains 'Architecture') { [string]$selectedVersion.Architecture } else { '' }
                Channel      = if ($selectedVersion.PSObject.Properties.Name -contains 'Channel') { [string]$selectedVersion.Channel } else { '' }
                Uri          = if ($selectedVersion.PSObject.Properties.Name -contains 'URI') { [string]$selectedVersion.URI } else { '' }
                Status       = 'Pending'
            }

            $isDuplicate = $syncHash.DownloadQueue | Where-Object {
                $_.AppName      -eq $queueItem.AppName      -and
                $_.Version      -eq $queueItem.Version      -and
                $_.Architecture -eq $queueItem.Architecture -and
                $_.Channel      -eq $queueItem.Channel      -and
                $_.Platform     -eq $queueItem.Platform
            }
            if ($isDuplicate) {
                Write-UILog -SyncHash $syncHash -Message "Already queued: $($queueItem.AppName) $($queueItem.Version)" -Level Warning
                continue
            }

            $syncHash.DownloadQueue.Add($queueItem)
            Write-UILog -SyncHash $syncHash -Message "Queued: $($queueItem.AppName) $($queueItem.Version)" -Level Info
        }
        & $refreshQueueView
    })

$removeQueueItemButton.add_Click({
        if ($syncHash.IsRunning) {
            Write-UILog -SyncHash $syncHash -Message 'Cannot remove queue items while downloads are running.' -Level Warning
            return
        }

        $selectedQueueItem = $syncHash.DownloadQueueListView.SelectedItem
        if ($null -eq $selectedQueueItem) {
            Write-UILog -SyncHash $syncHash -Message 'Select one queue item to remove.' -Level Warning
            return
        }

        [void]$syncHash.DownloadQueue.Remove($selectedQueueItem)
        Write-UILog -SyncHash $syncHash -Message 'Removed selected item from queue.' -Level Info
        & $refreshQueueView
    })

$clearQueueButton.add_Click({
        if ($syncHash.IsRunning) {
            Write-UILog -SyncHash $syncHash -Message 'Cannot clear queue while downloads are running.' -Level Warning
            return
        }

        $syncHash.DownloadQueue.Clear()
        Write-UILog -SyncHash $syncHash -Message 'Queue cleared.' -Level Info
        & $refreshQueueView
    })

$openDownloadFolderButton.add_Click({
        $folderPath = $syncHash.Config.OutputPath
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            Write-UILog -SyncHash $syncHash -Message 'No download output path configured.' -Level Warning
            return
        }
        if (-not (Test-Path -LiteralPath $folderPath)) {
            $null = New-Item -ItemType Directory -Path $folderPath -Force
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $folderPath | Out-Null
    })

$syncHash.DownloadAllButton.add_Click({
        & $startQueueDownload
    })

$libraryRefreshButton.add_Click({
        & $refreshLibraryView
    })

$libraryBrowseButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Evergreen library folder'
        $dlg.SelectedPath = $libraryPathViewBox.Text
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $libraryPathViewBox.Text = $dlg.SelectedPath
            $syncHash.Config.LibraryPath = $dlg.SelectedPath
            Set-UIConfig -Config $syncHash.Config
            & $refreshLibraryView
        }
    })

$libraryNewButton.add_Click({
        $path = $libraryPathViewBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-UILog -SyncHash $syncHash -Message 'Set a library path before creating a new library.' -Level Warning
            return
        }

        try {
            Write-UILog -SyncHash $syncHash -Message "New-EvergreenLibrary -Path '$path'" -Level Cmd
            New-EvergreenLibrary -Path $path -ErrorAction Stop | Out-Null
            Write-UILog -SyncHash $syncHash -Message "Created Evergreen library: $path" -Level Info
            $syncHash.Config.LibraryPath = $path
            Set-UIConfig -Config $syncHash.Config
            & $refreshLibraryView
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Failed to create library: $_" -Level Error
        }
    })

$libraryOpenFolderButton.add_Click({
        $path = $libraryPathViewBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            return
        }

        if (Test-Path -LiteralPath $path -PathType Container) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $path | Out-Null
        }
        else {
            Write-UILog -SyncHash $syncHash -Message "Library path does not exist: $path" -Level Warning
        }
    })

$syncHash.LibraryUpdateButton.add_Click({
        & $startLibraryUpdate
    })

$syncHash.LibraryContentsListView.add_MouseDoubleClick({
        $selected = $syncHash.LibraryContentsListView.SelectedItem
        & $loadLibraryAppDetails -SelectedLibraryItem $selected
    })

$syncHash.LibraryContentsListView.add_SelectionChanged({
        $selected = $syncHash.LibraryContentsListView.SelectedItem
        if ($null -eq $selected) {
            $syncHash.LibraryDetailsListView.ItemsSource = @()
            return
        }
        & $loadLibraryAppDetails -SelectedLibraryItem $selected
    })

$libraryPathViewBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $libraryPathViewBox.Text
        $libraryPathViewBox.Text = $normalised
        $syncHash.Config.LibraryPath = $normalised
        Set-UIConfig -Config $syncHash.Config
    })

$logVerbosityComboBox.add_SelectionChanged({
        $item = $logVerbosityComboBox.SelectedItem
        if ($null -eq $item) { return }
        $syncHash.Config.LogVerbosity = [string]$item.Content
        Set-UIConfig -Config $syncHash.Config
    })

$startupViewComboBox.add_SelectionChanged({
        $item = $startupViewComboBox.SelectedItem
        if ($null -eq $item) { return }

        $selected = [string]$item.Content
        if ([string]::IsNullOrWhiteSpace($selected)) {
            $selected = 'Apps'
        }

        $syncHash.Config.StartupView = $selected
        Set-UIConfig -Config $syncHash.Config
    })

# Navigation: Settings panel - populate form on activation
$navSettings.add_Checked({
        $outputPathBox.Text = $syncHash.Config.OutputPath
        $evergreenAppsPathBox.Text = (Get-EvergreenAppsPath)

        $desiredVerbosity = [string]$syncHash.Config.LogVerbosity
        $logVerbosityComboBox.SelectedIndex = if ($desiredVerbosity -eq 'Verbose') { 1 } else { 0 }

        switch ([string]$syncHash.Config.StartupView) {
            'Download' { $startupViewComboBox.SelectedIndex = 1 }
            'Library' { $startupViewComboBox.SelectedIndex = 2 }
            'Settings' { $startupViewComboBox.SelectedIndex = 3 }
            default { $startupViewComboBox.SelectedIndex = 0 }
        }
    })

# Theme toggle
$themeToggle.add_Click({
        if ($themeToggle.IsChecked) {
            Set-DarkTheme  -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
        }
        else {
            Set-LightTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
        }

        $syncHash.Config.Theme = if ($themeToggle.IsChecked) { 'Dark' } else { 'Light' }
        Set-UIConfig -Config $syncHash.Config
    })

# Log panel collapse / expand
# When expanded, the log area height (above the 32px status bar) is restored
# from config; when collapsed, row 3 drops to exactly the status bar height.
$logToggleButton.add_Click({
        if ($logToggleButton.IsChecked) {
            $restoreHeight = [Math]::Max(80, $syncHash.Config.LogHeight)
            $logRowDef.Height = [System.Windows.GridLength]::new(40 + $restoreHeight)
            $logToggleButton.Content = 'Hide progress log'
        }
        else {
            # Save current displayed log height before collapsing
            $currentHeight = [int]$logRowDef.Height.Value - 40
            if ($currentHeight -gt 0) { $syncHash.Config.LogHeight = $currentHeight }
            $logRowDef.Height = [System.Windows.GridLength]::new(40)
            $logToggleButton.Content = 'Show progress log'
        }
    })

# Copy log
$copyLogButton.add_Click({
        if (-not [string]::IsNullOrEmpty($syncHash.LogTextBox.Text)) {
            [System.Windows.Clipboard]::SetText($syncHash.LogTextBox.Text)
            Write-UILog -SyncHash $syncHash -Message 'Log copied to clipboard.' -Level Info
        }
    })

# Save log
$saveLogButton.add_Click({
        $dlg = [System.Windows.Forms.SaveFileDialog]::new()
        $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
        $dlg.FileName = "EvergreenUI-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $syncHash.LogTextBox.Text |
                Set-Content -Path $dlg.FileName -Encoding UTF8 -ErrorAction Stop
                Write-UILog -SyncHash $syncHash -Message "Log saved: $($dlg.FileName)" -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to save log: $_" -Level Error
            }
        }
    })

# Settings: Output path - Browse
$browseOutputButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select download output folder'
        $dlg.SelectedPath = $outputPathBox.Text
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
            $outputPathBox.Text = $normalised
            $syncHash.Config.OutputPath = $normalised
            Set-UIConfig -Config $syncHash.Config
        }
    })

# Settings: Open cache folder
$openEvergreenAppsFolderButton.add_Click({
        $folderPath = $evergreenAppsPathBox.Text
        if ([string]::IsNullOrWhiteSpace($folderPath)) { return }
        if (-not (Test-Path -LiteralPath $folderPath)) {
            $null = New-Item -ItemType Directory -Path $folderPath -Force
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $folderPath | Out-Null
    })

# Settings: Open cache folder
$openCacheFolderButton.add_Click({
        $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            $null = New-Item -ItemType Directory -Path $cacheDir -Force
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $cacheDir | Out-Null
    })

# Settings: Clear cache
$clearCacheButton.add_Click({
        $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
        if (Test-Path -LiteralPath $cacheDir) {
            try {
                $files = Get-ChildItem -LiteralPath $cacheDir -Filter '*.json' -File -ErrorAction Stop
                $count = $files.Count
                $files | Remove-Item -Force -ErrorAction Stop
                Write-UILog -SyncHash $syncHash -Message "Cache cleared. $count file(s) removed." -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to clear cache: $_" -Level Error
            }
        }
        else {
            Write-UILog -SyncHash $syncHash -Message 'Cache directory does not exist. Nothing to clear.' -Level Info
        }
    })

# Settings: persist path edits on focus-leave
$outputPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $outputPathBox.Text
        $outputPathBox.Text = $normalised
        $syncHash.Config.OutputPath = $normalised
        Set-UIConfig -Config $syncHash.Config
    })

# Show window (blocking)
[void]$window.ShowDialog()
