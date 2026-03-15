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
      persisted to $env:APPDATA\EvergreenUI\settings.json.
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
    $psd1 = (Resolve-Path -Path (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'EvergreenUI.psd1')).Path
    $sta.AddScript([scriptblock]::Create("Import-Module '$psd1'; Start-EvergreenWorkbench")) | Out-Null
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
        SettingsAutoSaveTimer      = $null
        SettingsLastSavedJson      = ''
        DownloadQueue              = [System.Collections.Generic.List[PSCustomObject]]::new()
        EvergreenVersion           = ''
        Config                     = $config
        PendingLoadTimer           = $null
        PendingLoadPS              = $null
        PendingLoadRunspace        = $null
        PendingLoadAsync           = $null
        PendingLoadAppName         = $null
        PendingNerdioAzureAuthTimer    = $null
        PendingNerdioAzureAuthPS       = $null
        PendingNerdioAzureAuthRunspace = $null
        PendingNerdioAzureAuthAsync    = $null
        PendingIntuneImportTimer       = $null
        PendingIntuneImportPS          = $null
        PendingIntuneImportRunspace    = $null
        PendingIntuneImportAsync       = $null
        IsIntuneImportLoading          = $false
        IntuneActionButtonStates       = @{}
        PendingNerdioShellAppsTimer    = $null
        PendingNerdioShellAppsPS       = $null
        PendingNerdioShellAppsRunspace = $null
        PendingNerdioShellAppsAsync    = $null
        IsNerdioShellAppsLoading       = $false
        NerdioDefinitionRows           = @()
        NerdioShellAppRows             = @()
        NerdioComparisonRows           = @()
        ImportCurrentProvider      = 'Nerdio'
        AzureAuthState             = [PSCustomObject]@{
            IsAuthenticated    = $false
            IsAuthInProgress   = $false
            AccountId          = ''
            TenantId           = ''
            SubscriptionName   = ''
            ErrorMessage       = ''
            IntuneConnected    = $false
            IntuneConnectError = ''
        }
        NerdioApiAuthState         = [PSCustomObject]@{
            IsAuthenticated  = $false
            IsAuthInProgress = $false
            AccountId        = ''
            TenantId         = ''
            ContextName      = ''
            ErrorMessage     = ''
        }
        NerdioAzureAuthState       = [PSCustomObject]@{
            IsAuthenticated  = $false
            IsAuthInProgress = $false
            AccountId        = ''
            TenantId         = ''
            SubscriptionName = ''
            ErrorMessage     = ''
        }
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
$themeComboBox = $window.FindName('ThemeComboBox')

$navApps = $window.FindName('NavApps')
$navDownload = $window.FindName('NavDownload')
$navLibrary = $window.FindName('NavLibrary')
$navImport = $window.FindName('NavImport')
$navSettings = $window.FindName('NavSettings')

$appsPanel = $window.FindName('AppsPanel')
$downloadPanel = $window.FindName('DownloadPanel')
$libraryPanel = $window.FindName('LibraryPanel')
$importPanel = $window.FindName('ImportPanel')
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
$nerdioModulePathSettingsBox = $window.FindName('NerdioModulePathSettingsBox')
$nerdioBrowseModulePathSettingsButton = $window.FindName('NerdioBrowseModulePathSettingsButton')
$nerdioReloadModuleSettingsButton = $window.FindName('NerdioReloadModuleSettingsButton')
$nerdioModuleStatusLabel = $window.FindName('NerdioModuleStatusLabel')

$importProviderTabControl = $window.FindName('ImportProviderTabControl')
$importTenantIdBox = $window.FindName('ImportTenantIdBox')
$importAuthStatusDot = $window.FindName('ImportAuthStatusDot')
$importAuthStatusLabel = $window.FindName('ImportAuthStatusLabel')
$importSignInButton = $window.FindName('ImportSignInButton')
$importSignOutButton = $window.FindName('ImportSignOutButton')
$intuneRefreshCatalogButton = $window.FindName('IntuneRefreshCatalogButton')
# Microsoft Intune controls
$intunePackageOutputPathBox              = $window.FindName('IntunePackageOutputPathBox')
$intuneBrowsePackageOutputButton         = $window.FindName('IntuneBrowsePackageOutputButton')
$intuneDefinitionsPathBox                = $window.FindName('IntuneDefinitionsPathBox')
$intuneBrowseDefinitionsButton           = $window.FindName('IntuneBrowseDefinitionsButton')
$intuneLoadDefinitionsButton             = $window.FindName('IntuneLoadDefinitionsButton')
$intuneDefinitionsCountLabel             = $window.FindName('IntuneDefinitionsCountLabel')
$intuneDefinitionsListView               = $window.FindName('IntuneDefinitionsListView')
$intuneWin32AppsCountLabel               = $window.FindName('IntuneWin32AppsCountLabel')
$intuneWin32AppsListView                 = $window.FindName('IntuneWin32AppsListView')
$intunePackageButton                     = $window.FindName('IntunePackageButton')
$intuneOnlyUnpackagedCheckBox            = $window.FindName('IntuneOnlyUnpackagedCheckBox')
$intuneActionStatusLabel                 = $window.FindName('IntuneActionStatusLabel')
$intuneImportLoadingPanel                = $window.FindName('IntuneImportLoadingPanel')
$intuneImportLoadingLabel                = $window.FindName('IntuneImportLoadingLabel')
$intuneImportProgressBar                 = $window.FindName('IntuneImportProgressBar')
# Intune Settings controls
$intuneReloadModuleSettingsButton        = $window.FindName('IntuneReloadModuleSettingsButton')
$intuneSettingsModuleStatusDot           = $window.FindName('IntuneSettingsModuleStatusDot')
$intuneSettingsModuleStatusLabel         = $window.FindName('IntuneSettingsModuleStatusLabel')
# Nerdio Shell Apps controls
$nmeHostBox                  = $window.FindName('NmeHostBox')
$nmeClientIdBox              = $window.FindName('NmeClientIdBox')
$nmeApiScopeBox              = $window.FindName('NmeApiScopeBox')
$nmeOAuthTokenUrlBox         = $window.FindName('NmeOAuthTokenUrlBox')
$nmeClientSecretBox          = $window.FindName('NmeClientSecretBox')
$nmeSubscriptionIdBox        = $window.FindName('NmeSubscriptionIdBox')
$nmeResourceGroupCombo       = $window.FindName('NmeResourceGroupCombo')
$nmeStorageAccountCombo      = $window.FindName('NmeStorageAccountCombo')
$nmeContainerCombo           = $window.FindName('NmeContainerCombo')
$nerdioTenantIdBox           = $window.FindName('NerdioTenantIdBox')
$nerdioApiAuthStatusDot      = $window.FindName('NerdioApiAuthStatusDot')
$nerdioApiAuthStatusLabel    = $window.FindName('NerdioApiAuthStatusLabel')
$nerdioApiSignInButton       = $window.FindName('NerdioApiSignInButton')
$nerdioApiSignOutButton      = $window.FindName('NerdioApiSignOutButton')
$nerdioDefinitionsPathBox      = $window.FindName('NerdioDefinitionsPathBox')
$nerdioBrowseDefinitionsButton = $window.FindName('NerdioBrowseDefinitionsButton')
$nerdioLoadDefinitionsButton   = $window.FindName('NerdioLoadDefinitionsButton')
$nerdioListShellAppsButton     = $window.FindName('NerdioListShellAppsButton')
$nerdioDefinitionsListView     = $window.FindName('NerdioDefinitionsListView')
$nerdioShellAppsListView       = $window.FindName('NerdioShellAppsListView')
$nerdioDefinitionsCountLabel   = $window.FindName('NerdioDefinitionsCountLabel')
$nerdioShellAppsCountLabel     = $window.FindName('NerdioShellAppsCountLabel')
$nerdioShellAppsLoadingPanel   = $window.FindName('NerdioShellAppsLoadingPanel')
$nerdioShellAppsLoadingLabel   = $window.FindName('NerdioShellAppsLoadingLabel')
$nerdioShellAppsProgressBar    = $window.FindName('NerdioShellAppsProgressBar')
$nerdioAddVersionButton        = $window.FindName('NerdioAddVersionButton')
$nerdioImportNewButton         = $window.FindName('NerdioImportNewButton')
$nerdioCompareUpdatesButton    = $window.FindName('NerdioCompareUpdatesButton')
$nerdioActionStatusLabel       = $window.FindName('NerdioActionStatusLabel')
$nerdioAzureAuthStatusDot      = $window.FindName('NerdioAzureAuthStatusDot')
$nerdioAzureAuthStatusLabel    = $window.FindName('NerdioAzureAuthStatusLabel')
$nerdioAzureSignInButton       = $window.FindName('NerdioAzureSignInButton')
$nerdioAzureSignOutButton      = $window.FindName('NerdioAzureSignOutButton')
$intunePreviewImportButton = $window.FindName('IntunePreviewImportButton')
$intuneApplyImportButton = $window.FindName('IntuneApplyImportButton')
# Log row is RowDefinitions[3]; track its height for collapse/restore
$logRowDef = $rootGrid.RowDefinitions[3]

# Store refs needed by background-runspace callbacks
$syncHash.ImportTenantIdBox = $importTenantIdBox

$setNerdioShellAppsLoadingState = {
    param(
        [bool]$IsLoading,
        [string]$Message = ''
    )

    $syncHash.IsNerdioShellAppsLoading = $IsLoading

    if ($null -ne $nerdioListShellAppsButton) {
        $nerdioListShellAppsButton.IsEnabled = -not $IsLoading
    }

    if ($null -ne $nerdioCompareUpdatesButton) {
        $nerdioCompareUpdatesButton.IsEnabled = -not $IsLoading
    }

    if ($null -ne $nerdioShellAppsLoadingPanel) {
        $nerdioShellAppsLoadingPanel.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
    }

    if ($null -ne $nerdioShellAppsLoadingLabel) {
        if ($IsLoading -and -not [string]::IsNullOrWhiteSpace($Message)) {
            $nerdioShellAppsLoadingLabel.Text = $Message
        }
        elseif (-not $IsLoading) {
            $nerdioShellAppsLoadingLabel.Text = 'Loading Shell Apps from Nerdio Manager...'
        }
    }

    if ($null -ne $nerdioShellAppsProgressBar) {
        $nerdioShellAppsProgressBar.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
    }

    if ($IsLoading -and $null -ne $nerdioShellAppsCountLabel) {
        $nerdioShellAppsCountLabel.Text = 'Loading...'
    }
}

$setIntuneImportLoadingState = {
    param(
        [bool]$IsLoading,
        [string]$Message = ''
    )

    $syncHash.IsIntuneImportLoading = $IsLoading

    foreach ($button in @($intuneRefreshCatalogButton, $intunePreviewImportButton, $intuneApplyImportButton)) {
        if ($null -eq $button) {
            continue
        }

        if ($IsLoading) {
            $syncHash.IntuneActionButtonStates[$button.Name] = [bool]$button.IsEnabled
            $button.IsEnabled = $false
        }
        else {
            if ($syncHash.IntuneActionButtonStates.ContainsKey($button.Name)) {
                $button.IsEnabled = [bool]$syncHash.IntuneActionButtonStates[$button.Name]
            }
        }
    }

    if (-not $IsLoading) {
        $syncHash.IntuneActionButtonStates.Clear()
    }

    if ($null -ne $intuneImportLoadingPanel) {
        $intuneImportLoadingPanel.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
    }

    if ($null -ne $intuneImportLoadingLabel) {
        if ($IsLoading -and -not [string]::IsNullOrWhiteSpace($Message)) {
            $intuneImportLoadingLabel.Text = $Message
        }
        elseif (-not $IsLoading) {
            $intuneImportLoadingLabel.Text = 'Working...'
        }
    }

    if ($null -ne $intuneImportProgressBar) {
        $intuneImportProgressBar.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
    }

    if ($null -ne $intuneActionStatusLabel) {
        if ($IsLoading) {
            $intuneActionStatusLabel.Text = if ([string]::IsNullOrWhiteSpace($Message)) { 'Working...' } else { $Message }
        }
        else {
            $intuneActionStatusLabel.Text = ''
        }
    }
}

$startIntuneImportOperation = {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)][string]$LoadingMessage,
        [Parameter(Mandatory = $true)][string]$CompletionMessage
    )

    if ($syncHash.IsIntuneImportLoading) {
        Write-UILog -SyncHash $syncHash -Message "Intune: another import action is already in progress." -Level Warning
        return
    }

    if ($null -ne $syncHash.PendingIntuneImportTimer -and $syncHash.PendingIntuneImportTimer.IsEnabled) {
        $syncHash.PendingIntuneImportTimer.Stop()
        $syncHash.PendingIntuneImportTimer = $null
    }

    foreach ($pendingOp in @('PendingIntuneImportPS', 'PendingIntuneImportRunspace', 'PendingIntuneImportAsync')) {
        $syncHash[$pendingOp] = $null
    }

    & $setIntuneImportLoadingState -IsLoading $true -Message $LoadingMessage
    Write-UILog -SyncHash $syncHash -Message "Intune: $ActionName started." -Level Info

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param([string]$OperationName)

            Start-Sleep -Milliseconds 1200

            return [PSCustomObject]@{
                Success = $true
                Action  = $OperationName
            }
        }).AddArgument($ActionName)

    $syncHash.PendingIntuneImportPS = $ps
    $syncHash.PendingIntuneImportRunspace = $rs
    $syncHash.PendingIntuneImportAsync = $ps.BeginInvoke()

    $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $syncHash.PendingIntuneImportTimer = $pollTimer

    $pollTimer.add_Tick({
            if ($null -eq $syncHash.PendingIntuneImportAsync -or -not $syncHash.PendingIntuneImportAsync.IsCompleted) {
                return
            }

            if ($null -ne $syncHash.PendingIntuneImportTimer) {
                $syncHash.PendingIntuneImportTimer.Stop()
                $syncHash.PendingIntuneImportTimer = $null
            }

            try {
                [void]$syncHash.PendingIntuneImportPS.EndInvoke($syncHash.PendingIntuneImportAsync)
                Write-UILog -SyncHash $syncHash -Message $CompletionMessage -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Intune: $ActionName failed: $($_.Exception.Message)" -Level Error
            }
            finally {
                try { $syncHash.PendingIntuneImportPS.Dispose() } catch {}
                try { $syncHash.PendingIntuneImportRunspace.Dispose() } catch {}

                $syncHash.PendingIntuneImportPS = $null
                $syncHash.PendingIntuneImportRunspace = $null
                $syncHash.PendingIntuneImportAsync = $null

                & $setIntuneImportLoadingState -IsLoading $false
            }
        })

    $pollTimer.Start()
}

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

$normalizeImportProvider = {
    param([string]$Provider)

    if ([string]::IsNullOrWhiteSpace($Provider)) {
        return 'Nerdio'
    }

    switch -Regex ($Provider.Trim()) {
        '^Nerdio(\s+Manager)?$' { return 'Nerdio' }
        '^Intune$' { return 'Intune' }
        '^Microsoft\s+Intune$' { return 'Intune' }
        default { return 'Nerdio' }
    }
}

$setImportProvider = {
    param(
        [string]$Provider,
        [switch]$Persist
    )

    $resolvedProvider = & $normalizeImportProvider -Provider $Provider
    $syncHash.ImportCurrentProvider = $resolvedProvider

    if ($null -eq $syncHash.Config.ImportSettings) {
        $syncHash.Config | Add-Member -NotePropertyName 'ImportSettings' -NotePropertyValue ([PSCustomObject]@{ CurrentProvider = $resolvedProvider }) -Force
    }
    else {
        $syncHash.Config.ImportSettings.CurrentProvider = $resolvedProvider
    }

    $targetIndex = if ($resolvedProvider -eq 'Intune') { 0 } else { 1 }
    if ($importProviderTabControl.SelectedIndex -ne $targetIndex) {
        $importProviderTabControl.SelectedIndex = $targetIndex
    }

    if ($Persist) {
        Set-UIConfig -Config $syncHash.Config
    }
}

$normalizeDirectoryPath = {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ''
    }

    return $PathValue.Trim().Trim('"')
}

$getCurrentStartupView = {
    if ($navDownload.IsChecked) {
        return 'Download'
    }
    elseif ($navLibrary.IsChecked) {
        return 'Library'
    }
    elseif ($navImport.IsChecked) {
        return 'Import'
    }
    elseif ($navSettings.IsChecked) {
        return 'Settings'
    }

    return 'Apps'
}

$persistUiSettingsSnapshot = {
    param([switch]$ForceWrite)

    $syncHash.Config.OutputPath = & $normalizeDirectoryPath -PathValue ([string]$outputPathBox.Text)
    $syncHash.Config.LibraryPath = & $normalizeDirectoryPath -PathValue ([string]$libraryPathViewBox.Text)
    $syncHash.Config.Theme = if ($themeComboBox.SelectedIndex -eq 1) { 'Dark' } else { 'Light' }
    $syncHash.Config.WindowWidth = [int]$window.Width
    $syncHash.Config.WindowHeight = [int]$window.Height
    $syncHash.Config.LastAppName = if ($null -ne $appsComboBox.SelectedItem) { [string]$appsComboBox.SelectedItem.Name } else { '' }
    $syncHash.Config.StartupView = & $getCurrentStartupView
    $syncHash.Config.LogVisible = [bool]$logToggleButton.IsChecked

    if ($syncHash.Config.LogVisible) {
        $currentLogHeight = [int]$logRowDef.Height.Value - 40
        if ($currentLogHeight -gt 0) {
            $syncHash.Config.LogHeight = $currentLogHeight
        }
    }

    $syncHash.Config.NerdioSettings.ModulePath = & $normalizeDirectoryPath -PathValue ([string]$nerdioModulePathSettingsBox.Text)
    $syncHash.Config.NerdioSettings.NmeHost = [string]$nmeHostBox.Text
    $syncHash.Config.NerdioSettings.NmeClientId = [string]$nmeClientIdBox.Text
    $syncHash.Config.NerdioSettings.NmeApiScope = [string]$nmeApiScopeBox.Text
    $syncHash.Config.NerdioSettings.NmeOAuthTokenUrl = [string]$nmeOAuthTokenUrlBox.Text
    $syncHash.Config.NerdioSettings.NmeSubscriptionId = [string]$nmeSubscriptionIdBox.Text
    $syncHash.Config.NerdioSettings.DefinitionsPath = & $normalizeDirectoryPath -PathValue ([string]$nerdioDefinitionsPathBox.Text)

    $syncHash.Config.IntuneSettings.DefinitionsPath = & $normalizeDirectoryPath -PathValue ([string]$intuneDefinitionsPathBox.Text)
    $syncHash.Config.IntuneSettings.PackageOutputPath = & $normalizeDirectoryPath -PathValue ([string]$intunePackageOutputPathBox.Text)

    $syncHash.Config.AzureAuthSettings.TenantId = [string]$importTenantIdBox.Text
    $syncHash.Config.AzureAuthSettings.NerdioTenantId = [string]$nerdioTenantIdBox.Text

    if ($null -eq $syncHash.Config.ImportSettings) {
        $syncHash.Config | Add-Member -NotePropertyName 'ImportSettings' -NotePropertyValue ([PSCustomObject]@{ CurrentProvider = $syncHash.ImportCurrentProvider }) -Force
    }
    else {
        $syncHash.Config.ImportSettings.CurrentProvider = $syncHash.ImportCurrentProvider
    }

    $snapshotJson = $syncHash.Config | ConvertTo-Json -Depth 5
    if ($ForceWrite -or $snapshotJson -ne $syncHash.SettingsLastSavedJson) {
        Set-UIConfig -Config $syncHash.Config
        $syncHash.SettingsLastSavedJson = $snapshotJson
    }
}

$refreshImportAuthUi = {
    $state = $syncHash.AzureAuthState
    if ($state.IsAuthInProgress) {
        $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::Gold
        $importAuthStatusLabel.Text = 'Signing in...'
        $importSignInButton.IsEnabled = $false
        $importSignOutButton.IsEnabled = $false
        return
    }

    if ($state.IsAuthenticated) {
        $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
        $account = if ([string]::IsNullOrWhiteSpace($state.AccountId)) { 'signed in' } else { $state.AccountId }
        $tenant  = if ([string]::IsNullOrWhiteSpace($state.TenantId)) { '' } else { " | tenant: $($state.TenantId)" }
        $intune  = if ($state.IntuneConnected) { ' | Intune: connected' } else { '' }
        $importAuthStatusLabel.Text = "$account$tenant$intune"
        $importSignInButton.IsEnabled = $true
        $importSignOutButton.IsEnabled = $true
        return
    }

    $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
    if ([string]::IsNullOrWhiteSpace($state.ErrorMessage)) {
        $importAuthStatusLabel.Text = 'Not signed in'
    }
    else {
        $importAuthStatusLabel.Text = 'Sign-in failed'
    }
    $importSignInButton.IsEnabled = $true
    $importSignOutButton.IsEnabled = $false
}

$syncHash.RefreshImportAuthUi = $refreshImportAuthUi

$refreshNerdioApiAuthUi = {
    $state = $syncHash.NerdioApiAuthState
    if ($state.IsAuthInProgress) {
        $nerdioApiAuthStatusDot.Fill = [System.Windows.Media.Brushes]::Gold
        $nerdioApiAuthStatusLabel.Text = 'Signing in...'
        $nerdioApiSignInButton.IsEnabled = $false
        $nerdioApiSignOutButton.IsEnabled = $false
        return
    }

    if ($state.IsAuthenticated) {
        $nerdioApiAuthStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
        $hostName = [string]$state.ContextName
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = [string]$nmeHostBox.Text
        }
        $nerdioApiAuthStatusLabel.Text = if ([string]::IsNullOrWhiteSpace($hostName)) { 'Connected' } else { $hostName }
        $nerdioApiSignInButton.IsEnabled = $true
        $nerdioApiSignOutButton.IsEnabled = $true
        return
    }

    $nerdioApiAuthStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
    if ([string]::IsNullOrWhiteSpace($state.ErrorMessage)) {
        $nerdioApiAuthStatusLabel.Text = 'Not signed in'
    }
    else {
        $nerdioApiAuthStatusLabel.Text = 'Sign-in failed'
    }
    $nerdioApiSignInButton.IsEnabled = $true
    $nerdioApiSignOutButton.IsEnabled = $false
}

$refreshNerdioAzureAuthUi = {
    $state = $syncHash.NerdioAzureAuthState
    if ($state.IsAuthInProgress) {
        $nerdioAzureAuthStatusDot.Fill = [System.Windows.Media.Brushes]::Gold
        $nerdioAzureAuthStatusLabel.Text = 'Signing in...'
        $nerdioAzureSignInButton.IsEnabled = $false
        $nerdioAzureSignOutButton.IsEnabled = $false
        return
    }

    if ($state.IsAuthenticated) {
        $nerdioAzureAuthStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
        $account = if ([string]::IsNullOrWhiteSpace($state.AccountId)) { 'signed in' } else { $state.AccountId }
        $tenant = if ([string]::IsNullOrWhiteSpace($state.TenantId)) { '' } else { " | tenant: $($state.TenantId)" }
        $sub = if ([string]::IsNullOrWhiteSpace($state.SubscriptionName)) { '' } else { " | sub: $($state.SubscriptionName)" }
        $nerdioAzureAuthStatusLabel.Text = "$account$tenant$sub"
        $nerdioAzureSignInButton.IsEnabled = $true
        $nerdioAzureSignOutButton.IsEnabled = $true
        return
    }

    $nerdioAzureAuthStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
    if ([string]::IsNullOrWhiteSpace($state.ErrorMessage)) {
        $nerdioAzureAuthStatusLabel.Text = 'Not signed in'
    }
    else {
        $nerdioAzureAuthStatusLabel.Text = 'Sign-in failed'
    }
    $nerdioAzureSignInButton.IsEnabled = $true
    $nerdioAzureSignOutButton.IsEnabled = $false
}

$isImportAuthReady = {
    return [bool]$syncHash.AzureAuthState.IsAuthenticated
}

$isNerdioApiAuthReady = {
    return [bool]$syncHash.NerdioApiAuthState.IsAuthenticated
}

$isNerdioAzureAuthReady = {
    return [bool]$syncHash.NerdioAzureAuthState.IsAuthenticated
}

$requireImportAuth = {
    param(
        [string]$ActionName,
        [string]$Provider = 'Intune'
    )

    if ($Provider -eq 'Nerdio') {
        if (& $isNerdioApiAuthReady) {
            return $true
        }

        Write-UILog -SyncHash $syncHash -Message "$ActionName requires Nerdio Manager API sign-in on the Nerdio Manager tab." -Level Warning
        return $false
    }

    if (& $isImportAuthReady) {
        return $true
    }

        Write-UILog -SyncHash $syncHash -Message "$ActionName requires Entra ID sign-in in the Intune tab." -Level Warning
    return $false
}

$applyImportTenantToConfig = {
    $tenantText = if ($null -eq $importTenantIdBox) { '' } else { [string]$importTenantIdBox.Text }
    $syncHash.Config.AzureAuthSettings.TenantId = $tenantText.Trim()
    Set-UIConfig -Config $syncHash.Config
}

$applyNerdioTenantToConfig = {
    $tenantText = if ($null -eq $nerdioTenantIdBox) { '' } else { [string]$nerdioTenantIdBox.Text }
    $syncHash.Config.AzureAuthSettings.NerdioTenantId = $tenantText.Trim()
    Set-UIConfig -Config $syncHash.Config
}

$applyNerdioDefinitionsPathToConfig = {
    $definitionsPath = if ($null -eq $nerdioDefinitionsPathBox) { '' } else { [string]$nerdioDefinitionsPathBox.Text }
    $syncHash.Config.NerdioSettings.DefinitionsPath = (& $normalizeDirectoryPath -PathValue $definitionsPath)
    Set-UIConfig -Config $syncHash.Config
}

$applyIntunePathsToConfig = {
    $definitionsPath = if ($null -eq $intuneDefinitionsPathBox) { '' } else { [string]$intuneDefinitionsPathBox.Text }
    $packageOutputPath = if ($null -eq $intunePackageOutputPathBox) { '' } else { [string]$intunePackageOutputPathBox.Text }

    $syncHash.Config.IntuneSettings.DefinitionsPath = (& $normalizeDirectoryPath -PathValue $definitionsPath)
    $syncHash.Config.IntuneSettings.PackageOutputPath = (& $normalizeDirectoryPath -PathValue $packageOutputPath)
    Set-UIConfig -Config $syncHash.Config
}

$refreshNerdioModuleStatus = {
    param(
        [bool]$IsLoaded,
        [string]$Message
    )

    if ($null -eq $nerdioModuleStatusLabel) { return }

    if ($IsLoaded) {
        $nerdioModuleStatusLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    else {
        $nerdioModuleStatusLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
    }

    $nerdioModuleStatusLabel.Text = $Message
}

$loadNerdioShellAppsModule = {
    param([switch]$Force)

    $pathValue = [string]$nerdioModulePathSettingsBox.Text
    $path = & $normalizeDirectoryPath -PathValue $pathValue
    $nerdioModulePathSettingsBox.Text = $path
    $syncHash.Config.NerdioSettings.ModulePath = $path
    Set-UIConfig -Config $syncHash.Config

    if ([string]::IsNullOrWhiteSpace($path)) {
        & $refreshNerdioModuleStatus -IsLoaded $false -Message 'NerdioShellApps module path is not configured.'
        return $false
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        & $refreshNerdioModuleStatus -IsLoaded $false -Message "Module file not found: $path"
        Write-UILog -SyncHash $syncHash -Message "Nerdio module was not loaded because the file was not found: $path" -Level Warning
        return $false
    }

    try {
        if ($Force) {
            Remove-Module -Name NerdioShellApps -ErrorAction SilentlyContinue
        }

        Import-Module -Name $path -Force:$Force -ErrorAction Stop | Out-Null
        & $refreshNerdioModuleStatus -IsLoaded $true -Message "Loaded module: $path"
        Write-UILog -SyncHash $syncHash -Message "Loaded NerdioShellApps module from '$path'." -Level Info
        return $true
    }
    catch {
        & $refreshNerdioModuleStatus -IsLoaded $false -Message "Failed to load module: $($_.Exception.Message)"
        Write-UILog -SyncHash $syncHash -Message "Failed to load NerdioShellApps module: $($_.Exception.Message)" -Level Error
        return $false
    }
}

$getNerdioShellAppsCommand = {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $qualifiedName = "NerdioShellApps\$Name"
    $cmd = Get-Command -Name $qualifiedName -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd
    }

    return (Get-Command -Name $Name -Module NerdioShellApps -ErrorAction SilentlyContinue)
}

$parseComparableVersion = {
    param(
        [AllowNull()]
        [string]$VersionText
    )

    $raw = if ($null -eq $VersionText) { '' } else { [string]$VersionText }
    $trimmed = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return [PSCustomObject]@{
            Success    = $false
            Raw        = $raw
            Normalized = ''
            Parsed     = $null
            Error      = 'Version is empty.'
        }
    }

    $match = [regex]::Match($trimmed, '\d+(\.\d+){0,3}')
    $normalized = ''
    if ($match.Success) {
        $normalized = $match.Value
    }
    else {
        $normalized = ($trimmed -replace '[^0-9\.]', '').Trim('.')
    }

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return [PSCustomObject]@{
            Success    = $false
            Raw        = $raw
            Normalized = ''
            Parsed     = $null
            Error      = 'Version has no numeric segments.'
        }
    }

    $segments = @($normalized.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -eq 0) {
        return [PSCustomObject]@{
            Success    = $false
            Raw        = $raw
            Normalized = ''
            Parsed     = $null
            Error      = 'Version has no valid numeric segments.'
        }
    }

    if ($segments.Count -gt 4) {
        $segments = @($segments | Select-Object -First 4)
    }

    $normalized = ($segments -join '.')
    try {
        return [PSCustomObject]@{
            Success    = $true
            Raw        = $raw
            Normalized = $normalized
            Parsed     = [version]$normalized
            Error      = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            Success    = $false
            Raw        = $raw
            Normalized = $normalized
            Parsed     = $null
            Error      = $_.Exception.Message
        }
    }
}

$getEvergreenMetadataForDefinition = {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DefinitionRow
    )

    if ($null -eq $DefinitionRow.DefinitionObject) {
        return $null
    }

    $getAppMetadataCommand = & $getNerdioShellAppsCommand -Name 'Get-AppMetadata'
    if ($null -eq $getAppMetadataCommand) {
        throw 'Required command Get-AppMetadata was not found in NerdioShellApps module.'
    }

    return (& $getAppMetadataCommand -Definition $DefinitionRow.DefinitionObject)
}

$refreshNerdioComparison = {
    $definitionRows = @($syncHash.NerdioDefinitionRows)
    $shellAppRows = @($syncHash.NerdioShellAppRows)

    if ($definitionRows.Count -eq 0) {
        $syncHash.NerdioComparisonRows = @()
        $nerdioDefinitionsListView.ItemsSource = @()
        $nerdioDefinitionsCountLabel.Text = '0 loaded'
        if ($null -ne $nerdioActionStatusLabel) {
            $nerdioActionStatusLabel.Text = ''
        }
        return
    }

    $evergreenCache = @{}
    $comparisonRows = [System.Collections.Generic.List[object]]::new()

    $matchedCount = 0
    $updateCount = 0
    $compareUnavailableCount = 0
    $unmatchedCount = 0

    foreach ($definitionRow in $definitionRows) {
        $publisher = [string]$definitionRow.Publisher
        $appName = [string]$definitionRow.AppName
        $definitionValid = [string]$definitionRow.DefinitionValid
        $sourceType = [string]$definitionRow.SourceType

        $baseRow = [PSCustomObject]@{
            DefinitionPath    = $definitionRow.DefinitionPath
            Publisher         = $publisher
            AppName           = $appName
            DefinitionValid   = $definitionValid
            MatchStatus       = '-'
            NerdioVersion     = '-'
            EvergreenVersion  = '-'
            UpdateNeeded      = '-'
            CompareMessage    = ''
            MatchedShellAppId = ''
        }

        if ($definitionValid -ne 'Yes') {
            $baseRow.MatchStatus = 'Invalid definition'
            $comparisonRows.Add($baseRow)
            continue
        }

        if ($sourceType -ine 'Evergreen') {
            $baseRow.MatchStatus = 'Unsupported source type'
            $baseRow.CompareMessage = "Source type '$sourceType' is not supported for compare."
            $comparisonRows.Add($baseRow)
            continue
        }

        $matches = @(
            $shellAppRows | Where-Object {
                [string]$_.Publisher -ieq $publisher -and [string]$_.Name -ieq $appName
            }
        )

        if ($matches.Count -eq 0) {
            $baseRow.MatchStatus = 'No matching Shell App'
            $baseRow.CompareMessage = 'No existing Shell App matched by publisher and name.'
            $comparisonRows.Add($baseRow)
            $unmatchedCount++
            continue
        }

        if ($matches.Count -gt 1) {
            $baseRow.MatchStatus = 'Duplicate matches'
            $baseRow.CompareMessage = 'More than one Shell App matched by publisher and name.'
            $comparisonRows.Add($baseRow)
            $unmatchedCount++
            continue
        }

        $matchedShellApp = $matches[0]
        $baseRow.MatchStatus = 'Matched'
        $baseRow.MatchedShellAppId = [string]$matchedShellApp.Id
        $baseRow.NerdioVersion = [string]$matchedShellApp.LatestVersion
        $matchedCount++

        $cacheKey = "{0}|{1}" -f ([string]$definitionRow.SourceApp).Trim(), ([string]$definitionRow.SourceFilter).Trim()
        $evergreenMetadata = $null
        if ($evergreenCache.ContainsKey($cacheKey)) {
            $evergreenMetadata = $evergreenCache[$cacheKey]
        }
        else {
            try {
                $evergreenMetadata = & $getEvergreenMetadataForDefinition -DefinitionRow $definitionRow
                $evergreenCache[$cacheKey] = $evergreenMetadata
            }
            catch {
                $baseRow.CompareMessage = "Evergreen lookup failed: $($_.Exception.Message)"
                $baseRow.UpdateNeeded = 'Compare unavailable'
                $comparisonRows.Add($baseRow)
                $compareUnavailableCount++
                continue
            }
        }

        if ($null -eq $evergreenMetadata -or [string]::IsNullOrWhiteSpace([string]$evergreenMetadata.Version)) {
            $baseRow.CompareMessage = 'Evergreen lookup returned no version.'
            $baseRow.UpdateNeeded = 'Compare unavailable'
            $comparisonRows.Add($baseRow)
            $compareUnavailableCount++
            continue
        }

        $baseRow.EvergreenVersion = [string]$evergreenMetadata.Version

        $nerdioParsed = & $parseComparableVersion -VersionText ([string]$baseRow.NerdioVersion)
        $evergreenParsed = & $parseComparableVersion -VersionText ([string]$baseRow.EvergreenVersion)

        if (-not $nerdioParsed.Success -or -not $evergreenParsed.Success) {
            $baseRow.UpdateNeeded = 'Compare unavailable'
            $baseRow.CompareMessage = "Unable to parse versions. Nerdio='$($baseRow.NerdioVersion)' Evergreen='$($baseRow.EvergreenVersion)'"
            $comparisonRows.Add($baseRow)
            $compareUnavailableCount++
            continue
        }

        if ($evergreenParsed.Parsed -gt $nerdioParsed.Parsed) {
            $baseRow.UpdateNeeded = 'Yes'
            $baseRow.CompareMessage = 'Evergreen version is newer than Nerdio latest version.'
            $updateCount++
        }
        else {
            $baseRow.UpdateNeeded = 'No'
            $baseRow.CompareMessage = 'Nerdio latest version is current.'
        }

        $comparisonRows.Add($baseRow)
    }

    $sortedRows = @($comparisonRows | Sort-Object -Property Publisher, AppName, DefinitionPath)
    $syncHash.NerdioComparisonRows = $sortedRows
    $nerdioDefinitionsListView.ItemsSource = $sortedRows

    $validCount = @($sortedRows | Where-Object { $_.DefinitionValid -eq 'Yes' }).Count
    $nerdioDefinitionsCountLabel.Text = "$($sortedRows.Count) loaded ($validCount valid, $matchedCount matched, $updateCount update needed)"

    if ($null -ne $nerdioActionStatusLabel) {
        $nerdioActionStatusLabel.Text = "Compared $($sortedRows.Count) definition(s): $matchedCount matched, $updateCount update needed, $compareUnavailableCount compare unavailable, $unmatchedCount unmatched."
    }

    Write-UILog -SyncHash $syncHash -Message "Nerdio compare complete: $($sortedRows.Count) definition(s), $matchedCount matched, $updateCount update needed, $compareUnavailableCount compare unavailable, $unmatchedCount unmatched." -Level Info
}

$loadNerdioDefinitions = {
    $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$nerdioDefinitionsPathBox.Text)
    $nerdioDefinitionsPathBox.Text = $definitionsRoot
    & $applyNerdioDefinitionsPathToConfig

    if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
        $syncHash.NerdioDefinitionRows = @()
        $syncHash.NerdioComparisonRows = @()
        $nerdioDefinitionsListView.ItemsSource = @()
        $nerdioDefinitionsCountLabel.Text = '0 loaded'
        if ($null -ne $nerdioActionStatusLabel) {
            $nerdioActionStatusLabel.Text = ''
        }
        Write-UILog -SyncHash $syncHash -Message 'Nerdio: provide a definitions folder path first.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $definitionsRoot -PathType Container)) {
        $syncHash.NerdioDefinitionRows = @()
        $syncHash.NerdioComparisonRows = @()
        $nerdioDefinitionsListView.ItemsSource = @()
        $nerdioDefinitionsCountLabel.Text = '0 loaded'
        if ($null -ne $nerdioActionStatusLabel) {
            $nerdioActionStatusLabel.Text = ''
        }
        Write-UILog -SyncHash $syncHash -Message "Nerdio: definitions path does not exist: $definitionsRoot" -Level Warning
        return
    }

    try {
        $topLevelDirectories = @(Get-ChildItem -LiteralPath $definitionsRoot -Directory -ErrorAction Stop)
        $definitionFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

        foreach ($directory in $topLevelDirectories) {
            $definitionMatches = @(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File -ErrorAction Stop |
                    Where-Object { $_.Name -ieq 'definition.json' })

            foreach ($match in $definitionMatches) {
                $definitionFiles.Add($match)
            }
        }
    }
    catch {
        $syncHash.NerdioDefinitionRows = @()
        $syncHash.NerdioComparisonRows = @()
        $nerdioDefinitionsListView.ItemsSource = @()
        $nerdioDefinitionsCountLabel.Text = '0 loaded'
        if ($null -ne $nerdioActionStatusLabel) {
            $nerdioActionStatusLabel.Text = ''
        }
        Write-UILog -SyncHash $syncHash -Message "Nerdio: failed to enumerate definitions: $($_.Exception.Message)" -Level Error
        return
    }

    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($definitionFile in $definitionFiles) {
        $definitionPath = [string](Split-Path -Path $definitionFile.FullName -Parent)
        $publisher = '-'
        $appName = [string](Split-Path -Path $definitionFile.DirectoryName -Leaf)
        $definitionValid = 'No'
        $sourceType = ''
        $sourceApp = ''
        $sourceFilter = ''
        $definitionObject = $null

        try {
            $definition = Get-Content -LiteralPath $definitionFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $definitionObject = $definition

            $publisherProperty = @(
                $definition.PSObject.Properties['publisher'],
                $definition.PSObject.Properties['Publisher'],
                $definition.PSObject.Properties['vendor'],
                $definition.PSObject.Properties['manufacturer']
            ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

            $appNameProperty = @(
                $definition.PSObject.Properties['name'],
                $definition.PSObject.Properties['Name'],
                $definition.PSObject.Properties['displayName'],
                $definition.PSObject.Properties['appName'],
                $definition.PSObject.Properties['title']
            ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

            if ($null -ne $publisherProperty) {
                $publisher = ([string]$publisherProperty.Value).Trim()
            }

            if ($null -ne $appNameProperty) {
                $appName = ([string]$appNameProperty.Value).Trim()
            }

            if ($null -ne $publisherProperty -and $null -ne $appNameProperty) {
                $definitionValid = 'Yes'
            }
            else {
                $definitionValid = 'No (missing JSON properties)'
            }

            if ($definition.PSObject.Properties.Name -contains 'source' -and $null -ne $definition.source) {
                $sourceType = [string]$definition.source.type
                $sourceApp = [string]$definition.source.app
                $sourceFilter = [string]$definition.source.filter
            }
        }
        catch {
            $definitionValid = 'No (invalid JSON)'
        }

        $rows.Add([PSCustomObject]@{
                DefinitionPath  = $definitionPath
                Publisher       = $publisher
                AppName         = $appName
                DefinitionValid = $definitionValid
                SourceType      = $sourceType
                SourceApp       = $sourceApp
                SourceFilter    = $sourceFilter
                DefinitionObject = $definitionObject
            })
    }

    $sortedRows = @($rows | Sort-Object -Property DefinitionPath, Publisher, AppName)
    $syncHash.NerdioDefinitionRows = $sortedRows
    & $refreshNerdioComparison

    $validCount = @($sortedRows | Where-Object { $_.DefinitionValid -eq 'Yes' }).Count

    if ($sortedRows.Count -eq 0) {
        Write-UILog -SyncHash $syncHash -Message "Nerdio: no definition.json files found under sub-directories of '$definitionsRoot'." -Level Warning
    }
    else {
        Write-UILog -SyncHash $syncHash -Message "Nerdio: loaded $($sortedRows.Count) Shell App definitions ($validCount valid)." -Level Info
    }
}

$loadNerdioShellApps = {
    if ($syncHash.IsNerdioShellAppsLoading) {
        return
    }

    if (-not (& $loadNerdioShellAppsModule)) {
        $syncHash.NerdioShellAppRows = @()
        $nerdioShellAppsListView.ItemsSource = @()
        $nerdioShellAppsCountLabel.Text = '0 apps'
        & $refreshNerdioComparison
        return
    }

    if ($null -ne $syncHash.PendingNerdioShellAppsTimer -and $syncHash.PendingNerdioShellAppsTimer.IsEnabled) {
        $syncHash.PendingNerdioShellAppsTimer.Stop()
        $syncHash.PendingNerdioShellAppsTimer = $null
    }

    foreach ($pendingOp in @('PendingNerdioShellAppsPS', 'PendingNerdioShellAppsRunspace', 'PendingNerdioShellAppsAsync')) {
        $syncHash[$pendingOp] = $null
    }

    $modulePath = & $normalizeDirectoryPath -PathValue ([string]$nerdioModulePathSettingsBox.Text)
    if ([string]::IsNullOrWhiteSpace($modulePath) -or -not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        $syncHash.NerdioShellAppRows = @()
        $nerdioShellAppsListView.ItemsSource = @()
        $nerdioShellAppsCountLabel.Text = '0 apps'
        Write-UILog -SyncHash $syncHash -Message 'Nerdio: module path is not configured or does not exist.' -Level Error
        & $refreshNerdioComparison
        return
    }

    & $setNerdioShellAppsLoadingState -IsLoading $true -Message 'Retrieving Shell Apps from Nerdio Manager...'
    Write-UILog -SyncHash $syncHash -Message 'Nerdio: retrieving Shell Apps from Nerdio Manager...' -Level Info

    $nerdioAuthContext = [PSCustomObject]@{
        TenantId       = [string]$nerdioTenantIdBox.Text
        NmeHost        = [string]$nmeHostBox.Text
        ClientId       = [string]$nmeClientIdBox.Text
        ApiScope       = [string]$nmeApiScopeBox.Text
        OAuthTokenUrl  = [string]$nmeOAuthTokenUrlBox.Text
        ClientSecret   = [string]$nmeClientSecretBox.Password
        SubscriptionId = [string]$nmeSubscriptionIdBox.Text
        ResourceGroup  = [string]$nmeResourceGroupCombo.SelectedItem
        StorageAccount = [string]$nmeStorageAccountCombo.SelectedItem
        Container      = [string]$nmeContainerCombo.SelectedItem
    }

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param(
                [string]$ModulePath,
                [PSCustomObject]$NerdioAuthContext
            )

            $result = [PSCustomObject]@{
                Success = $false
                Rows    = @()
                Error   = ''
            }

            try {
                Import-Module -Name $ModulePath -Force -ErrorAction Stop | Out-Null

                $setNmeCredentialsCommand = Get-Command -Name 'NerdioShellApps\Set-NmeCredentials' -ErrorAction SilentlyContinue
                $connectNmeCommand = Get-Command -Name 'NerdioShellApps\Connect-Nme' -ErrorAction SilentlyContinue

                if ($null -ne $setNmeCredentialsCommand -and $null -ne $connectNmeCommand) {
                    foreach ($required in @(
                            @{ Name = 'Tenant ID'; Value = [string]$NerdioAuthContext.TenantId },
                            @{ Name = 'NME Host'; Value = [string]$NerdioAuthContext.NmeHost },
                            @{ Name = 'Client ID'; Value = [string]$NerdioAuthContext.ClientId },
                            @{ Name = 'API Scope'; Value = [string]$NerdioAuthContext.ApiScope },
                            @{ Name = 'Client Secret'; Value = [string]$NerdioAuthContext.ClientSecret }
                        )) {
                        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                            throw "Nerdio API $($required.Name) is required to list Shell Apps."
                        }
                    }

                    & $setNmeCredentialsCommand -ClientId ([string]$NerdioAuthContext.ClientId) -ClientSecret ([string]$NerdioAuthContext.ClientSecret) -TenantId ([string]$NerdioAuthContext.TenantId) -ApiScope ([string]$NerdioAuthContext.ApiScope) -OAuthToken ([string]$NerdioAuthContext.OAuthTokenUrl) -SubscriptionId ([string]$NerdioAuthContext.SubscriptionId) -ResourceGroupName ([string]$NerdioAuthContext.ResourceGroup) -StorageAccountName ([string]$NerdioAuthContext.StorageAccount) -ContainerName ([string]$NerdioAuthContext.Container) -NmeHost ([string]$NerdioAuthContext.NmeHost)
                    $null = & $connectNmeCommand -PassThru
                }

                $getShellAppsCommand = Get-Command -Name 'NerdioShellApps\Get-ShellApps' -ErrorAction SilentlyContinue
                if ($null -eq $getShellAppsCommand) {
                    $getShellAppsCommand = Get-Command -Name 'NerdioShellApps\Get-ShellApp' -ErrorAction SilentlyContinue
                }

                if ($null -eq $getShellAppsCommand) {
                    throw 'Required command Get-ShellApps was not found in NerdioShellApps module.'
                }

                $getShellAppVersionCommand = Get-Command -Name 'NerdioShellApps\Get-ShellAppVersion' -ErrorAction SilentlyContinue
                $rawApps = @(& $getShellAppsCommand)
                $rows = [System.Collections.Generic.List[object]]::new()

                foreach ($app in $rawApps) {
                    if ($null -eq $app) { continue }

                    $publisher = @(
                        $app.PSObject.Properties['Publisher'],
                        $app.PSObject.Properties['publisher'],
                        $app.PSObject.Properties['Vendor'],
                        $app.PSObject.Properties['vendor'],
                        $app.PSObject.Properties['Manufacturer'],
                        $app.PSObject.Properties['manufacturer']
                    ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                    $name = @(
                        $app.PSObject.Properties['Name'],
                        $app.PSObject.Properties['name'],
                        $app.PSObject.Properties['displayName'],
                        $app.PSObject.Properties['cachedName']
                    ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                    $id = @(
                        $app.PSObject.Properties['Id'],
                        $app.PSObject.Properties['id'],
                        $app.PSObject.Properties['publicId'],
                        $app.PSObject.Properties['externalId']
                    ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                    $latestVersion = @(
                        $app.PSObject.Properties['LatestVersion'],
                        $app.PSObject.Properties['latestVersion'],
                        $app.PSObject.Properties['Version'],
                        $app.PSObject.Properties['version']
                    ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                    $versionCount = @(
                        $app.PSObject.Properties['VersionCount'],
                        $app.PSObject.Properties['versionCount'],
                        $app.PSObject.Properties['VersionsCount'],
                        $app.PSObject.Properties['versionsCount']
                    ) | Where-Object { $null -ne $_ -and $null -ne $_.Value -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                    $resolvedVersionCount = '-'
                    if ($null -ne $versionCount) {
                        $resolvedVersionCount = [string]$versionCount.Value
                    }

                    $resolvedLatestVersion = if ($null -ne $latestVersion) { [string]$latestVersion.Value } else { '-' }

                    if (($resolvedVersionCount -eq '-' -or $resolvedLatestVersion -eq '-') -and $null -ne $getShellAppVersionCommand -and $null -ne $id) {
                        try {
                            $versions = @(& $getShellAppVersionCommand -Id ([string]$id.Value))

                            if ($resolvedVersionCount -eq '-') {
                                $resolvedVersionCount = [string]$versions.Count
                            }

                            if ($resolvedLatestVersion -eq '-' -and $versions.Count -gt 0) {
                                $versionStrings = @(
                                    foreach ($v in $versions) {
                                        $versionProperty = @(
                                            $v.PSObject.Properties['Version'],
                                            $v.PSObject.Properties['version'],
                                            $v.PSObject.Properties['DisplayVersion'],
                                            $v.PSObject.Properties['displayVersion'],
                                            $v.PSObject.Properties['Name'],
                                            $v.PSObject.Properties['name']
                                        ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | Select-Object -First 1

                                        if ($null -ne $versionProperty) {
                                            ([string]$versionProperty.Value).Trim()
                                        }
                                    }
                                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                                if ($versionStrings.Count -gt 0) {
                                    $parsedVersions = @(
                                        foreach ($versionText in $versionStrings) {
                                            $sanitizedVersion = (($versionText -replace '^[^0-9]*', '') -replace '[^0-9\.]', '')
                                            if (-not [string]::IsNullOrWhiteSpace($sanitizedVersion)) {
                                                try {
                                                    [PSCustomObject]@{
                                                        Raw    = $versionText
                                                        Parsed = [version]$sanitizedVersion
                                                    }
                                                }
                                                catch {
                                                }
                                            }
                                        }
                                    )

                                    if ($parsedVersions.Count -gt 0) {
                                        $resolvedLatestVersion = ($parsedVersions | Sort-Object -Property Parsed -Descending | Select-Object -First 1).Raw
                                    }
                                    else {
                                        $resolvedLatestVersion = $versionStrings[0]
                                    }
                                }
                            }
                        }
                        catch {
                        }
                    }

                    $rows.Add([PSCustomObject]@{
                            Publisher     = if ($null -ne $publisher) { [string]$publisher.Value } else { '-' }
                            Name          = if ($null -ne $name) { [string]$name.Value } else { '-' }
                            VersionCount  = $resolvedVersionCount
                            LatestVersion = $resolvedLatestVersion
                            Id            = if ($null -ne $id) { [string]$id.Value } else { '-' }
                        })
                }

                $result.Success = $true
                $result.Rows = @($rows | Sort-Object -Property Publisher, Name, Id)
            }
            catch {
                $result.Error = $_.Exception.Message
            }

            return $result
        }).AddArgument($modulePath).AddArgument($nerdioAuthContext)

    $syncHash.PendingNerdioShellAppsPS = $ps
    $syncHash.PendingNerdioShellAppsRunspace = $rs
    $syncHash.PendingNerdioShellAppsAsync = $ps.BeginInvoke()

    $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $syncHash.PendingNerdioShellAppsTimer = $pollTimer

    $pollTimer.add_Tick({
            if ($null -eq $syncHash.PendingNerdioShellAppsAsync -or -not $syncHash.PendingNerdioShellAppsAsync.IsCompleted) {
                return
            }

            if ($null -ne $syncHash.PendingNerdioShellAppsTimer) {
                $syncHash.PendingNerdioShellAppsTimer.Stop()
                $syncHash.PendingNerdioShellAppsTimer = $null
            }

            $result = $null
            try {
                $output = $syncHash.PendingNerdioShellAppsPS.EndInvoke($syncHash.PendingNerdioShellAppsAsync)
                if ($null -ne $output -and $output.Count -gt 0) {
                    $result = $output[$output.Count - 1]
                }
            }
            catch {
                $result = [PSCustomObject]@{ Success = $false; Rows = @(); Error = $_.Exception.Message }
            }
            finally {
                try { $syncHash.PendingNerdioShellAppsPS.Dispose() } catch {}
                try { $syncHash.PendingNerdioShellAppsRunspace.Dispose() } catch {}
                $syncHash.PendingNerdioShellAppsPS = $null
                $syncHash.PendingNerdioShellAppsRunspace = $null
                $syncHash.PendingNerdioShellAppsAsync = $null
            }

            try {
                if ($null -eq $result -or -not $result.Success) {
                    $syncHash.NerdioShellAppRows = @()
                    $nerdioShellAppsListView.ItemsSource = @()
                    $nerdioShellAppsCountLabel.Text = '0 apps'
                    $errorMessage = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Error)) { 'Unknown error occurred while listing Shell Apps.' } else { [string]$result.Error }
                    Write-UILog -SyncHash $syncHash -Message "Nerdio: failed to list Shell Apps: $errorMessage" -Level Error
                }
                else {
                    $rows = @($result.Rows)
                    $syncHash.NerdioShellAppRows = $rows
                    $nerdioShellAppsListView.ItemsSource = $rows
                    $nerdioShellAppsCountLabel.Text = "$($rows.Count) apps"
                    Write-UILog -SyncHash $syncHash -Message "Nerdio: loaded $($rows.Count) Shell App(s) from Nerdio Manager." -Level Info
                }

                & $refreshNerdioComparison
            }
            finally {
                & $setNerdioShellAppsLoadingState -IsLoading $false
            }
        })

    $pollTimer.Start()
}

$refreshIntuneModuleStatus = {
    param(
        [bool]$IsLoaded,
        [string]$Message
    )

    if ($null -eq $intuneSettingsModuleStatusLabel) { return }

    if ($IsLoaded) {
        $intuneSettingsModuleStatusLabel.Foreground = [System.Windows.Media.Brushes]::LightGreen
        if ($null -ne $intuneSettingsModuleStatusDot) {
            $intuneSettingsModuleStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
        }
    }
    else {
        $intuneSettingsModuleStatusLabel.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        if ($null -ne $intuneSettingsModuleStatusDot) {
            $intuneSettingsModuleStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
        }
    }

    $intuneSettingsModuleStatusLabel.Text = $Message
}

$loadIntuneWin32AppModule = {
    param([switch]$Force)

    try {
        if ($Force) {
            Remove-Module -Name IntuneWin32App -ErrorAction SilentlyContinue
        }

        Import-Module -Name IntuneWin32App -Force:$Force -ErrorAction Stop | Out-Null
        $ver = (Get-Module -Name IntuneWin32App).Version
        & $refreshIntuneModuleStatus -IsLoaded $true -Message "IntuneWin32App v$ver loaded."
        Write-UILog -SyncHash $syncHash -Message "IntuneWin32App module v$ver loaded successfully." -Level Info
        return $true
    }
    catch {
        & $refreshIntuneModuleStatus -IsLoaded $false -Message "Failed to load module: $($_.Exception.Message)"
        Write-UILog -SyncHash $syncHash -Message "Failed to load IntuneWin32App module: $($_.Exception.Message)" -Level Error
        return $false
    }
}

$startImportSignIn = {
    if ($syncHash.AzureAuthState.IsAuthInProgress) {
        return
    }

    # Set in-progress immediately on the UI thread so the Gold dot renders
    # before the browser auth dialog opens.
    $syncHash.AzureAuthState.IsAuthInProgress = $true
    $syncHash.AzureAuthState.ErrorMessage = ''
    & $refreshImportAuthUi

    $tenant = [string]$importTenantIdBox.Text
    Write-UILog -SyncHash $syncHash -Message 'Starting Entra sign-in for Intune workflows...' -Level Info

    $r = Invoke-AzureSignIn -TenantId $tenant

    if ($null -ne $r -and $r.Succeeded) {
        $syncHash.AzureAuthState.IsAuthenticated  = $true
        $syncHash.AzureAuthState.AccountId        = [string]$r.AccountId
        $syncHash.AzureAuthState.TenantId         = [string]$r.TenantId
        $syncHash.AzureAuthState.SubscriptionName = [string]$r.SubscriptionName
        $syncHash.AzureAuthState.ErrorMessage     = ''

        if ($r.PSObject.Properties.Name -contains 'IntuneConnected') {
            $syncHash.AzureAuthState.IntuneConnected = [bool]$r.IntuneConnected
        }
        else {
            $syncHash.AzureAuthState.IntuneConnected = $false
        }

        if ($r.PSObject.Properties.Name -contains 'IntuneConnectError') {
            $syncHash.AzureAuthState.IntuneConnectError = [string]$r.IntuneConnectError
        }
        else {
            $syncHash.AzureAuthState.IntuneConnectError = ''
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$r.TenantId)) {
            $syncHash.ImportTenantIdBox.Text = [string]$r.TenantId
        }

        $syncHash.Config.AzureAuthSettings.TenantId        = [string]$syncHash.ImportTenantIdBox.Text
        $syncHash.Config.AzureAuthSettings.LastAccountId   = [string]$r.AccountId
        $syncHash.Config.AzureAuthSettings.LastTenantId    = [string]$r.TenantId
        $syncHash.Config.AzureAuthSettings.LastSignedInUtc = (Get-Date).ToUniversalTime().ToString('o')
        Set-UIConfig -Config $syncHash.Config

        Write-UILog -SyncHash $syncHash -Message "Signed in as $($r.AccountId) to tenant $($r.TenantId)." -Level Info
        if ($r.PSObject.Properties.Name -contains 'AuthMethod' -and -not [string]::IsNullOrWhiteSpace([string]$r.AuthMethod)) {
            Write-UILog -SyncHash $syncHash -Message "Sign-in method: $([string]$r.AuthMethod)." -Level Info
        }
        if ($syncHash.AzureAuthState.IntuneConnected) {
            Write-UILog -SyncHash $syncHash -Message 'Intune Graph token acquisition succeeded.' -Level Info
        }
        elseif (-not [string]::IsNullOrWhiteSpace($syncHash.AzureAuthState.IntuneConnectError)) {
            Write-UILog -SyncHash $syncHash -Message "Intune Graph token acquisition failed: $($syncHash.AzureAuthState.IntuneConnectError)" -Level Warning
        }
    }
    else {
        $syncHash.AzureAuthState.IsAuthenticated    = $false
        $syncHash.AzureAuthState.AccountId          = ''
        $syncHash.AzureAuthState.TenantId           = ''
        $syncHash.AzureAuthState.SubscriptionName   = ''
        $syncHash.AzureAuthState.IntuneConnected    = $false
        $syncHash.AzureAuthState.IntuneConnectError = ''
        $syncHash.AzureAuthState.ErrorMessage       = if ($null -eq $r) { 'Unknown sign-in error.' } else { [string]$r.ErrorMessage }
        Write-UILog -SyncHash $syncHash -Message "Sign-in failed: $($syncHash.AzureAuthState.ErrorMessage)" -Level Error
    }

    $syncHash.AzureAuthState.IsAuthInProgress = $false
    & $syncHash.RefreshImportAuthUi
}

$startImportSignOut = {
    Invoke-AzureSignOut

    $syncHash.AzureAuthState.IsAuthenticated = $false
    $syncHash.AzureAuthState.IsAuthInProgress = $false
    $syncHash.AzureAuthState.AccountId = ''
    $syncHash.AzureAuthState.TenantId = ''
    $syncHash.AzureAuthState.SubscriptionName = ''
    $syncHash.AzureAuthState.ErrorMessage = ''
    $syncHash.AzureAuthState.IntuneConnected = $false
    $syncHash.AzureAuthState.IntuneConnectError = ''
    & $refreshImportAuthUi

    Write-UILog -SyncHash $syncHash -Message 'Signed out of Entra session for Import workflows.' -Level Info
}

$startNerdioApiSignIn = {
    if ($syncHash.NerdioApiAuthState.IsAuthInProgress) {
        return
    }

    if (-not (& $loadNerdioShellAppsModule)) {
        $syncHash.NerdioApiAuthState.ErrorMessage = 'NerdioShellApps module is not loaded.'
        & $refreshNerdioApiAuthUi
        return
    }

    $setNmeCredentialsCommand = & $getNerdioShellAppsCommand -Name 'Set-NmeCredentials'
    $connectNmeCommand = & $getNerdioShellAppsCommand -Name 'Connect-Nme'

    if ($null -eq $setNmeCredentialsCommand -or $null -eq $connectNmeCommand) {
        $syncHash.NerdioApiAuthState.ErrorMessage = 'Required NerdioShellApps commands were not found.'
        & $refreshNerdioApiAuthUi
        Write-UILog -SyncHash $syncHash -Message 'Nerdio API sign-in failed: required NerdioShellApps commands were not found.' -Level Error
        return
    }

    $tenant = [string]$nerdioTenantIdBox.Text
    $nmeHost = [string]$nmeHostBox.Text
    $clientId = [string]$nmeClientIdBox.Text
    $apiScope = [string]$nmeApiScopeBox.Text
    $oAuthTokenUrl = [string]$nmeOAuthTokenUrlBox.Text
    $clientSecret = [string]$nmeClientSecretBox.Password
    $subscriptionId = [string]$nmeSubscriptionIdBox.Text
    $resourceGroup  = [string]$nmeResourceGroupCombo.SelectedItem
    $storageAccount = [string]$nmeStorageAccountCombo.SelectedItem
    $container      = [string]$nmeContainerCombo.SelectedItem

    foreach ($required in @(
            @{ Name = 'Tenant ID'; Value = $tenant },
            @{ Name = 'NME Host'; Value = $nmeHost },
            @{ Name = 'Client ID'; Value = $clientId },
            @{ Name = 'API Scope'; Value = $apiScope },
            @{ Name = 'Client Secret'; Value = $clientSecret }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            $syncHash.NerdioApiAuthState.ErrorMessage = "$($required.Name) is required."
            & $refreshNerdioApiAuthUi
            Write-UILog -SyncHash $syncHash -Message "Nerdio API sign-in failed: $($required.Name) is required." -Level Warning
            return
        }
    }

    $syncHash.NerdioApiAuthState.IsAuthInProgress = $true
    $syncHash.NerdioApiAuthState.ErrorMessage = ''
    & $refreshNerdioApiAuthUi

    try {
        & $setNmeCredentialsCommand -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenant -ApiScope $apiScope -OAuthToken $oAuthTokenUrl -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -StorageAccountName $storageAccount -ContainerName $container -NmeHost $nmeHost
        $null = & $connectNmeCommand -PassThru

        $syncHash.NerdioApiAuthState.IsAuthenticated = $true
        $syncHash.NerdioApiAuthState.AccountId = $clientId
        $syncHash.NerdioApiAuthState.TenantId = $tenant.Trim()
        $syncHash.NerdioApiAuthState.ContextName = $nmeHost.Trim()
        $syncHash.NerdioApiAuthState.ErrorMessage = ''

        $syncHash.Config.AzureAuthSettings.NerdioTenantId = [string]$tenant.Trim()
        Set-UIConfig -Config $syncHash.Config

        Write-UILog -SyncHash $syncHash -Message "Nerdio Manager API sign-in succeeded for host $nmeHost." -Level Info
    }
    catch {
        $syncHash.NerdioApiAuthState.IsAuthenticated = $false
        $syncHash.NerdioApiAuthState.AccountId = ''
        $syncHash.NerdioApiAuthState.TenantId = ''
        $syncHash.NerdioApiAuthState.ContextName = ''
        $syncHash.NerdioApiAuthState.ErrorMessage = $_.Exception.Message
        Write-UILog -SyncHash $syncHash -Message "Nerdio API sign-in failed: $($syncHash.NerdioApiAuthState.ErrorMessage)" -Level Error
    }
    finally {
        $syncHash.NerdioApiAuthState.IsAuthInProgress = $false
        & $refreshNerdioApiAuthUi
    }
}

$startNerdioApiSignOut = {
    try {
        $clearSecretsCommand = & $getNerdioShellAppsCommand -Name 'Remove-NerdioManagerSecretsFromMemory'
        if ($null -ne $clearSecretsCommand) {
            & $clearSecretsCommand | Out-Null
        }
    }
    catch {}

    $syncHash.NerdioApiAuthState.IsAuthenticated = $false
    $syncHash.NerdioApiAuthState.IsAuthInProgress = $false
    $syncHash.NerdioApiAuthState.AccountId = ''
    $syncHash.NerdioApiAuthState.TenantId = ''
    $syncHash.NerdioApiAuthState.ContextName = ''
    $syncHash.NerdioApiAuthState.ErrorMessage = ''
    & $refreshNerdioApiAuthUi

    Write-UILog -SyncHash $syncHash -Message 'Signed out of Nerdio Manager API session.' -Level Info
}

$startNerdioAzureSignIn = {
    if ($syncHash.NerdioAzureAuthState.IsAuthInProgress) {
        return
    }

    $subscriptionId = [string]$nmeSubscriptionIdBox.Text
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        Write-UILog -SyncHash $syncHash -Message 'Azure sign-in requires a Subscription ID.' -Level Warning
        return
    }

    $syncHash.NerdioAzureAuthState.IsAuthInProgress = $true
    $syncHash.NerdioAzureAuthState.ErrorMessage = ''
    & $refreshNerdioAzureAuthUi

    $tenant = [string]$nerdioTenantIdBox.Text
    Write-UILog -SyncHash $syncHash -Message "Starting Azure sign-in for Nerdio workflows (subscription: $subscriptionId)..." -Level Info

    $r = Invoke-NerdioAzureSignIn -SubscriptionId $subscriptionId -TenantId $tenant
    if ($null -ne $r -and $r.Succeeded) {
        $syncHash.NerdioAzureAuthState.IsAuthenticated   = $true
        $syncHash.NerdioAzureAuthState.AccountId         = [string]$r.AccountId
        $syncHash.NerdioAzureAuthState.TenantId          = [string]$r.TenantId
        $syncHash.NerdioAzureAuthState.SubscriptionName  = [string]$r.SubscriptionName
        $syncHash.NerdioAzureAuthState.ErrorMessage      = ''

        if (-not [string]::IsNullOrWhiteSpace([string]$r.TenantId)) {
            $nerdioTenantIdBox.Text = [string]$r.TenantId
        }

        $syncHash.Config.AzureAuthSettings.NerdioTenantId         = [string]$nerdioTenantIdBox.Text
        $syncHash.Config.AzureAuthSettings.NerdioLastAccountId    = [string]$r.AccountId
        $syncHash.Config.AzureAuthSettings.NerdioLastTenantId     = [string]$r.TenantId
        $syncHash.Config.AzureAuthSettings.NerdioLastSignedInUtc  = (Get-Date).ToUniversalTime().ToString('o')
        Set-UIConfig -Config $syncHash.Config

        Write-UILog -SyncHash $syncHash -Message "Nerdio Azure sign-in succeeded as $($r.AccountId) (subscription: $($r.SubscriptionName), tenant: $($r.TenantId))." -Level Info

        # Populate the Resource Group dropdown from the target subscription
        Write-UILog -SyncHash $syncHash -Message 'Loading resource groups...' -Level Info
        $nmeResourceGroupCombo.Items.Clear()
        $nmeStorageAccountCombo.Items.Clear()
        $nmeContainerCombo.Items.Clear()
        $nmeStorageAccountCombo.IsEnabled = $false
        $nmeContainerCombo.IsEnabled      = $false

        $rgs = Get-NerdioAzureResourceGroups
        foreach ($rg in $rgs) { [void]$nmeResourceGroupCombo.Items.Add($rg) }
        $nmeResourceGroupCombo.IsEnabled = ($nmeResourceGroupCombo.Items.Count -gt 0)
        Write-UILog -SyncHash $syncHash -Message "$($nmeResourceGroupCombo.Items.Count) resource group(s) loaded." -Level Info
    }
    else {
        $syncHash.NerdioAzureAuthState.IsAuthenticated   = $false
        $syncHash.NerdioAzureAuthState.AccountId         = ''
        $syncHash.NerdioAzureAuthState.TenantId          = ''
        $syncHash.NerdioAzureAuthState.SubscriptionName  = ''
        $syncHash.NerdioAzureAuthState.ErrorMessage      = if ($null -eq $r) { 'Unknown sign-in error.' } else { [string]$r.ErrorMessage }
        Write-UILog -SyncHash $syncHash -Message "Nerdio Azure sign-in failed: $($syncHash.NerdioAzureAuthState.ErrorMessage)" -Level Error
    }

    $syncHash.NerdioAzureAuthState.IsAuthInProgress = $false
    & $refreshNerdioAzureAuthUi
}

$startNerdioAzureSignOut = {
    Invoke-NerdioAzureSignOut

    $syncHash.NerdioAzureAuthState.IsAuthenticated  = $false
    $syncHash.NerdioAzureAuthState.IsAuthInProgress = $false
    $syncHash.NerdioAzureAuthState.AccountId        = ''
    $syncHash.NerdioAzureAuthState.TenantId         = ''
    $syncHash.NerdioAzureAuthState.SubscriptionName = ''
    $syncHash.NerdioAzureAuthState.ErrorMessage     = ''

    # Clear and disable the storage dropdowns
    $nmeResourceGroupCombo.Items.Clear()
    $nmeStorageAccountCombo.Items.Clear()
    $nmeContainerCombo.Items.Clear()
    $nmeResourceGroupCombo.IsEnabled  = $false
    $nmeStorageAccountCombo.IsEnabled = $false
    $nmeContainerCombo.IsEnabled      = $false

    & $refreshNerdioAzureAuthUi
    Write-UILog -SyncHash $syncHash -Message 'Signed out of Azure session for Nerdio workflows.' -Level Info
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

# Apply initial log state from config
$isLogVisible = [bool]$syncHash.Config.LogVisible
if ($isLogVisible) {
    $initialLogHeight = [Math]::Max(80, [int]$syncHash.Config.LogHeight)
    $logRowDef.Height = [System.Windows.GridLength]::new(40 + $initialLogHeight)
    $logToggleButton.IsChecked = $true
    $logToggleButton.Content = 'Hide progress log'
}
else {
    $logRowDef.Height = [System.Windows.GridLength]::new(40)
    $logToggleButton.IsChecked = $false
    $logToggleButton.Content = 'Show progress log'
}

# Event: Window.Loaded
$window.add_Loaded({
        # Apply saved theme (before any logging so colours are correct)
        if ($syncHash.Config.Theme -eq 'Dark') {
            $themeComboBox.SelectedIndex = 1
            Set-DarkTheme -Window $syncHash.Window
        }
        else {
            $themeComboBox.SelectedIndex = 0
            Set-LightTheme -Window $syncHash.Window
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
        $importTenantIdBox.Text = [string]$syncHash.Config.AzureAuthSettings.TenantId
        $nerdioTenantIdBox.Text = [string]$syncHash.Config.AzureAuthSettings.NerdioTenantId
        $nerdioModulePathSettingsBox.Text = [string]$syncHash.Config.NerdioSettings.ModulePath
        $nmeHostBox.Text           = [string]$syncHash.Config.NerdioSettings.NmeHost
        $nmeClientIdBox.Text       = [string]$syncHash.Config.NerdioSettings.NmeClientId
        $nmeApiScopeBox.Text       = [string]$syncHash.Config.NerdioSettings.NmeApiScope
        $nmeOAuthTokenUrlBox.Text  = [string]$syncHash.Config.NerdioSettings.NmeOAuthTokenUrl
        $nmeSubscriptionIdBox.Text = [string]$syncHash.Config.NerdioSettings.NmeSubscriptionId
        $nerdioDefinitionsPathBox.Text = [string]$syncHash.Config.NerdioSettings.DefinitionsPath
        $intuneDefinitionsPathBox.Text    = [string]$syncHash.Config.IntuneSettings.DefinitionsPath
        $intunePackageOutputPathBox.Text  = [string]$syncHash.Config.IntuneSettings.PackageOutputPath
        [void](& $loadNerdioShellAppsModule)
        [void](& $loadIntuneWin32AppModule)
        & $refreshImportAuthUi
        & $refreshNerdioApiAuthUi
        & $refreshNerdioAzureAuthUi
        & $setImportProvider -Provider $syncHash.Config.ImportSettings.CurrentProvider

        $syncHash.SettingsLastSavedJson = $syncHash.Config | ConvertTo-Json -Depth 5
        if ($null -eq $syncHash.SettingsAutoSaveTimer) {
            $settingsTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $settingsTimer.Interval = [TimeSpan]::FromSeconds(5)
            $settingsTimer.add_Tick({
                    try {
                        & $persistUiSettingsSnapshot
                    }
                    catch {
                        # Best effort only - autosave must never destabilize the UI.
                    }
                })
            $syncHash.SettingsAutoSaveTimer = $settingsTimer
        }
        if (-not $syncHash.SettingsAutoSaveTimer.IsEnabled) {
            $syncHash.SettingsAutoSaveTimer.Start()
        }

        switch ([string]$syncHash.Config.StartupView) {
            'Download' {
                $navDownload.IsChecked = $true
            }
            'Library' {
                $navLibrary.IsChecked = $true
            }
            'Import' {
                $navImport.IsChecked = $true
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
            & $persistUiSettingsSnapshot -ForceWrite

            if ($null -ne $syncHash.SettingsAutoSaveTimer -and $syncHash.SettingsAutoSaveTimer.IsEnabled) {
                $syncHash.SettingsAutoSaveTimer.Stop()
            }

            if ($null -ne $syncHash.BackgroundOperationsTimer -and $syncHash.BackgroundOperationsTimer.IsEnabled) {
                $syncHash.BackgroundOperationsTimer.Stop()
            }

            foreach ($op in @($syncHash.ActiveBackgroundOperations)) {
                try { $op.PowerShell.Stop() } catch {}
                try { $op.PowerShell.Dispose() } catch {}
                try { $op.Runspace.Dispose() } catch {}
            }
            $syncHash.ActiveBackgroundOperations.Clear()

            if ($null -ne $syncHash.PendingIntuneImportTimer -and $syncHash.PendingIntuneImportTimer.IsEnabled) {
                $syncHash.PendingIntuneImportTimer.Stop()
            }
            if ($null -ne $syncHash.PendingIntuneImportPS) {
                try { $syncHash.PendingIntuneImportPS.Stop() } catch {}
                try { $syncHash.PendingIntuneImportPS.Dispose() } catch {}
            }
            if ($null -ne $syncHash.PendingIntuneImportRunspace) {
                try { $syncHash.PendingIntuneImportRunspace.Dispose() } catch {}
            }

            $syncHash.PendingIntuneImportTimer = $null
            $syncHash.PendingIntuneImportPS = $null
            $syncHash.PendingIntuneImportRunspace = $null
            $syncHash.PendingIntuneImportAsync = $null
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
    param($source, $e)

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
            elseif ($navImport.IsChecked) {
                & $setImportProvider -Provider $syncHash.Config.ImportSettings.CurrentProvider
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
    NavImport   = $importPanel
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

foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navImport, $navSettings)) {
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

$navImport.add_Checked({
        & $refreshImportAuthUi
    & $refreshNerdioApiAuthUi
    & $refreshNerdioAzureAuthUi
        & $setImportProvider -Provider $syncHash.Config.ImportSettings.CurrentProvider
    })

$importProviderTabControl.add_SelectionChanged({
        param($s, $e)
        if ($s -ne $importProviderTabControl) { return }
        # Index 2 is the shared Authentication tab — not a provider workflow, nothing to switch
        if ($importProviderTabControl.SelectedIndex -eq 2) { return }
    $provider = if ($importProviderTabControl.SelectedIndex -eq 0) { 'Intune' } else { 'Nerdio' }
        & $setImportProvider -Provider $provider -Persist
    $label = if ($importProviderTabControl.SelectedIndex -eq 0) { 'Microsoft Intune Win32 Apps' } else { 'Nerdio Manager Shell Apps' }
        Write-UILog -SyncHash $syncHash -Message "Import workflow switched to $label placeholder." -Level Info
    })

$importSignInButton.add_Click({
        & $applyImportTenantToConfig
        & $startImportSignIn
    })

$importSignOutButton.add_Click({
        & $startImportSignOut
    })

$importTenantIdBox.add_LostFocus({
        & $applyImportTenantToConfig
    })

$nerdioApiSignInButton.add_Click({
        & $applyNerdioTenantToConfig
        & $startNerdioApiSignIn
    })

$nerdioApiSignOutButton.add_Click({
        & $startNerdioApiSignOut
    })

$nerdioAzureSignInButton.add_Click({
        & $applyNerdioTenantToConfig
        & $startNerdioAzureSignIn
    })

$nerdioAzureSignOutButton.add_Click({
        & $startNerdioAzureSignOut
    })

# Enable/disable the Azure sign-in button based on whether Subscription ID is provided
$nmeSubscriptionIdBox.add_TextChanged({
        $nerdioAzureSignInButton.IsEnabled = -not [string]::IsNullOrWhiteSpace($nmeSubscriptionIdBox.Text)
        $syncHash.Config.NerdioSettings.NmeSubscriptionId = [string]$nmeSubscriptionIdBox.Text
        Set-UIConfig -Config $syncHash.Config
    })

$nmeHostBox.add_TextChanged({
        $syncHash.Config.NerdioSettings.NmeHost = [string]$nmeHostBox.Text
        Set-UIConfig -Config $syncHash.Config
    })

$nmeClientIdBox.add_TextChanged({
        $syncHash.Config.NerdioSettings.NmeClientId = [string]$nmeClientIdBox.Text
        Set-UIConfig -Config $syncHash.Config
    })

$nmeApiScopeBox.add_TextChanged({
        $syncHash.Config.NerdioSettings.NmeApiScope = [string]$nmeApiScopeBox.Text
        Set-UIConfig -Config $syncHash.Config
    })

$nmeOAuthTokenUrlBox.add_TextChanged({
        $syncHash.Config.NerdioSettings.NmeOAuthTokenUrl = [string]$nmeOAuthTokenUrlBox.Text
        Set-UIConfig -Config $syncHash.Config
    })

# When a resource group is selected, populate the Storage Account dropdown
$nmeResourceGroupCombo.add_SelectionChanged({
        $rg = [string]$nmeResourceGroupCombo.SelectedItem
        $nmeStorageAccountCombo.Items.Clear()
        $nmeContainerCombo.Items.Clear()
        $nmeStorageAccountCombo.IsEnabled = $false
        $nmeContainerCombo.IsEnabled      = $false
        if ([string]::IsNullOrWhiteSpace($rg)) { return }
        Write-UILog -SyncHash $syncHash -Message "Loading storage accounts for '$rg'..." -Level Info
        $accounts = Get-NerdioAzureStorageAccounts -ResourceGroupName $rg
        foreach ($sa in $accounts) { [void]$nmeStorageAccountCombo.Items.Add($sa) }
        $nmeStorageAccountCombo.IsEnabled = ($nmeStorageAccountCombo.Items.Count -gt 0)
        Write-UILog -SyncHash $syncHash -Message "$($nmeStorageAccountCombo.Items.Count) storage account(s) loaded." -Level Info
    })

# When a storage account is selected, populate the Container dropdown
$nmeStorageAccountCombo.add_SelectionChanged({
        $rg = [string]$nmeResourceGroupCombo.SelectedItem
        $sa = [string]$nmeStorageAccountCombo.SelectedItem
        $nmeContainerCombo.Items.Clear()
        $nmeContainerCombo.IsEnabled = $false
        if ([string]::IsNullOrWhiteSpace($rg) -or [string]::IsNullOrWhiteSpace($sa)) { return }
        Write-UILog -SyncHash $syncHash -Message "Loading containers for '$sa'..." -Level Info
        $containers = Get-NerdioAzureStorageContainers -ResourceGroupName $rg -StorageAccountName $sa
        foreach ($c in $containers) { [void]$nmeContainerCombo.Items.Add($c) }
        $nmeContainerCombo.IsEnabled = ($nmeContainerCombo.Items.Count -gt 0)
        Write-UILog -SyncHash $syncHash -Message "$($nmeContainerCombo.Items.Count) container(s) loaded." -Level Info
    })

$nerdioTenantIdBox.add_LostFocus({
    & $applyNerdioTenantToConfig
    })

$nerdioDefinitionsPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $nerdioDefinitionsPathBox.Text
        $nerdioDefinitionsPathBox.Text = $normalised
        & $applyNerdioDefinitionsPathToConfig
    })

$nerdioBrowseDefinitionsButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Shell App definitions folder'
        if (-not [string]::IsNullOrWhiteSpace($nerdioDefinitionsPathBox.Text)) {
            $dlg.SelectedPath = $nerdioDefinitionsPathBox.Text
        }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $nerdioDefinitionsPathBox.Text = $dlg.SelectedPath
            & $applyNerdioDefinitionsPathToConfig
        }
    })

$nerdioLoadDefinitionsButton.add_Click({
    & $loadNerdioDefinitions
    })

$nerdioListShellAppsButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'List Shell Apps' -Provider 'Nerdio')) { return }
    & $loadNerdioShellApps
    })

$nerdioCompareUpdatesButton.add_Click({
        try {
            if (-not (& $loadNerdioShellAppsModule)) {
                Write-UILog -SyncHash $syncHash -Message 'Nerdio: cannot compare updates because NerdioShellApps module is not loaded.' -Level Warning
                return
            }

            & $refreshNerdioComparison
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Nerdio: compare updates failed: $($_.Exception.Message)" -Level Error
        }
    })

$nerdioAddVersionButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'Add Shell App version' -Provider 'Nerdio')) { return }
        Write-UILog -SyncHash $syncHash -Message 'Nerdio: add version to existing Shell App is not implemented yet.' -Level Info
    })

$nerdioImportNewButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'Import new Shell App' -Provider 'Nerdio')) { return }
        Write-UILog -SyncHash $syncHash -Message 'Nerdio: import as new Shell App is not implemented yet.' -Level Info
    })

$intuneRefreshCatalogButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'List Intune Win32 apps')) { return }
    & $startIntuneImportOperation -ActionName 'List Intune Win32 apps' -LoadingMessage 'Listing Win32 apps from Microsoft Intune...' -CompletionMessage 'Intune: listing Win32 apps from Microsoft Intune is not implemented yet.'
    })

$intuneBrowseDefinitionsButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Intune package definitions folder'
        if (-not [string]::IsNullOrWhiteSpace($intuneDefinitionsPathBox.Text)) {
            $dlg.SelectedPath = $intuneDefinitionsPathBox.Text
        }

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
            $intuneDefinitionsPathBox.Text = $normalised
            & $applyIntunePathsToConfig
        }
    })

$intuneLoadDefinitionsButton.add_Click({
        Write-UILog -SyncHash $syncHash -Message 'Intune: load package definitions is not implemented yet.' -Level Info
    })

$intuneBrowsePackageOutputButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Intune package output folder'
        if (-not [string]::IsNullOrWhiteSpace($intunePackageOutputPathBox.Text)) {
            $dlg.SelectedPath = $intunePackageOutputPathBox.Text
        }

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
            $intunePackageOutputPathBox.Text = $normalised
            & $applyIntunePathsToConfig
        }
    })

$intuneDefinitionsPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $intuneDefinitionsPathBox.Text
        $intuneDefinitionsPathBox.Text = $normalised
        & $applyIntunePathsToConfig
    })

$intunePackageOutputPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $intunePackageOutputPathBox.Text
        $intunePackageOutputPathBox.Text = $normalised
        & $applyIntunePathsToConfig
    })

$intunePackageButton.add_Click({
        Write-UILog -SyncHash $syncHash -Message 'Intune: package selected apps is not implemented yet.' -Level Info
    })

$intunePreviewImportButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'Intune preview import')) { return }
    & $startIntuneImportOperation -ActionName 'Preview import' -LoadingMessage 'Preparing Intune import preview...' -CompletionMessage 'Intune: preview import is not implemented yet.'
    })

$intuneApplyImportButton.add_Click({
        if (-not (& $requireImportAuth -ActionName 'Intune apply import')) { return }
    & $startIntuneImportOperation -ActionName 'Apply import' -LoadingMessage 'Applying Intune import...' -CompletionMessage 'Intune: apply import is not implemented yet.'
    })

$intuneReloadModuleSettingsButton.add_Click({
        [void](& $loadIntuneWin32AppModule -Force)
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

$themeComboBox.add_SelectionChanged({
        $item = $themeComboBox.SelectedItem
        if ($null -eq $item) { return }

        if ([string]$item.Content -eq 'Dark') {
            Set-DarkTheme -Window $syncHash.Window
            $syncHash.Config.Theme = 'Dark'
        }
        else {
            Set-LightTheme -Window $syncHash.Window
            $syncHash.Config.Theme = 'Light'
        }

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
        $nerdioModulePathSettingsBox.Text = [string]$syncHash.Config.NerdioSettings.ModulePath

        $nerdioLoaded = $null -ne (Get-Module -Name NerdioShellApps)
        if ($nerdioLoaded) {
            & $refreshNerdioModuleStatus -IsLoaded $true -Message 'NerdioShellApps module is loaded.'
        }
        else {
            & $refreshNerdioModuleStatus -IsLoaded $false -Message 'NerdioShellApps module not loaded. Select a module path and click Reload.'
        }

        $intuneLoaded = $null -ne (Get-Module -Name IntuneWin32App)
        if ($intuneLoaded) {
            & $refreshIntuneModuleStatus -IsLoaded $true -Message 'IntuneWin32App module is loaded.'
        }
        else {
            & $refreshIntuneModuleStatus -IsLoaded $false -Message 'IntuneWin32App module not loaded. Install from the PowerShell Gallery and click Reload.'
        }

        $desiredVerbosity = [string]$syncHash.Config.LogVerbosity
        $logVerbosityComboBox.SelectedIndex = if ($desiredVerbosity -eq 'Verbose') { 1 } else { 0 }

        $themeComboBox.SelectedIndex = if ([string]$syncHash.Config.Theme -eq 'Dark') { 1 } else { 0 }

        switch ([string]$syncHash.Config.StartupView) {
            'Download' { $startupViewComboBox.SelectedIndex = 1 }
            'Library' { $startupViewComboBox.SelectedIndex = 2 }
            'Import' { $startupViewComboBox.SelectedIndex = 3 }
            'Settings' { $startupViewComboBox.SelectedIndex = 4 }
            default { $startupViewComboBox.SelectedIndex = 0 }
        }
    })

# Log panel collapse / expand
# When expanded, the log area height (above the 32px status bar) is restored
# from config; when collapsed, row 3 drops to exactly the status bar height.
$logToggleButton.add_Click({
        if ($logToggleButton.IsChecked) {
            $restoreHeight = [Math]::Max(80, $syncHash.Config.LogHeight)
            $logRowDef.Height = [System.Windows.GridLength]::new(40 + $restoreHeight)
            $logToggleButton.Content = 'Hide progress log'
            $syncHash.Config.LogVisible = $true
        }
        else {
            # Save current displayed log height before collapsing
            $currentHeight = [int]$logRowDef.Height.Value - 40
            if ($currentHeight -gt 0) { $syncHash.Config.LogHeight = $currentHeight }
            $logRowDef.Height = [System.Windows.GridLength]::new(40)
            $logToggleButton.Content = 'Show progress log'
            $syncHash.Config.LogVisible = $false
        }

        Set-UIConfig -Config $syncHash.Config
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

$nerdioBrowseModulePathSettingsButton.add_Click({
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Title = 'Select NerdioShellApps module file'
        $dlg.Filter = 'PowerShell module files (*.psm1)|*.psm1|All files (*.*)|*.*'
        $dlg.CheckFileExists = $true
        $dlg.Multiselect = $false
        if (-not [string]::IsNullOrWhiteSpace($nerdioModulePathSettingsBox.Text)) {
            try {
                $currentDir = Split-Path -Path $nerdioModulePathSettingsBox.Text -Parent
                if (Test-Path -LiteralPath $currentDir -PathType Container) {
                    $dlg.InitialDirectory = $currentDir
                }
            }
            catch {}
        }

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $nerdioModulePathSettingsBox.Text = $dlg.FileName
            [void](& $loadNerdioShellAppsModule -Force)
        }
    })

$nerdioReloadModuleSettingsButton.add_Click({
        [void](& $loadNerdioShellAppsModule -Force)
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

$nerdioModulePathSettingsBox.add_LostFocus({
        [void](& $loadNerdioShellAppsModule)
    })

# Show window (blocking)
[void]$window.ShowDialog()
