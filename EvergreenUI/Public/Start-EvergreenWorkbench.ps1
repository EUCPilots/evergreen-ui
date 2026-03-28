#Requires -Version 5.1
<#
.EXTERNALHELP EvergreenUI-help.xml
#>
function Start-EvergreenWorkbench {
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

    $moduleManifestPath = (Resolve-Path -Path (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'EvergreenUI.psd1')).Path
    $moduleMetadata = [ordered]@{
        Name              = 'EvergreenUI'
        Version           = ''
        Prerelease        = ''
        Author            = ''
        CompanyName       = ''
        Copyright         = ''
        License           = ''
        ProjectUri        = ''
        Description       = ''
        PowerShellVersion = ''
        RootModule        = ''
        Guid              = ''
        ManifestPath      = $moduleManifestPath
    }

    try {
        $moduleManifest = Test-ModuleManifest -Path $moduleManifestPath -ErrorAction Stop

        $moduleMetadata.Name = [string]$moduleManifest.Name
        $moduleMetadata.Version = [string]$moduleManifest.Version
        $moduleMetadata.Author = [string]$moduleManifest.Author
        $moduleMetadata.CompanyName = [string]$moduleManifest.CompanyName
        $moduleMetadata.Copyright = [string]$moduleManifest.Copyright
        $moduleMetadata.Description = [string]$moduleManifest.Description
        $moduleMetadata.PowerShellVersion = [string]$moduleManifest.PowerShellVersion
        $moduleMetadata.RootModule = [string]$moduleManifest.RootModule
        $moduleMetadata.Guid = [string]$moduleManifest.Guid

        $psData = $null
        if ($moduleManifest.PrivateData -is [hashtable]) {
            if ($moduleManifest.PrivateData.ContainsKey('PSData')) {
                $psData = $moduleManifest.PrivateData.PSData
            }
        }
        elseif ($null -ne $moduleManifest.PrivateData) {
            $psData = $moduleManifest.PrivateData.PSData
        }

        if ($null -ne $psData) {
            if ($null -ne $psData.Prerelease) {
                $moduleMetadata.Prerelease = [string]$psData.Prerelease
            }
            if ($null -ne $psData.LicenseUri) {
                $moduleMetadata.License = [string]$psData.LicenseUri
            }
            if ($null -ne $psData.ProjectUri) {
                $moduleMetadata.ProjectUri = [string]$psData.ProjectUri
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$moduleMetadata.License)) {
            $moduleMetadata.License = [string]$moduleMetadata.Copyright
        }
    }
    catch {
        # About panel metadata is best-effort only.
    }

    # Shared state
    $syncHash = [hashtable]::Synchronized(@{
            Window                                          = $null
            LogTextBox                                      = $null
            LogScrollViewer                                 = $null
            IsRunning                                       = $false
            AppList                                         = $null
            CurrentAppResults                               = $null
            FilterState                                     = @{}
            VersionsListView                                = $null
            ResultsCountLabel                               = $null
            DownloadQueueListView                           = $null
            QueueCountLabel                                 = $null
            DownloadAllButton                               = $null
            DownloadProgressBar                             = $null
            LibraryContentsListView                         = $null
            LibraryDetailsListView                          = $null
            LibraryStatusLabel                              = $null
            LibraryUpdateButton                             = $null
            UpdateOutputTextBox                             = $null
            UpdateOutputScrollViewer                        = $null
            RunUpdateEvergreenButton                        = $null
            UpdateStatusLabel                               = $null
            LibraryData                                     = @()
            ActiveBackgroundOperations                      = [System.Collections.Generic.List[object]]::new()
            BackgroundOperationsTimer                       = $null
            SettingsAutoSaveTimer                           = $null
            SettingsLastSavedJson                           = ''
            DownloadQueue                                   = [System.Collections.Generic.List[PSCustomObject]]::new()
            EvergreenVersion                                = ''
            Config                                          = $config
            PendingLoadTimer                                = $null
            PendingLoadPS                                   = $null
            PendingLoadRunspace                             = $null
            PendingLoadAsync                                = $null
            PendingLoadAppName                              = $null
            PendingNerdioAzureAuthTimer                     = $null
            PendingNerdioAzureAuthPS                        = $null
            PendingNerdioAzureAuthRunspace                  = $null
            PendingNerdioAzureAuthAsync                     = $null
            PendingIntuneImportTimer                        = $null
            PendingIntuneImportPS                           = $null
            PendingIntuneImportRunspace                     = $null
            PendingIntuneImportAsync                        = $null
            IsIntuneImportLoading                           = $false
            IntuneActionButtonStates                        = @{}
            IntuneDefinitionRows                            = @()
            IntuneWin32Rows                                 = @()
            IntuneComparisonRows                            = @()
            IntuneSortProperty                              = ''
            IntuneSortDirection                             = 'Ascending'
            PendingInstallTimer                             = $null
            PendingInstallPS                                = $null
            PendingInstallRunspace                          = $null
            PendingInstallAsync                             = $null
            IsInstallLoading                                = $false
            InstallActionButtonStates                       = @{}
            InstallDefinitionRows                           = @()
            InstallRows                                     = @()
            InstallSortProperty                             = ''
            InstallSortDirection                            = 'Ascending'
            PendingNerdioShellAppsTimer                     = $null
            PendingNerdioShellAppsPS                        = $null
            PendingNerdioShellAppsRunspace                  = $null
            PendingNerdioShellAppsAsync                     = $null
            IsNerdioShellAppsLoading                        = $false
            PendingNerdioAddVersionTimer                    = $null
            PendingNerdioAddVersionPS                       = $null
            PendingNerdioAddVersionRunspace                 = $null
            PendingNerdioAddVersionAsync                    = $null
            PendingNerdioPostImportVerifyAppId              = ''
            PendingNerdioPostImportVerifyAppName            = ''
            PendingNerdioPostImportExpectedEvergreenVersion = ''
            NerdioDefinitionRows                            = @()
            NerdioShellAppRows                              = @()
            NerdioComparisonRows                            = @()
            NerdioSelectedComparisonRow                     = $null
            ImportCurrentProvider                           = 'Nerdio'
            AzureAuthState                                  = [PSCustomObject]@{
                IsAuthenticated    = $false
                IsAuthInProgress   = $false
                AccountId          = ''
                TenantId           = ''
                SubscriptionName   = ''
                ErrorMessage       = ''
                IntuneConnected    = $false
                IntuneConnectError = ''
            }
            NerdioApiAuthState                              = [PSCustomObject]@{
                IsAuthenticated  = $false
                IsAuthInProgress = $false
                AccountId        = ''
                TenantId         = ''
                ContextName      = ''
                ErrorMessage     = ''
            }
            NerdioAzureAuthState                            = [PSCustomObject]@{
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
    $stream = [System.IO.File]::OpenRead((Resolve-Path -Path $xamlPath).Path)
    $window = [System.Windows.Markup.XamlReader]::Load($stream)
    $stream.Dispose()

    # Set window/taskbar icon from bundled resource when available.
    $iconPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Resources\evergreenbulb.png'
    if (Test-Path -Path $iconPath) {
        try {
            $iconUri = [System.Uri]::new((Resolve-Path -Path $iconPath).Path)
            $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new($iconUri)
        }
        catch {
            # Ignore icon load failures and continue startup.
        }
    }

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
    $navInstall = $window.FindName('NavInstall')
    $navSettings = $window.FindName('NavSettings')
    $navUpdate = $window.FindName('NavUpdate')
    $navAbout = $window.FindName('NavAbout')

    $appsPanel = $window.FindName('AppsPanel')
    $downloadPanel = $window.FindName('DownloadPanel')
    $libraryPanel = $window.FindName('LibraryPanel')
    $importPanel = $window.FindName('ImportPanel')
    $installPanel = $window.FindName('InstallPanel')
    $settingsPanel = $window.FindName('SettingsPanel')
    $updatePanel = $window.FindName('UpdatePanel')
    $aboutPanel = $window.FindName('AboutPanel')

    $refreshAppsButton = $window.FindName('RefreshAppsButton')
    $appSearchBox = $window.FindName('AppSearchBox')
    $appsComboBox = $window.FindName('AppsComboBox')
    $loadAppVersionsButton = $window.FindName('LoadAppVersionsButton')
    $filterWrapPanel = $window.FindName('FilterWrapPanel')
    $clearFiltersButton = $window.FindName('ClearFiltersButton')
    $exportCsvButton = $window.FindName('ExportCsvButton')
    $addToQueueButton = $window.FindName('AddToQueueButton')

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
    $syncHash.RunUpdateEvergreenButton = $window.FindName('RunUpdateEvergreenButton')
    $syncHash.UpdateOutputTextBox = $window.FindName('UpdateOutputTextBox')
    $syncHash.UpdateOutputScrollViewer = $window.FindName('UpdateOutputScrollViewer')
    $syncHash.UpdateStatusLabel = $window.FindName('UpdateStatusLabel')
    $clearUpdateOutputButton = $window.FindName('ClearUpdateOutputButton')

    $syncHash.DownloadQueueListView = $window.FindName('DownloadQueueListView')
    $syncHash.QueueCountLabel = $window.FindName('QueueCountLabel')
    $syncHash.DownloadAllButton = $window.FindName('DownloadAllButton')
    $syncHash.DownloadProgressBar = $window.FindName('DownloadProgressBar')

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
    $showImportTabCheckBox = $window.FindName('ShowImportTabCheckBox')
    $showInstallTabCheckBox = $window.FindName('ShowInstallTabCheckBox')
    $startupViewComboBox = $window.FindName('StartupViewComboBox')
    $browseOutputButton = $window.FindName('BrowseOutputButton')
    $openEvergreenAppsFolderButton = $window.FindName('OpenEvergreenAppsFolderButton')
    $clearCacheButton = $window.FindName('ClearCacheButton')
    $openCacheFolderButton = $window.FindName('OpenCacheFolderButton')
    $nerdioModulePathSettingsBox = $window.FindName('NerdioModulePathSettingsBox')
    $nerdioBrowseModulePathSettingsButton = $window.FindName('NerdioBrowseModulePathSettingsButton')
    $nerdioReloadModuleSettingsButton = $window.FindName('NerdioReloadModuleSettingsButton')
    $nerdioModuleStatusLabel = $window.FindName('NerdioModuleStatusLabel')
    $aboutNameValue = $window.FindName('AboutNameValue')
    $aboutVersionValue = $window.FindName('AboutVersionValue')
    $aboutPrereleaseValue = $window.FindName('AboutPrereleaseValue')
    $aboutAuthorValue = $window.FindName('AboutAuthorValue')
    $aboutCompanyValue = $window.FindName('AboutCompanyValue')
    $aboutCopyrightValue = $window.FindName('AboutCopyrightValue')
    $aboutLicenseValue = $window.FindName('AboutLicenseValue')
    $aboutProjectUriValue = $window.FindName('AboutProjectUriValue')
    $aboutDescriptionValue = $window.FindName('AboutDescriptionValue')

    $importProviderTabControl = $window.FindName('ImportProviderTabControl')
    $importTenantIdBox = $window.FindName('ImportTenantIdBox')
    $importAuthStatusDot = $window.FindName('ImportAuthStatusDot')
    $importAuthStatusLabel = $window.FindName('ImportAuthStatusLabel')
    $importSignInButton = $window.FindName('ImportSignInButton')
    $importSignOutButton = $window.FindName('ImportSignOutButton')
    $intuneRefreshCatalogButton = $window.FindName('IntuneRefreshCatalogButton')
    # Microsoft Intune controls
    $intunePackageOutputPathBox = $window.FindName('IntunePackageOutputPathBox')
    $intuneBrowsePackageOutputButton = $window.FindName('IntuneBrowsePackageOutputButton')
    $intuneDefinitionsPathBox = $window.FindName('IntuneDefinitionsPathBox')
    $intuneBrowseDefinitionsButton = $window.FindName('IntuneBrowseDefinitionsButton')
    $intuneLoadDefinitionsButton = $window.FindName('IntuneLoadDefinitionsButton')
    $intuneDefinitionsCountLabel = $window.FindName('IntuneDefinitionsCountLabel')
    $intuneWin32AppsCountLabel = $window.FindName('IntuneWin32AppsCountLabel')
    $intuneConnectionStatusDot = $window.FindName('IntuneConnectionStatusDot')
    $intuneConnectionStatusLabel = $window.FindName('IntuneConnectionStatusLabel')
    $intuneWin32AppsListView = $window.FindName('IntuneWin32AppsListView')
    $intuneActionStatusLabel = $window.FindName('IntuneActionStatusLabel')
    $intuneImportLoadingPanel = $window.FindName('IntuneImportLoadingPanel')
    $intuneImportLoadingLabel = $window.FindName('IntuneImportLoadingLabel')
    $intuneImportProgressBar = $window.FindName('IntuneImportProgressBar')
    # Local Install controls
    $installDefinitionsPathBox = $window.FindName('InstallDefinitionsPathBox')
    $installBrowseDefinitionsButton = $window.FindName('InstallBrowseDefinitionsButton')
    $installLoadDefinitionsButton = $window.FindName('InstallLoadDefinitionsButton')
    $installResolveLatestButton = $window.FindName('InstallResolveLatestButton')
    $installDefinitionsCountLabel = $window.FindName('InstallDefinitionsCountLabel')
    $installActionableCountLabel = $window.FindName('InstallActionableCountLabel')
    $installElevationStatusDot = $window.FindName('InstallElevationStatusDot')
    $installElevationStatusLabel = $window.FindName('InstallElevationStatusLabel')
    $installLoadingPanel = $window.FindName('InstallLoadingPanel')
    $installLoadingLabel = $window.FindName('InstallLoadingLabel')
    $installProgressBar = $window.FindName('InstallProgressBar')
    $installPackagesListView = $window.FindName('InstallPackagesListView')
    $installApplyButton = $window.FindName('InstallApplyButton')
    $installActionStatusLabel = $window.FindName('InstallActionStatusLabel')
    # Intune Settings controls
    $intuneReloadModuleSettingsButton = $window.FindName('IntuneReloadModuleSettingsButton')
    $intuneSettingsModuleStatusDot = $window.FindName('IntuneSettingsModuleStatusDot')
    $intuneSettingsModuleStatusLabel = $window.FindName('IntuneSettingsModuleStatusLabel')
    # Nerdio Shell Apps controls
    $nmeHostBox = $window.FindName('NmeHostBox')
    $nmeClientIdBox = $window.FindName('NmeClientIdBox')
    $nmeApiScopeBox = $window.FindName('NmeApiScopeBox')
    $nmeOAuthTokenUrlBox = $window.FindName('NmeOAuthTokenUrlBox')
    $nmeClientSecretBox = $window.FindName('NmeClientSecretBox')
    $nmeSubscriptionIdBox = $window.FindName('NmeSubscriptionIdBox')
    $nmeResourceGroupCombo = $window.FindName('NmeResourceGroupCombo')
    $nmeStorageAccountCombo = $window.FindName('NmeStorageAccountCombo')
    $nmeContainerCombo = $window.FindName('NmeContainerCombo')
    $nerdioTenantIdBox = $window.FindName('NerdioTenantIdBox')
    $nerdioApiAuthStatusDot = $window.FindName('NerdioApiAuthStatusDot')
    $nerdioApiAuthStatusLabel = $window.FindName('NerdioApiAuthStatusLabel')
    $nerdioApiSignInButton = $window.FindName('NerdioApiSignInButton')
    $nerdioApiSignOutButton = $window.FindName('NerdioApiSignOutButton')
    $nerdioDefinitionsPathBox = $window.FindName('NerdioDefinitionsPathBox')
    $nerdioBrowseDefinitionsButton = $window.FindName('NerdioBrowseDefinitionsButton')
    $nerdioLoadDefinitionsButton = $window.FindName('NerdioLoadDefinitionsButton')
    $nerdioListShellAppsButton = $window.FindName('NerdioListShellAppsButton')
    $nerdioDefinitionsListView = $window.FindName('NerdioDefinitionsListView')
    $nerdioDefinitionsCountLabel = $window.FindName('NerdioDefinitionsCountLabel')
    $nerdioShellAppsCountLabel = $window.FindName('NerdioShellAppsCountLabel')
    $nerdioShellAppsLoadingPanel = $window.FindName('NerdioShellAppsLoadingPanel')
    $nerdioShellAppsLoadingLabel = $window.FindName('NerdioShellAppsLoadingLabel')
    $nerdioShellAppsProgressBar = $window.FindName('NerdioShellAppsProgressBar')
    $nerdioAddVersionButton = $window.FindName('NerdioAddVersionButton')
    $nerdioImportNewButton = $window.FindName('NerdioImportNewButton')
    $nerdioActionStatusLabel = $window.FindName('NerdioActionStatusLabel')
    $nerdioImportAuthStatusDot = $window.FindName('NerdioImportAuthStatusDot')
    $nerdioImportAuthStatusLabel = $window.FindName('NerdioImportAuthStatusLabel')
    $nerdioAzureAuthStatusDot = $window.FindName('NerdioAzureAuthStatusDot')
    $nerdioAzureAuthStatusLabel = $window.FindName('NerdioAzureAuthStatusLabel')
    $nerdioAzureSignInButton = $window.FindName('NerdioAzureSignInButton')
    $nerdioAzureSignOutButton = $window.FindName('NerdioAzureSignOutButton')
    $intuneApplyImportButton = $window.FindName('IntuneApplyImportButton')
    # Log row is RowDefinitions[3]; track its height for collapse/restore
    $logRowDef = $rootGrid.RowDefinitions[3]

    # Store refs needed by background-runspace callbacks
    $syncHash.ImportTenantIdBox = $importTenantIdBox

    # Intune controls exposed to runspace Dispatcher callbacks
    $syncHash.IntuneImportLoadingLabel = $intuneImportLoadingLabel
    $syncHash.IntuneImportProgressBar = $intuneImportProgressBar
    $syncHash.IntuneImportLoadingPanel = $intuneImportLoadingPanel
    $syncHash.IntuneActionStatusLabel = $intuneActionStatusLabel
    $syncHash.IntuneWin32AppsListView = $intuneWin32AppsListView
    $syncHash.InstallLoadingLabel = $installLoadingLabel
    $syncHash.InstallActionStatusLabel = $installActionStatusLabel

    $aboutNameValue.Text = [string]$moduleMetadata.Name
    $aboutVersionValue.Text = [string]$moduleMetadata.Version
    $aboutPrereleaseValue.Text = if ([string]::IsNullOrWhiteSpace([string]$moduleMetadata.Prerelease)) { 'n/a' } else { [string]$moduleMetadata.Prerelease }
    $aboutAuthorValue.Text = [string]$moduleMetadata.Author
    $aboutCompanyValue.Text = [string]$moduleMetadata.CompanyName
    $aboutCopyrightValue.Text = [string]$moduleMetadata.Copyright
    $aboutLicenseValue.Text = [string]$moduleMetadata.License
    $aboutProjectUriValue.Text = [string]$moduleMetadata.ProjectUri
    $aboutDescriptionValue.Text = [string]$moduleMetadata.Description

    $setNerdioShellAppsLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsNerdioShellAppsLoading = $IsLoading

        if ($null -ne $nerdioListShellAppsButton) {
            $nerdioListShellAppsButton.IsEnabled = -not $IsLoading
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

        & $updateNerdioRowActionButtons
    }

    $updateNerdioRowActionButtons = {
        $selectedRow = if ($null -eq $nerdioDefinitionsListView) { $null } else { $nerdioDefinitionsListView.SelectedItem }
        $syncHash.NerdioSelectedComparisonRow = $selectedRow

        $canImportNew = $false
        $canAddVersion = $false

        if ($null -ne $selectedRow) {
            $hasDefinition = ([string]$selectedRow.HasDefinition -eq 'Yes')
            $isMatched = ([string]$selectedRow.IsMatched -eq 'Yes')
            $isNewApp = ([string]$selectedRow.IsNewApp -eq 'Yes')
            $updateNeeded = ([string]$selectedRow.UpdateNeeded -eq 'Yes')

            $canImportNew = $hasDefinition -and $isNewApp
            $canAddVersion = $isMatched -and $updateNeeded
        }

        if ($null -ne $nerdioImportNewButton) {
            $nerdioImportNewButton.IsEnabled = (-not $syncHash.IsNerdioShellAppsLoading) -and $canImportNew
        }

        if ($null -ne $nerdioAddVersionButton) {
            $nerdioAddVersionButton.IsEnabled = (-not $syncHash.IsNerdioShellAppsLoading) -and $canAddVersion
        }
    }

    $updateIntuneRowActionButtons = {
        $selectedItems = if ($null -eq $intuneWin32AppsListView) { @() } else { @($intuneWin32AppsListView.SelectedItems) }

        $hasActionable = $selectedItems | Where-Object {
            [string]$_.ImportAction -eq 'Import new app' -or [string]$_.ImportAction -eq 'Import new version and supersede'
        }

        $canImport = ($null -ne $hasActionable) -and (-not $syncHash.IsIntuneImportLoading)

        if ($null -ne $intuneApplyImportButton) {
            $intuneApplyImportButton.IsEnabled = $canImport
        }
    }

    $updateInstallRowActionButtons = {
        $selectedItems = if ($null -eq $installPackagesListView) { @() } else { @($installPackagesListView.SelectedItems) }

        $hasActionable = @($selectedItems | Where-Object {
                [string]$_.InstallAction -eq 'Install' -or [string]$_.InstallAction -eq 'Update'
            }).Count -gt 0

        if ($null -ne $installApplyButton) {
            $installApplyButton.IsEnabled = (-not $syncHash.IsInstallLoading) -and $hasActionable
        }

        if ($null -ne $installResolveLatestButton) {
            $installResolveLatestButton.IsEnabled = (-not $syncHash.IsInstallLoading) -and (@($syncHash.InstallDefinitionRows).Count -gt 0)
        }
    }

    $setInstallElevationState = {
        $isElevated = & $testInstallElevationState
        if ($null -ne $installElevationStatusDot) {
            $installElevationStatusDot.Fill = if ($isElevated) {
                [System.Windows.Media.Brushes]::LightGreen
            }
            else {
                [System.Windows.Media.Brushes]::Gold
            }
        }

        if ($null -ne $installElevationStatusLabel) {
            $installElevationStatusLabel.Text = if ($isElevated) {
                'Workbench is running as administrator'
            }
            else {
                'Not elevated - installers may prompt for UAC'
            }
        }
    }

    $applyIntuneListSort = {
        if ($null -eq $intuneWin32AppsListView -or $null -eq $intuneWin32AppsListView.ItemsSource) {
            return
        }

        $sortProperty = [string]$syncHash.IntuneSortProperty
        if ([string]::IsNullOrWhiteSpace($sortProperty)) {
            return
        }

        $sortDirectionText = [string]$syncHash.IntuneSortDirection
        $sortDirection = if ($sortDirectionText -ieq 'Descending') {
            [System.ComponentModel.ListSortDirection]::Descending
        }
        else {
            [System.ComponentModel.ListSortDirection]::Ascending
        }

        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($intuneWin32AppsListView.ItemsSource)
        if ($null -eq $view) {
            return
        }

        $view.SortDescriptions.Clear()
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new($sortProperty, $sortDirection))
        $view.Refresh()
    }

    $applyInstallListSort = {
        if ($null -eq $installPackagesListView -or $null -eq $installPackagesListView.ItemsSource) {
            return
        }

        $sortProperty = [string]$syncHash.InstallSortProperty
        if ([string]::IsNullOrWhiteSpace($sortProperty)) {
            return
        }

        $sortDirectionText = [string]$syncHash.InstallSortDirection
        $sortDirection = if ($sortDirectionText -ieq 'Descending') {
            [System.ComponentModel.ListSortDirection]::Descending
        }
        else {
            [System.ComponentModel.ListSortDirection]::Ascending
        }

        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($installPackagesListView.ItemsSource)
        if ($null -eq $view) {
            return
        }

        $view.SortDescriptions.Clear()
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new($sortProperty, $sortDirection))
        $view.Refresh()
    }

    $setIntuneImportLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsIntuneImportLoading = $IsLoading

        foreach ($button in @($intuneRefreshCatalogButton, $intuneApplyImportButton)) {
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

        & $updateIntuneRowActionButtons
    }

    $setInstallLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsInstallLoading = $IsLoading

        foreach ($button in @($installLoadDefinitionsButton, $installResolveLatestButton, $installApplyButton)) {
            if ($null -eq $button) {
                continue
            }

            if ($IsLoading) {
                $syncHash.InstallActionButtonStates[$button.Name] = [bool]$button.IsEnabled
                $button.IsEnabled = $false
            }
            else {
                if ($syncHash.InstallActionButtonStates.ContainsKey($button.Name)) {
                    $button.IsEnabled = [bool]$syncHash.InstallActionButtonStates[$button.Name]
                }
            }
        }

        if (-not $IsLoading) {
            $syncHash.InstallActionButtonStates.Clear()
        }

        if ($null -ne $installLoadingPanel) {
            $installLoadingPanel.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
        }

        if ($null -ne $installLoadingLabel) {
            if ($IsLoading -and -not [string]::IsNullOrWhiteSpace($Message)) {
                $installLoadingLabel.Text = $Message
            }
            elseif (-not $IsLoading) {
                $installLoadingLabel.Text = 'Working...'
            }
        }

        if ($null -ne $installProgressBar) {
            $installProgressBar.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
        }

        if ($null -ne $installActionStatusLabel) {
            if ($IsLoading) {
                $installActionStatusLabel.Text = if ([string]::IsNullOrWhiteSpace($Message)) { 'Working...' } else { $Message }
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$installActionStatusLabel.Text)) {
                $installActionStatusLabel.Text = ''
            }
        }

        & $updateInstallRowActionButtons
    }

    $refreshInstallRows = {
        $definitionRows = @($syncHash.InstallDefinitionRows)
        $rows = [System.Collections.Generic.List[object]]::new()
        $actionableCount = 0

        foreach ($definitionRow in $definitionRows) {
            $definitionObject = $definitionRow.DefinitionObject
            $installedVersion = '-'
            $detectionStatus = 'Not evaluated'
            $installStatus = 'Needs latest check'
            $installAction = '-'
            $latestVersion = [string]$definitionRow.LatestVersion

            if ([string]$definitionRow.DefinitionValid -ne 'Yes' -or $null -eq $definitionObject) {
                $installStatus = [string]$definitionRow.Status
                $installAction = 'Fix definition'
            }
            else {
                $detectionResult = Test-LocalPackageDetection -DefinitionObject $definitionObject
                if (-not $detectionResult.Succeeded) {
                    $detectionStatus = 'Detection failed'
                    $installStatus = if ([string]::IsNullOrWhiteSpace([string]$detectionResult.Error)) { 'Detection failed' } else { [string]$detectionResult.Error }
                    $installAction = 'Needs review'
                }
                else {
                    if (-not [string]::IsNullOrWhiteSpace([string]$detectionResult.DetectedVersion)) {
                        $installedVersion = [string]$detectionResult.DetectedVersion
                    }
                    elseif ($detectionResult.Installed) {
                        $installedVersion = 'Installed'
                    }

                    $detectionStatus = [string]$detectionResult.Status

                    if (-not $detectionResult.Installed) {
                        $installStatus = 'Not installed'
                        $installAction = 'Install'
                    }
                    elseif ([string]::IsNullOrWhiteSpace($latestVersion)) {
                        $installStatus = 'Installed (latest not checked)'
                        $installAction = '-'
                    }
                    else {
                        $installedComparable = & $parseComparableVersion -VersionText $installedVersion
                        $latestComparable = & $parseComparableVersion -VersionText $latestVersion
                        if ($installedComparable.Success -and $latestComparable.Success -and $installedComparable.Parsed -lt $latestComparable.Parsed) {
                            $installStatus = 'Installed (update needed)'
                            $installAction = 'Update'
                        }
                        elseif ($installedComparable.Success -and $latestComparable.Success) {
                            $installStatus = 'Installed (up to date)'
                            $installAction = '-'
                        }
                        else {
                            $installStatus = 'Installed (compare unavailable)'
                            $installAction = '-'
                        }
                    }
                }
            }

            if ($installAction -eq 'Install' -or $installAction -eq 'Update') {
                $actionableCount++
            }

            $rows.Add([PSCustomObject]@{
                    Name              = [string]$definitionRow.Name
                    Publisher         = [string]$definitionRow.Publisher
                    DefinitionVersion = [string]$definitionRow.Version
                    InstalledVersion  = $installedVersion
                    LatestVersion     = if ([string]::IsNullOrWhiteSpace($latestVersion)) { '-' } else { $latestVersion }
                    DetectionStatus   = $detectionStatus
                    InstallStatus     = $installStatus
                    InstallAction     = $installAction
                    DefinitionPath    = [string]$definitionRow.DefinitionPath
                    DefinitionObject  = $definitionObject
                })
        }

        $sortedRows = @($rows | Sort-Object -Property @{ Expression = {
                    if ([string]$_.InstallAction -eq 'Install') { 0 }
                    elseif ([string]$_.InstallAction -eq 'Update') { 1 }
                    else { 2 }
                }
            }, Publisher, Name)

        $syncHash.InstallRows = $sortedRows
        if ($null -ne $installPackagesListView) {
            $installPackagesListView.ItemsSource = $sortedRows
            & $applyInstallListSort
        }

        if ($null -ne $installDefinitionsCountLabel) {
            $validCount = @($definitionRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count
            $installDefinitionsCountLabel.Text = "$($definitionRows.Count) loaded ($validCount valid)"
        }

        if ($null -ne $installActionableCountLabel) {
            $installActionableCountLabel.Text = "$actionableCount actionable"
        }

        if ($null -ne $installActionStatusLabel -and -not $syncHash.IsInstallLoading) {
            $upToDate = @($sortedRows | Where-Object { [string]$_.InstallStatus -eq 'Installed (up to date)' }).Count
            $needsInstall = @($sortedRows | Where-Object { [string]$_.InstallAction -eq 'Install' }).Count
            $needsUpdate = @($sortedRows | Where-Object { [string]$_.InstallAction -eq 'Update' }).Count
            $installActionStatusLabel.Text = "Install: $needsInstall | Update: $needsUpdate | Up to date: $upToDate"
        }

        & $updateInstallRowActionButtons
    }

    $loadInstallDefinitions = {
        $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$installDefinitionsPathBox.Text)
        $installDefinitionsPathBox.Text = $definitionsRoot
        & $applyInstallPathsToConfig

        if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
            $syncHash.InstallDefinitionRows = @()
            & $refreshInstallRows
            Write-UILog -SyncHash $syncHash -Message 'Install: provide a package definitions folder path first.' -Level Warning
            return
        }

        $definitionResult = Get-InstallPackageDefinitions -DefinitionsRoot $definitionsRoot
        if (-not $definitionResult.Succeeded) {
            $syncHash.InstallDefinitionRows = @()
            & $refreshInstallRows
            Write-UILog -SyncHash $syncHash -Message "Install: failed to load definitions: $($definitionResult.Error)" -Level Error
            return
        }

        $enrichedRows = @($definitionResult.Rows | ForEach-Object {
                [PSCustomObject]@{
                    DefinitionId         = [string]$_.DefinitionId
                    DefinitionPath       = [string]$_.DefinitionPath
                    Name                 = [string]$_.Name
                    Publisher            = [string]$_.Publisher
                    Version              = [string]$_.Version
                    Status               = [string]$_.Status
                    DefinitionValid      = [string]$_.DefinitionValid
                    PSPackageFactoryGuid = [string]$_.PSPackageFactoryGuid
                    DefinitionObject     = $_.DefinitionObject
                    LatestVersion        = ''
                }
            })

        # Hydrate LatestVersion from cache so values are visible immediately on load.
        $cacheFile = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\install-latest-cache.json'
        $cacheHits = 0
        $cacheExpired = 0
        $cacheFailed = 0
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            try {
                $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) {
                    Write-UILog -SyncHash $syncHash -Message 'Install: cache file is empty.' -Level Warning
                }
                else {
                    $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                    $cacheEntries = if ($parsed -is [System.Array]) { @($parsed) } elseif ($null -ne $parsed) { @($parsed) } else { @() }
                    Write-UILog -SyncHash $syncHash -Message "Install: read $($cacheEntries.Count) entr$(if ($cacheEntries.Count -eq 1) {'y'} else {'ies'}) from cache '$cacheFile'." -Level Info
                    $nowUtc = [DateTime]::UtcNow
                    foreach ($row in $enrichedRows) {
                        $rowPath = ([string]$row.DefinitionPath).Trim()
                        $matchedEntry = $null
                        foreach ($c in $cacheEntries) {
                            if ($null -ne $c -and ([string]$c.DefinitionPath).Trim() -ieq $rowPath) {
                                $matchedEntry = $c
                                break
                            }
                        }
                        if ($null -eq $matchedEntry) { continue }
                        if (-not [bool]$matchedEntry.Succeeded) { $cacheFailed++; continue }

                        # ConvertFrom-Json may auto-parse ISO 8601 strings into [DateTime] objects.
                        # Handle both the raw DateTime case and the string case.
                        [DateTime]$retrievedUtc = [DateTime]::MinValue
                        $timestampOk = $false
                        $rawTimestamp = $matchedEntry.RetrievedUtc
                        if ($rawTimestamp -is [DateTime]) {
                            $retrievedUtc = [DateTime]$rawTimestamp
                            $timestampOk = $true
                        }
                        elseif ([DateTime]::TryParseExact([string]$rawTimestamp, 'o',
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::RoundtripKind,
                                [ref]$retrievedUtc)) {
                            $timestampOk = $true
                        }
                        elseif ([DateTime]::TryParse([string]$rawTimestamp,
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::None,
                                [ref]$retrievedUtc)) {
                            $timestampOk = $true
                        }

                        if ($timestampOk) {
                            if (($nowUtc - $retrievedUtc.ToUniversalTime()) -le [TimeSpan]::FromHours(24)) {
                                $row.LatestVersion = [string]$matchedEntry.Version
                                $cacheHits++
                            }
                            else {
                                $cacheExpired++
                            }
                        }
                    }
                    $cacheSkipParts = @()
                    if ($cacheExpired -gt 0) { $cacheSkipParts += "$cacheExpired expired" }
                    if ($cacheFailed -gt 0) { $cacheSkipParts += "$cacheFailed failed" }
                    if ($cacheSkipParts.Count -gt 0) {
                        Write-UILog -SyncHash $syncHash -Message "Install: cache skipped $($cacheSkipParts -join ', ')." -Level Info
                    }
                }
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Install: cache read error - $($_.Exception.Message)" -Level Warning
            }
        }
        else {
            Write-UILog -SyncHash $syncHash -Message "Install: no cache file found at '$cacheFile'." -Level Info
        }

        $syncHash.InstallDefinitionRows = $enrichedRows
        & $setInstallElevationState
        & $refreshInstallRows

        $cacheMsg = if ($cacheHits -gt 0) { " ($cacheHits with cached latest version)" } else { '' }
        Write-UILog -SyncHash $syncHash -Message "Install: loaded $($enrichedRows.Count) App.json definitions$cacheMsg." -Level Info
    }

    $resolveInstallLatestVersions = {
        if ($syncHash.IsInstallLoading) {
            Write-UILog -SyncHash $syncHash -Message 'Install: another operation is already in progress.' -Level Warning
            return
        }

        $definitionRows = @($syncHash.InstallDefinitionRows | Where-Object {
                [string]$_.DefinitionValid -eq 'Yes' -and -not [string]::IsNullOrWhiteSpace([string]$_.DefinitionPath)
            })

        if ($definitionRows.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Install: no valid definitions loaded.' -Level Warning
            return
        }

        $outputPath = & $normalizeDirectoryPath -PathValue ([string]$outputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            Write-UILog -SyncHash $syncHash -Message 'Install: set a download output path on the Downloads tab first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
            try {
                $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Install: failed to create output path '$outputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        if ($null -ne $syncHash.PendingInstallTimer -and $syncHash.PendingInstallTimer.IsEnabled) {
            $syncHash.PendingInstallTimer.Stop()
            $syncHash.PendingInstallTimer = $null
        }
        foreach ($key in @('PendingInstallPS', 'PendingInstallRunspace', 'PendingInstallAsync')) {
            $syncHash[$key] = $null
        }

        & $setInstallLoadingState -IsLoading $true -Message "Resolving latest versions for $($definitionRows.Count) package(s)..."

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $installCacheRootPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        $helperScripts = @(
            'Write-UILog.ps1'
            'Get-IntunePackageLatestVersion.ps1'
            'Get-InstallPackageLatestVersion.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]$HelperScripts,
                    [object[]]$DefinitionRows,
                    [string]$CacheRootPath
                )

                $result = [PSCustomObject]@{
                    Success = $false
                    Rows    = @()
                    Error   = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Save-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    $cacheFilePath = Join-Path -Path $CacheRootPath -ChildPath 'install-latest-cache.json'
                    if (Test-Path -LiteralPath $cacheFilePath -PathType Leaf) {
                        Write-UILog -SyncHash $syncHash -Message "Install: reading latest version cache from '$cacheFilePath'." -Level Info
                    }
                    else {
                        Write-UILog -SyncHash $syncHash -Message "Install: no cache found at '$cacheFilePath', all versions will be fetched live." -Level Info
                    }

                    $rows = [System.Collections.Generic.List[object]]::new()
                    foreach ($definitionRow in $DefinitionRows) {
                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$definitionRow.DefinitionPath) -DefinitionObject $definitionRow.DefinitionObject -CacheRootPath $CacheRootPath
                        $rows.Add([PSCustomObject]@{
                                DefinitionPath = [string]$definitionRow.DefinitionPath
                                Succeeded      = [bool]$latestResult.Succeeded
                                LatestVersion  = [string]$latestResult.Version
                                LatestError    = [string]$latestResult.Error
                                IsFromCache    = [bool]$latestResult.IsFromCache
                            })
                    }

                    $writeCount = @($rows | Where-Object { -not [bool]$_.IsFromCache }).Count
                    if ($writeCount -gt 0) {
                        Write-UILog -SyncHash $syncHash -Message "Install: wrote $writeCount $(if ($writeCount -eq 1) { 'entry' } else { 'entries' }) to cache at '$cacheFilePath'." -Level Info
                    }

                    $result.Success = $true
                    $result.Rows = @($rows)
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            }).AddArgument(@($helperScripts)).AddArgument(@($definitionRows)).AddArgument($installCacheRootPath)

        $syncHash.PendingInstallPS = $ps
        $syncHash.PendingInstallRunspace = $rs
        $syncHash.PendingInstallAsync = $ps.BeginInvoke()

        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(350)
        $syncHash.PendingInstallTimer = $pollTimer

        $pollTimer.add_Tick({
                if ($null -eq $syncHash.PendingInstallAsync -or -not $syncHash.PendingInstallAsync.IsCompleted) {
                    return
                }

                if ($null -ne $syncHash.PendingInstallTimer) {
                    $syncHash.PendingInstallTimer.Stop()
                    $syncHash.PendingInstallTimer = $null
                }

                $result = $null
                try {
                    $output = $syncHash.PendingInstallPS.EndInvoke($syncHash.PendingInstallAsync)
                    $result = if ($null -ne $output -and $output.Count -gt 0) { $output[$output.Count - 1] } else { $null }
                }
                catch {
                    $result = [PSCustomObject]@{ Success = $false; Rows = @(); Error = $_.Exception.Message }
                }
                finally {
                    try { $syncHash.PendingInstallPS.Dispose() } catch {}
                    try { $syncHash.PendingInstallRunspace.Dispose() } catch {}
                    $syncHash.PendingInstallPS = $null
                    $syncHash.PendingInstallRunspace = $null
                    $syncHash.PendingInstallAsync = $null
                }

                try {
                    if ($null -eq $result -or -not $result.Success) {
                        $err = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Error)) { 'Unknown latest version error.' } else { [string]$result.Error }
                        Write-UILog -SyncHash $syncHash -Message "Install: latest version resolution failed: $err" -Level Error
                    }
                    else {
                        $latestMap = @{}
                        foreach ($row in @($result.Rows)) {
                            $latestMap[[string]$row.DefinitionPath] = $row
                        }

                        foreach ($definitionRow in @($syncHash.InstallDefinitionRows)) {
                            $key = [string]$definitionRow.DefinitionPath
                            if (-not $latestMap.ContainsKey($key)) {
                                continue
                            }

                            $latestRow = $latestMap[$key]
                            if ([bool]$latestRow.Succeeded) {
                                $definitionRow.LatestVersion = [string]$latestRow.LatestVersion
                            }
                            else {
                                $definitionRow.LatestVersion = ''
                                Write-UILog -SyncHash $syncHash -Message "Install: latest lookup failed for '$([string]$definitionRow.Name)': $([string]$latestRow.LatestError)" -Level Warning
                            }
                        }

                        $cacheCount = @($result.Rows | Where-Object { [bool]$_.Succeeded -and [bool]$_.IsFromCache }).Count
                        $freshCount = @($result.Rows | Where-Object { [bool]$_.Succeeded -and -not [bool]$_.IsFromCache }).Count
                        Write-UILog -SyncHash $syncHash -Message "Install: latest version resolution complete ($freshCount live, $cacheCount cache)." -Level Info
                    }

                    # After latest lookup finishes, show highest-priority statuses first.
                    $syncHash.InstallSortProperty = 'InstallStatus'
                    $syncHash.InstallSortDirection = 'Ascending'

                    & $refreshInstallRows
                }
                finally {
                    & $setInstallLoadingState -IsLoading $false
                }
            })

        $pollTimer.Start()
    }

    $startInstallSelectedOperation = {
        if ($syncHash.IsInstallLoading) {
            Write-UILog -SyncHash $syncHash -Message 'Install: another operation is already in progress.' -Level Warning
            return
        }

        $selectedRows = @($installPackagesListView.SelectedItems)
        $actionableRows = @($selectedRows | Where-Object {
                [string]$_.InstallAction -eq 'Install' -or [string]$_.InstallAction -eq 'Update'
            })

        if ($actionableRows.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Install: select one or more rows with Install or Update action.' -Level Warning
            return
        }

        $outputPath = & $normalizeDirectoryPath -PathValue ([string]$outputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            Write-UILog -SyncHash $syncHash -Message 'Install: set a download output path on the Downloads tab first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
            try {
                $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Install: failed to create output path '$outputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        if (-not (& $testInstallElevationState)) {
            Write-UILog -SyncHash $syncHash -Message 'Install: running without elevation. Installer may trigger a UAC prompt.' -Level Warning
        }

        if ($null -ne $syncHash.PendingInstallTimer -and $syncHash.PendingInstallTimer.IsEnabled) {
            $syncHash.PendingInstallTimer.Stop()
            $syncHash.PendingInstallTimer = $null
        }
        foreach ($key in @('PendingInstallPS', 'PendingInstallRunspace', 'PendingInstallAsync')) {
            $syncHash[$key] = $null
        }

        $installActions = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $actionableRows) {
            if ([string]::IsNullOrWhiteSpace([string]$row.DefinitionPath)) {
                continue
            }

            $installActions.Add([PSCustomObject]@{
                    Name           = [string]$row.Name
                    DefinitionPath = [string]$row.DefinitionPath
                })
        }

        if ($installActions.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Install: no valid definition paths were selected.' -Level Warning
            return
        }

        & $setInstallLoadingState -IsLoading $true -Message "Installing $($installActions.Count) package(s)..."

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $installCacheRootPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        $helperScripts = @(
            'Write-UILog.ps1'
            'Get-IntunePackageLatestVersion.ps1'
            'Get-InstallPackageLatestVersion.ps1'
            'Invoke-LocalPackageInstall.ps1'
            'Test-LocalPackageDetection.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]$HelperScripts,
                    [object[]]$InstallActions,
                    [string]$OutputPath,
                    [string]$CacheRootPath
                )

                $result = [PSCustomObject]@{
                    Success   = $false
                    Completed = @()
                    Failed    = @()
                    Error     = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Save-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    $completed = [System.Collections.Generic.List[object]]::new()
                    $failed = [System.Collections.Generic.List[object]]::new()

                    foreach ($action in $InstallActions) {
                        $definitionObject = $null
                        try {
                            $definitionObject = Get-Content -LiteralPath $action.DefinitionPath -Raw -ErrorAction Stop |
                            ConvertFrom-Json -ErrorAction Stop
                        }
                        catch {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = "Failed to load App.json: $($_.Exception.Message)"
                                })
                            continue
                        }

                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$action.DefinitionPath) -DefinitionObject $definitionObject -CacheRootPath $CacheRootPath
                        if (-not [string]::IsNullOrWhiteSpace([string]$latestResult.CacheFile)) {
                            if ([bool]$latestResult.IsFromCache) {
                                Write-UILog -SyncHash $syncHash -Message "Install: cache read for '$([string]$action.Name)' — $([string]$latestResult.Version) from '$([string]$latestResult.CacheFile)'." -Level Info
                            }
                            elseif ([bool]$latestResult.Succeeded) {
                                Write-UILog -SyncHash $syncHash -Message "Install: wrote to cache for '$([string]$action.Name)' — $([string]$latestResult.Version) at '$([string]$latestResult.CacheFile)'." -Level Info
                            }
                        }
                        if (-not $latestResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = "Latest lookup failed: $($latestResult.Error)"
                                })
                            continue
                        }

                        $installResult = Invoke-LocalPackageInstall -DefinitionPath ([string]$action.DefinitionPath) -DefinitionObject $definitionObject -WorkingPath $OutputPath -LatestVersionResult $latestResult -SyncHash $syncHash
                        if (-not $installResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = [string]$installResult.Error
                                })
                            continue
                        }

                        $detectionResult = Test-LocalPackageDetection -DefinitionObject $definitionObject
                        $completed.Add([PSCustomObject]@{
                                Name             = [string]$action.Name
                                DefinitionPath   = [string]$action.DefinitionPath
                                InstalledVersion = [string]$detectionResult.DetectedVersion
                                LatestVersion    = [string]$latestResult.Version
                                ExitCode         = [int]$installResult.ExitCode
                            })
                    }

                    $result.Success = $true
                    $result.Completed = @($completed)
                    $result.Failed = @($failed)
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            }).AddArgument(@($helperScripts)).AddArgument(@($installActions)).AddArgument($outputPath).AddArgument($installCacheRootPath)

        $syncHash.PendingInstallPS = $ps
        $syncHash.PendingInstallRunspace = $rs
        $syncHash.PendingInstallAsync = $ps.BeginInvoke()

        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $syncHash.PendingInstallTimer = $pollTimer

        $pollTimer.add_Tick({
                if ($null -eq $syncHash.PendingInstallAsync -or -not $syncHash.PendingInstallAsync.IsCompleted) {
                    return
                }

                if ($null -ne $syncHash.PendingInstallTimer) {
                    $syncHash.PendingInstallTimer.Stop()
                    $syncHash.PendingInstallTimer = $null
                }

                $result = $null
                try {
                    $output = $syncHash.PendingInstallPS.EndInvoke($syncHash.PendingInstallAsync)
                    $result = if ($null -ne $output -and $output.Count -gt 0) { $output[$output.Count - 1] } else { $null }
                }
                catch {
                    $result = [PSCustomObject]@{ Success = $false; Completed = @(); Failed = @(); Error = $_.Exception.Message }
                }
                finally {
                    try { $syncHash.PendingInstallPS.Dispose() } catch {}
                    try { $syncHash.PendingInstallRunspace.Dispose() } catch {}
                    $syncHash.PendingInstallPS = $null
                    $syncHash.PendingInstallRunspace = $null
                    $syncHash.PendingInstallAsync = $null
                }

                try {
                    if ($null -eq $result -or -not $result.Success) {
                        $err = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Error)) { 'Unknown install error.' } else { [string]$result.Error }
                        Write-UILog -SyncHash $syncHash -Message "Install: operation failed: $err" -Level Error
                    }
                    else {
                        foreach ($item in @($result.Completed)) {
                            Write-UILog -SyncHash $syncHash -Message "Install: completed '$([string]$item.Name)' (exit code $([int]$item.ExitCode))." -Level Info
                            foreach ($definitionRow in @($syncHash.InstallDefinitionRows)) {
                                if ([string]$definitionRow.DefinitionPath -eq [string]$item.DefinitionPath) {
                                    $definitionRow.LatestVersion = [string]$item.LatestVersion
                                    break
                                }
                            }
                        }

                        foreach ($item in @($result.Failed)) {
                            Write-UILog -SyncHash $syncHash -Message "Install: failed '$([string]$item.Name)': $([string]$item.Error)" -Level Error
                        }
                    }

                    & $setInstallElevationState
                    & $refreshInstallRows
                }
                finally {
                    & $setInstallLoadingState -IsLoading $false
                }
            })

        $pollTimer.Start()
    }

    $startIntuneImportOperation = {
        if ($syncHash.IsIntuneImportLoading) {
            Write-UILog -SyncHash $syncHash -Message 'Intune: another import action is already in progress.' -Level Warning
            return
        }

        # Gather actionable rows from the list view selection
        $selectedRows = @($intuneWin32AppsListView.SelectedItems)
        $actionableRows = @($selectedRows | Where-Object {
                [string]$_.ImportAction -eq 'Import new app' -or [string]$_.ImportAction -eq 'Import new version and supersede'
            })

        if ($actionableRows.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Intune: no actionable rows selected. Select rows with "Import as new app" or "Update app" import action.' -Level Warning
            return
        }

        # Verify required output path
        $packageOutputPath = & $normalizeDirectoryPath -PathValue ([string]$intunePackageOutputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($packageOutputPath)) {
            Write-UILog -SyncHash $syncHash -Message 'Intune: package output path is not configured. Set it in the Intune settings pane first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $packageOutputPath -PathType Container)) {
            try { $null = New-Item -ItemType Directory -Path $packageOutputPath -Force -ErrorAction Stop }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Intune: cannot create package output path '$packageOutputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        # IntuneWin32App module is still required for New-IntuneWin32AppPackage (packaging only)
        if (-not (& $loadIntuneWin32AppModule)) {
            Write-UILog -SyncHash $syncHash -Message 'Intune: IntuneWin32App module is required for .intunewin packaging but could not be loaded.' -Level Warning
            return
        }

        # Build serialisable action list for the runspace
        $importActions = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $actionableRows) {
            $defPath = [string]$row.DefinitionPath
            if ([string]::IsNullOrWhiteSpace($defPath) -or -not (Test-Path -LiteralPath $defPath -PathType Leaf)) {
                Write-UILog -SyncHash $syncHash -Message "Intune: skipping '$([string]$row.DefinitionDisplayName)' - App.json not found at '$defPath'." -Level Warning
                continue
            }

            $importActions.Add([PSCustomObject]@{
                    AppName          = [string]$row.DefinitionDisplayName
                    DefinitionPath   = $defPath
                    PreviousAppId    = [string]$row.IntuneAppId
                    IsUpdate         = ([string]$row.IsMatched -eq 'Yes' -and [string]$row.UpdateRequired -eq 'Yes')
                    PSPackageFactory = [string]$row.PSPackageFactoryGuid
                })
        }

        if ($importActions.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Intune: no rows could be processed (check that DefinitionPath is set for selected rows).' -Level Warning
            return
        }

        # Clean up any stale async state
        if ($null -ne $syncHash.PendingIntuneImportTimer -and $syncHash.PendingIntuneImportTimer.IsEnabled) {
            $syncHash.PendingIntuneImportTimer.Stop()
            $syncHash.PendingIntuneImportTimer = $null
        }
        foreach ($key in @('PendingIntuneImportPS', 'PendingIntuneImportRunspace', 'PendingIntuneImportAsync')) {
            $syncHash[$key] = $null
        }

        & $setIntuneImportLoadingState -IsLoading $true -Message "Importing $($importActions.Count) app(s)..."
        Write-UILog -SyncHash $syncHash -Message "Intune: starting import of $($importActions.Count) app(s)..." -Level Info

        # Resolve required private helper scripts explicitly so the runspace does not import the full UI module.
        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $helperScripts = @(
            'Write-UILog.ps1'
            'Get-IntunePackageLatestVersion.ps1'
            'Invoke-IntunePackageBuild.ps1'
            'Invoke-IntuneGraphWin32Import.ps1'
            'Set-IntuneGraphWin32Supersedence.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]$HelperScripts,
                    [object[]]$ImportActions,
                    [string]  $WorkingPath
                )

                $result = [PSCustomObject]@{
                    Success   = $false
                    Completed = [System.Collections.Generic.List[object]]::new()
                    Failed    = [System.Collections.Generic.List[object]]::new()
                    Error     = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }

                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Save-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    if (-not (Get-Command -Name 'New-IntuneWin32AppPackage' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name IntuneWin32App -ErrorAction Stop | Out-Null
                        Write-UILog -Message "IntuneWin32App module loaded in import runspace." -Level Info -SyncHash $syncHash
                    }

                    $totalCount = $ImportActions.Count
                    $itemIndex = 0

                    foreach ($action in $ImportActions) {
                        $itemIndex++
                        $statusMsg = "[$itemIndex/$totalCount] $($action.AppName)"

                        $syncHash.Window.Dispatcher.Invoke([action] {
                                if ($null -ne $syncHash.IntuneImportLoadingLabel) {
                                    $syncHash.IntuneImportLoadingLabel.Text = $statusMsg
                                }
                                if ($null -ne $syncHash.IntuneActionStatusLabel) {
                                    $syncHash.IntuneActionStatusLabel.Text = $statusMsg
                                }
                            }, 'Normal')

                        # Load definition object from disk
                        $definitionObject = $null
                        try {
                            $definitionObject = Get-Content -LiteralPath $action.DefinitionPath -Raw -ErrorAction Stop |
                            ConvertFrom-Json -ErrorAction Stop
                        }
                        catch {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = "Failed to load App.json: $($_.Exception.Message)" })
                            continue
                        }

                        # Stage 1: resolve latest version, download, and package
                        $buildResult = Invoke-IntunePackageBuild -ComparisonRow ([PSCustomObject]@{
                                DefinitionPath   = $action.DefinitionPath
                                DefinitionObject = $definitionObject
                                DefinitionId     = $action.DefinitionPath
                            }) -WorkingPath $WorkingPath -SyncHash $syncHash

                        if (-not $buildResult.Succeeded) {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = "Build: $($buildResult.Error)" })
                            continue
                        }

                        # Stage 2: upload to Intune via Graph
                        $importResult = Invoke-IntuneGraphWin32Import `
                            -DefinitionObject  $definitionObject `
                            -IntuneWinPath     $buildResult.IntuneWinPath `
                            -SetupFilePath     $buildResult.SetupFileUsed `
                            -DownloadedVersion $buildResult.DownloadedVersion `
                            -PSPackageFactoryGuid $action.PSPackageFactory `
                            -DefinitionPath    $action.DefinitionPath `
                            -SyncHash          $syncHash

                        if (-not $importResult.Succeeded) {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = "Import: $($importResult.Error)" })
                            continue
                        }

                        # Stage 3: configure supersedence for updates
                        if ($action.IsUpdate -and -not [string]::IsNullOrWhiteSpace($action.PreviousAppId)) {
                            $superResult = Set-IntuneGraphWin32Supersedence `
                                -NewAppId      $importResult.IntuneAppId `
                                -PreviousAppId $action.PreviousAppId `
                                -SyncHash      $syncHash

                            if (-not $superResult.Succeeded) {
                                Write-UILog -Message "Supersedence warning for '$($action.AppName)': $($superResult.Error)" -Level Warning -SyncHash $syncHash
                            }
                        }

                        $result.Completed.Add([PSCustomObject]@{
                                AppName     = $action.AppName
                                AppId       = $importResult.IntuneAppId
                                DisplayName = $importResult.DisplayName
                                Version     = $buildResult.DownloadedVersion
                            })
                    }

                    $result.Success = $true
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result

            }).AddArgument(@($helperScripts)).AddArgument(@($importActions)).AddArgument($packageOutputPath)

        $syncHash.PendingIntuneImportPS = $ps
        $syncHash.PendingIntuneImportRunspace = $rs
        $syncHash.PendingIntuneImportAsync = $ps.BeginInvoke()

        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $syncHash.PendingIntuneImportTimer = $pollTimer

        $pollTimer.add_Tick({
                if ($null -eq $syncHash.PendingIntuneImportAsync -or -not $syncHash.PendingIntuneImportAsync.IsCompleted) {
                    return
                }

                if ($null -ne $syncHash.PendingIntuneImportTimer) {
                    $syncHash.PendingIntuneImportTimer.Stop()
                    $syncHash.PendingIntuneImportTimer = $null
                }

                $result = $null
                try {
                    $output = $syncHash.PendingIntuneImportPS.EndInvoke($syncHash.PendingIntuneImportAsync)
                    $result = if ($null -ne $output -and $output.Count -gt 0) { $output[$output.Count - 1] } else { $null }
                }
                catch {
                    $result = [PSCustomObject]@{ Success = $false; Completed = @(); Failed = @(); Error = $_.Exception.Message }
                }
                finally {
                    try { $syncHash.PendingIntuneImportPS.Dispose() } catch {}
                    try { $syncHash.PendingIntuneImportRunspace.Dispose() } catch {}
                    $syncHash.PendingIntuneImportPS = $null
                    $syncHash.PendingIntuneImportRunspace = $null
                    $syncHash.PendingIntuneImportAsync = $null
                }

                try {
                    if ($null -eq $result -or -not $result.Success) {
                        $errMsg = if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result.Error)) { 'Unknown error during import.' } else { $result.Error }
                        Write-UILog -SyncHash $syncHash -Message "Intune: import run failed: $errMsg" -Level Error
                    }
                    else {
                        $completedCount = @($result.Completed).Count
                        $failedCount = @($result.Failed).Count
                        Write-UILog -SyncHash $syncHash -Message "Intune: import complete - $completedCount succeeded, $failedCount failed." -Level Info
                        foreach ($item in @($result.Completed)) {
                            Write-UILog -SyncHash $syncHash -Message "  + Imported '$($item.DisplayName)' v$($item.Version) (id: $($item.AppId))" -Level Info
                        }
                        foreach ($item in @($result.Failed)) {
                            Write-UILog -SyncHash $syncHash -Message "  - Failed '$($item.AppName)': $($item.Error)" -Level Error
                        }
                    }

                    # Clear loading state before refresh, otherwise loadIntuneWin32Apps exits early.
                    & $setIntuneImportLoadingState -IsLoading $false

                    # Refresh the comparison table against the updated Intune catalog
                    & $loadIntuneWin32Apps
                }
                finally {
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
        $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed
        $appDetailLoading.Visibility = [System.Windows.Visibility]::Visible
        $appDetailLoadingLabel.Text = "Retrieving details for $appName with Evergreen..."

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
        $syncHash.PendingLoadPS = $ps
        $syncHash.PendingLoadRunspace = $runspace
        $syncHash.PendingLoadAppName = $appName
        $syncHash.PendingLoadAsync = $ps.BeginInvoke()

        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $syncHash.PendingLoadTimer = $pollTimer

        $pollTimer.add_Tick({
                # Guard against null (can happen if cancelled between ticks)
                if ($null -eq $syncHash.PendingLoadAsync -or -not $syncHash.PendingLoadAsync.IsCompleted) { return }

                $syncHash.PendingLoadTimer.Stop()
                $syncHash.PendingLoadTimer = $null

                # Grab refs before clearing syncHash slots
                $currentPS = $syncHash.PendingLoadPS
                $currentRunspace = $syncHash.PendingLoadRunspace
                $currentAsync = $syncHash.PendingLoadAsync
                $currentAppName = $syncHash.PendingLoadAppName

                $syncHash.PendingLoadPS = $null
                $syncHash.PendingLoadRunspace = $null
                $syncHash.PendingLoadAsync = $null
                $syncHash.PendingLoadAppName = $null

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
                    $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible

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

        & $updateDownloadAllButtonState
    }

    $updateDownloadAllButtonState = {
        if ($null -eq $syncHash.DownloadAllButton) {
            return
        }

        $pathValue = ''
        if ($null -ne $outputPathBox -and -not [string]::IsNullOrWhiteSpace([string]$outputPathBox.Text)) {
            $pathValue = [string]$outputPathBox.Text
        }
        elseif ($null -ne $syncHash.Config -and $syncHash.Config.PSObject.Properties.Name -contains 'OutputPath') {
            $pathValue = [string]$syncHash.Config.OutputPath
        }

        $normalisedPathValue = if ([string]::IsNullOrWhiteSpace($pathValue)) { '' } else { $pathValue.Trim().Trim('"') }
        $hasOutputPath = -not [string]::IsNullOrWhiteSpace($normalisedPathValue)
        $hasQueueItems = $syncHash.DownloadQueue.Count -gt 0

        $syncHash.DownloadAllButton.IsEnabled = (-not $syncHash.IsRunning) -and $hasQueueItems -and $hasOutputPath
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

    $setImportTabVisibility = {
        param(
            [bool]$ShowImport,
            [bool]$ShowInstall
        )

        if ($null -ne $navImport) {
            $navImport.Visibility = if ($ShowImport) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }

            if (-not $ShowImport -and $navImport.IsChecked) {
                $navApps.IsChecked = $true
            }
        }

        if ($null -ne $navInstall) {
            $navInstall.Visibility = if ($ShowInstall) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }

            if (-not $ShowInstall -and $navInstall.IsChecked) {
                $navApps.IsChecked = $true
            }
        }

        if ($null -ne $startupViewComboBox) {
            $startupItems = @{}
            foreach ($candidate in @($startupViewComboBox.Items)) {
                if ($candidate -is [System.Windows.Controls.ComboBoxItem]) {
                    $startupItems[[string]$candidate.Content] = $candidate
                }
            }

            if ($startupItems.ContainsKey('Import')) {
                $startupItems['Import'].IsEnabled = $ShowImport
            }
            if ($startupItems.ContainsKey('Install')) {
                $startupItems['Install'].IsEnabled = $ShowInstall
            }

            $startupView = [string]$syncHash.Config.StartupView
            if (($startupView -eq 'Import' -and -not $ShowImport) -or ($startupView -eq 'Install' -and -not $ShowInstall)) {
                $syncHash.Config.StartupView = 'Apps'
                $startupViewComboBox.SelectedIndex = 0
            }
        }
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
        elseif ($navInstall.IsChecked) {
            return 'Install'
        }
        elseif ($navSettings.IsChecked) {
            return 'Settings'
        }
        elseif ($navUpdate.IsChecked) {
            return 'Update'
        }
        elseif ($navAbout.IsChecked) {
            return 'About'
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
        $syncHash.Config.ShowImportTab = if ($null -eq $showImportTabCheckBox) { [bool]$syncHash.Config.ShowImportTab } else { [bool]$showImportTabCheckBox.IsChecked }
        $syncHash.Config.ShowInstallTab = if ($null -eq $showInstallTabCheckBox) { [bool]$syncHash.Config.ShowInstallTab } else { [bool]$showInstallTabCheckBox.IsChecked }
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
        $selectedNmeResourceGroup = [string]$nmeResourceGroupCombo.SelectedItem
        if (-not [string]::IsNullOrWhiteSpace($selectedNmeResourceGroup)) {
            $syncHash.Config.NerdioSettings.NmeResourceGroup = $selectedNmeResourceGroup
        }

        $selectedNmeStorageAccount = [string]$nmeStorageAccountCombo.SelectedItem
        if (-not [string]::IsNullOrWhiteSpace($selectedNmeStorageAccount)) {
            $syncHash.Config.NerdioSettings.NmeStorageAccount = $selectedNmeStorageAccount
        }

        $selectedNmeContainer = [string]$nmeContainerCombo.SelectedItem
        if (-not [string]::IsNullOrWhiteSpace($selectedNmeContainer)) {
            $syncHash.Config.NerdioSettings.NmeContainer = $selectedNmeContainer
        }

        $syncHash.Config.NerdioSettings.DefinitionsPath = & $normalizeDirectoryPath -PathValue ([string]$nerdioDefinitionsPathBox.Text)

        $syncHash.Config.IntuneSettings.DefinitionsPath = & $normalizeDirectoryPath -PathValue ([string]$intuneDefinitionsPathBox.Text)
        $syncHash.Config.IntuneSettings.PackageOutputPath = & $normalizeDirectoryPath -PathValue ([string]$intunePackageOutputPathBox.Text)

        if ($null -eq $syncHash.Config.InstallSettings) {
            $syncHash.Config | Add-Member -NotePropertyName 'InstallSettings' -NotePropertyValue ([PSCustomObject]@{
                    DefinitionsPath = ''
                }) -Force
        }

        $syncHash.Config.InstallSettings.DefinitionsPath = & $normalizeDirectoryPath -PathValue ([string]$installDefinitionsPathBox.Text)

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
        $canCompareIntune = (-not $syncHash.IsIntuneImportLoading) -and $state.IsAuthenticated -and $state.IntuneConnected

        if ($null -ne $intuneRefreshCatalogButton) {
            $intuneRefreshCatalogButton.IsEnabled = $canCompareIntune
        }

        $setIntuneConnectionStatus = {
            param(
                [System.Windows.Media.Brush]$Brush,
                [string]$Text
            )

            if ($null -ne $intuneConnectionStatusDot) {
                $intuneConnectionStatusDot.Fill = $Brush
            }

            if ($null -ne $intuneConnectionStatusLabel) {
                $intuneConnectionStatusLabel.Text = $Text
            }
        }

        if ($state.IsAuthInProgress) {
            $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::Gold
            $importAuthStatusLabel.Text = 'Signing in...'
            & $setIntuneConnectionStatus -Brush ([System.Windows.Media.Brushes]::Gold) -Text 'Signing in...'
            $importSignInButton.IsEnabled = $false
            $importSignOutButton.IsEnabled = $false
            return
        }

        if ($state.IsAuthenticated) {
            $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
            $account = if ([string]::IsNullOrWhiteSpace($state.AccountId)) { 'signed in' } else { $state.AccountId }
            $tenant = if ([string]::IsNullOrWhiteSpace($state.TenantId)) { '' } else { " | tenant: $($state.TenantId)" }
            $intune = if ($state.IntuneConnected) { ' | Intune: connected' } else { '' }
            $importAuthStatusLabel.Text = "$account$tenant$intune"

            if ($state.IntuneConnected) {
                & $setIntuneConnectionStatus -Brush ([System.Windows.Media.Brushes]::LightGreen) -Text 'Connected'
            }
            else {
                & $setIntuneConnectionStatus -Brush ([System.Windows.Media.Brushes]::OrangeRed) -Text 'Signed in, Intune token failed'
            }

            $importSignInButton.IsEnabled = $false
            $importSignOutButton.IsEnabled = $true
            return
        }

        $importAuthStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
        & $setIntuneConnectionStatus -Brush ([System.Windows.Media.Brushes]::OrangeRed) -Text 'Not signed in'
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
        $applyStateToImportTab = {
            param(
                [System.Windows.Media.Brush]$Brush,
                [string]$LabelText
            )

            if ($null -ne $nerdioImportAuthStatusDot) {
                $nerdioImportAuthStatusDot.Fill = $Brush
            }

            if ($null -ne $nerdioImportAuthStatusLabel) {
                $nerdioImportAuthStatusLabel.Text = $LabelText
            }
        }

        $state = $syncHash.NerdioApiAuthState
        $canCompareShellApps = (-not $syncHash.IsNerdioShellAppsLoading) -and $state.IsAuthenticated

        if ($null -ne $nerdioListShellAppsButton) {
            $nerdioListShellAppsButton.IsEnabled = $canCompareShellApps
        }

        if ($state.IsAuthInProgress) {
            $nerdioApiAuthStatusDot.Fill = [System.Windows.Media.Brushes]::Gold
            $nerdioApiAuthStatusLabel.Text = 'Signing in...'
            & $applyStateToImportTab -Brush ([System.Windows.Media.Brushes]::Gold) -LabelText 'Signing in...'
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
            $connectedText = if ([string]::IsNullOrWhiteSpace($hostName)) { 'Connected' } else { $hostName }
            $nerdioApiAuthStatusLabel.Text = $connectedText
            & $applyStateToImportTab -Brush ([System.Windows.Media.Brushes]::LightGreen) -LabelText $connectedText
            $nerdioApiSignInButton.IsEnabled = $false
            $nerdioApiSignOutButton.IsEnabled = $true
            return
        }

        $nerdioApiAuthStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
        if ([string]::IsNullOrWhiteSpace($state.ErrorMessage)) {
            $nerdioApiAuthStatusLabel.Text = 'Not signed in'
            & $applyStateToImportTab -Brush ([System.Windows.Media.Brushes]::OrangeRed) -LabelText 'Not signed in'
        }
        else {
            $nerdioApiAuthStatusLabel.Text = 'Sign-in failed'
            & $applyStateToImportTab -Brush ([System.Windows.Media.Brushes]::OrangeRed) -LabelText 'Sign-in failed'
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
            $nerdioAzureSignInButton.IsEnabled = $false
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

    $applyInstallPathsToConfig = {
        $definitionsPath = if ($null -eq $installDefinitionsPathBox) { '' } else { [string]$installDefinitionsPathBox.Text }

        if ($null -eq $syncHash.Config.InstallSettings) {
            $syncHash.Config | Add-Member -NotePropertyName 'InstallSettings' -NotePropertyValue ([PSCustomObject]@{
                    DefinitionsPath = ''
                }) -Force
        }

        $syncHash.Config.InstallSettings.DefinitionsPath = (& $normalizeDirectoryPath -PathValue $definitionsPath)
        Set-UIConfig -Config $syncHash.Config
    }

    $testInstallElevationState = {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            return $false
        }
    }

    $getThemeStatusBrush = {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ResourceKey,

            [Parameter(Mandatory = $true)]
            [System.Windows.Media.Brush]$FallbackBrush
        )

        $themeBrush = $null
        if ($null -ne $window -and $null -ne $window.Resources -and $window.Resources.Contains($ResourceKey)) {
            $candidate = $window.Resources[$ResourceKey]
            if ($candidate -is [System.Windows.Media.Brush]) {
                $themeBrush = [System.Windows.Media.Brush]$candidate
            }
        }

        if ($null -ne $themeBrush) {
            return $themeBrush
        }

        return $FallbackBrush
    }

    $refreshNerdioModuleStatus = {
        param(
            [bool]$IsLoaded,
            [string]$Message
        )

        if ($null -eq $nerdioModuleStatusLabel) { return }

        if ($IsLoaded) {
            $nerdioModuleStatusLabel.Foreground = & $getThemeStatusBrush -ResourceKey 'StatusPositiveBrush' -FallbackBrush ([System.Windows.Media.Brushes]::LightGreen)
        }
        else {
            $nerdioModuleStatusLabel.Foreground = & $getThemeStatusBrush -ResourceKey 'StatusErrorBrush' -FallbackBrush ([System.Windows.Media.Brushes]::OrangeRed)
        }

        $nerdioModuleStatusLabel.Text = $Message
    }

    $setNerdioModuleQuietLogging = {
        param(
            [string]$Preference = 'SilentlyContinue'
        )

        try {
            $module = Get-Module -Name NerdioShellApps -ErrorAction SilentlyContinue
            if ($null -ne $module -and $null -ne $module.SessionState -and $null -ne $module.SessionState.PSVariable) {
                $module.SessionState.PSVariable.Set('InformationPreference', $Preference)
            }
        }
        catch {
            # Best effort only. If this fails, Nerdio operations should still continue.
        }
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
            & $setNerdioModuleQuietLogging -Preference 'SilentlyContinue'
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

    $refreshIntuneComparison = {
        $definitionRows = @($syncHash.IntuneDefinitionRows)
        $intuneRows = @($syncHash.IntuneWin32Rows)

        $definitionLookup = @{}
        foreach ($definitionRow in $definitionRows) {
            if ([string]$definitionRow.DefinitionValid -ne 'Yes') {
                continue
            }

            $guidText = [string]$definitionRow.PSPackageFactoryGuid
            if ([string]::IsNullOrWhiteSpace($guidText)) {
                continue
            }

            $lookupKey = $guidText.Trim().ToLowerInvariant()
            if (-not $definitionLookup.ContainsKey($lookupKey)) {
                $definitionLookup[$lookupKey] = [System.Collections.Generic.List[object]]::new()
            }

            $definitionLookup[$lookupKey].Add($definitionRow)
        }

        $matchedDefinitionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $comparisonRows = [System.Collections.Generic.List[object]]::new()

        $matchedCount = 0
        $updateRequiredCount = 0
        $unknownCount = 0
        $definitionOnlyCount = 0
        $intuneOnlyCount = 0

        foreach ($intuneRow in $intuneRows) {
            $guidText = [string]$intuneRow.NotesGuid
            $lookupKey = if ([string]::IsNullOrWhiteSpace($guidText)) { '' } else { $guidText.Trim().ToLowerInvariant() }

            $intuneDisplayName = [string]$intuneRow.DisplayName
            $baseRow = [PSCustomObject]@{
                RowType               = 'Intune'
                IntuneAppId           = [string]$intuneRow.IntuneAppId
                IntuneDisplayName     = $intuneDisplayName
                DisplayName           = $intuneDisplayName
                DefinitionDisplayName = '-'
                DisplayPublisher      = [string]$intuneRow.Publisher
                IntuneVersion         = [string]$intuneRow.DisplayVersion
                DefinitionVersion     = '-'
                PSPackageFactoryGuid  = if ([string]::IsNullOrWhiteSpace($guidText)) { '-' } else { $guidText }
                IsMatched             = 'No'
                UpdateRequired        = 'Unknown'
                MatchStatus           = 'No local definition'
                ImportAction          = '-'
                DefinitionPath        = ''
                DefinitionObject      = $null
            }

            if ([string]$intuneRow.NotesValid -ne 'Yes') {
                $baseRow.MatchStatus = 'Invalid notes JSON'
                $comparisonRows.Add($baseRow)
                $unknownCount++
                $intuneOnlyCount++
                continue
            }

            if ([string]::IsNullOrWhiteSpace($lookupKey)) {
                $baseRow.MatchStatus = 'Missing GUID in notes'
                $comparisonRows.Add($baseRow)
                $unknownCount++
                $intuneOnlyCount++
                continue
            }

            $matchedDefinitions = @()
            if ($definitionLookup.ContainsKey($lookupKey)) {
                $matchedDefinitions = @($definitionLookup[$lookupKey])
            }

            if ($matchedDefinitions.Count -eq 0) {
                $baseRow.MatchStatus = 'No local definition'
                $comparisonRows.Add($baseRow)
                $intuneOnlyCount++
                continue
            }

            if ($matchedDefinitions.Count -gt 1) {
                $baseRow.MatchStatus = 'Duplicate definition GUID'
                $baseRow.ImportAction = 'Fix in definition'
                $comparisonRows.Add($baseRow)
                $unknownCount++
                continue
            }

            $definitionRow = $matchedDefinitions[0]
            $null = $matchedDefinitionIds.Add([string]$definitionRow.DefinitionId)

            $baseRow.IsMatched = 'Yes'
            $baseRow.DefinitionDisplayName = [string]$definitionRow.Name
            $baseRow.DefinitionVersion = [string]$definitionRow.Version
            $baseRow.DefinitionPath = [string]$definitionRow.DefinitionPath
            $baseRow.DefinitionObject = $definitionRow.DefinitionObject
            if ([string]::IsNullOrWhiteSpace($baseRow.DisplayPublisher) -or $baseRow.DisplayPublisher -eq '-') {
                $baseRow.DisplayPublisher = [string]$definitionRow.Publisher
            }

            $intuneParsed = & $parseComparableVersion -VersionText ([string]$baseRow.IntuneVersion)
            $definitionParsed = & $parseComparableVersion -VersionText ([string]$baseRow.DefinitionVersion)

            if (-not $intuneParsed.Success -or -not $definitionParsed.Success) {
                $baseRow.UpdateRequired = 'Unknown'
                $baseRow.MatchStatus = 'Matched (needs review)'
                $comparisonRows.Add($baseRow)
                $matchedCount++
                $unknownCount++
                continue
            }

            if ($definitionParsed.Parsed -gt $intuneParsed.Parsed) {
                $baseRow.UpdateRequired = 'Yes'
                $baseRow.MatchStatus = 'Matched (update required)'
                $baseRow.ImportAction = 'Import new version and supersede'
                $updateRequiredCount++
            }
            else {
                $baseRow.UpdateRequired = 'No'
                $baseRow.MatchStatus = 'Matched (current)'
                $baseRow.ImportAction = '-'
            }

            $comparisonRows.Add($baseRow)
            $matchedCount++
        }

        foreach ($definitionRow in $definitionRows) {
            $definitionId = [string]$definitionRow.DefinitionId
            if ($matchedDefinitionIds.Contains($definitionId)) {
                continue
            }

            $status = [string]$definitionRow.DefinitionValid
            $isValid = ($status -eq 'Yes')
            $isDuplicateGuid = $false
            if ($isValid) {
                $guidText = [string]$definitionRow.PSPackageFactoryGuid
                if (-not [string]::IsNullOrWhiteSpace($guidText)) {
                    $lookupKey = $guidText.Trim().ToLowerInvariant()
                    if ($definitionLookup.ContainsKey($lookupKey) -and @($definitionLookup[$lookupKey]).Count -gt 1) {
                        $isDuplicateGuid = $true
                    }
                }
            }

            $defDisplayName = [string]$definitionRow.Name
            $matchStatus = 'Definition not in Intune'
            $importAction = 'Import new app'
            $updateRequired = 'Unknown'

            if (-not $isValid) {
                $matchStatus = if ([string]::IsNullOrWhiteSpace($status)) { 'Invalid definition' } else { $status }
                $importAction = '-'
            }
            elseif ($isDuplicateGuid) {
                $matchStatus = 'Duplicate definition GUID'
                $importAction = 'Fix in definition'
            }

            $comparisonRows.Add([PSCustomObject]@{
                    RowType               = 'Definition'
                    IntuneAppId           = ''
                    IntuneDisplayName     = '-'
                    DisplayName           = $defDisplayName
                    DefinitionDisplayName = $defDisplayName
                    DisplayPublisher      = [string]$definitionRow.Publisher
                    IntuneVersion         = '-'
                    DefinitionVersion     = [string]$definitionRow.Version
                    PSPackageFactoryGuid  = [string]$definitionRow.PSPackageFactoryGuid
                    IsMatched             = 'No'
                    UpdateRequired        = $updateRequired
                    MatchStatus           = $matchStatus
                    ImportAction          = $importAction
                    DefinitionPath        = [string]$definitionRow.DefinitionPath
                    DefinitionObject      = $definitionRow.DefinitionObject
                })

            if ($isValid -and -not $isDuplicateGuid) {
                $definitionOnlyCount++
            }
            else {
                $unknownCount++
            }
        }

        $sortedRows = @(
            $comparisonRows | Sort-Object -Property `
            @{ Expression = {
                    if ([string]$_.ImportAction -eq 'Import new app') { return 0 }
                    if ([string]$_.UpdateRequired -eq 'Yes') { return 1 }
                    if ([string]$_.UpdateRequired -eq 'Unknown') { return 2 }
                    if ([string]$_.RowType -eq 'Intune') { return 3 }
                    return 4
                } 
            },
            DisplayPublisher,
            DefinitionDisplayName,
            IntuneDisplayName,
            PSPackageFactoryGuid
        )

        $syncHash.IntuneComparisonRows = $sortedRows
        if ($null -ne $intuneWin32AppsListView) {
            $intuneWin32AppsListView.ItemsSource = $sortedRows
            & $applyIntuneListSort
        }

        if ($null -ne $intuneWin32AppsCountLabel) {
            $intuneWin32AppsCountLabel.Text = "$($intuneRows.Count) apps | $($sortedRows.Count) rows"
        }

        if ($null -ne $intuneActionStatusLabel) {
            $intuneActionStatusLabel.Text = "Matched: $matchedCount | Update required: $updateRequiredCount | New imports: $definitionOnlyCount | Intune only: $intuneOnlyCount | Needs review: $unknownCount"
        }

        Write-UILog -SyncHash $syncHash -Message "Intune compare complete: rows=$($sortedRows.Count), matched=$matchedCount, update required=$updateRequiredCount, new imports=$definitionOnlyCount, intune only=$intuneOnlyCount, needs review=$unknownCount." -Level Info
    }

    $loadIntuneDefinitions = {
        $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$intuneDefinitionsPathBox.Text)
        $intuneDefinitionsPathBox.Text = $definitionsRoot
        & $applyIntunePathsToConfig

        if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
            $syncHash.IntuneDefinitionRows = @()
            if ($null -ne $intuneDefinitionsCountLabel) {
                $intuneDefinitionsCountLabel.Text = '0 loaded'
            }
            & $refreshIntuneComparison
            Write-UILog -SyncHash $syncHash -Message 'Intune: provide a package definitions folder path first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $definitionsRoot -PathType Container)) {
            $syncHash.IntuneDefinitionRows = @()
            if ($null -ne $intuneDefinitionsCountLabel) {
                $intuneDefinitionsCountLabel.Text = '0 loaded'
            }
            & $refreshIntuneComparison
            Write-UILog -SyncHash $syncHash -Message "Intune: definitions path does not exist: $definitionsRoot" -Level Warning
            return
        }

        $definitionFiles = @()
        try {
            $definitionFiles = @(Get-ChildItem -LiteralPath $definitionsRoot -Recurse -File -ErrorAction Stop | Where-Object { $_.Name -ieq 'App.json' })
        }
        catch {
            $syncHash.IntuneDefinitionRows = @()
            if ($null -ne $intuneDefinitionsCountLabel) {
                $intuneDefinitionsCountLabel.Text = '0 loaded'
            }
            & $refreshIntuneComparison
            Write-UILog -SyncHash $syncHash -Message "Intune: failed to enumerate App.json files: $($_.Exception.Message)" -Level Error
            return
        }

        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($definitionFile in $definitionFiles) {
            $definitionObject = $null
            $name = [string](Split-Path -Path $definitionFile.DirectoryName -Leaf)
            $publisher = '-'
            $version = '-'
            $guidText = ''
            $status = 'Invalid JSON'

            try {
                $definitionObject = Get-Content -LiteralPath $definitionFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

                if ($null -ne $definitionObject.Information) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$definitionObject.Information.DisplayName)) {
                        $name = ([string]$definitionObject.Information.DisplayName).Trim()
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$definitionObject.Information.Publisher)) {
                        $publisher = ([string]$definitionObject.Information.Publisher).Trim()
                    }
                    $guidText = ([string]$definitionObject.Information.PSPackageFactoryGuid).Trim()
                }

                if ($null -ne $definitionObject.PackageInformation -and -not [string]::IsNullOrWhiteSpace([string]$definitionObject.PackageInformation.Version)) {
                    $version = ([string]$definitionObject.PackageInformation.Version).Trim()
                }

                if ([string]::IsNullOrWhiteSpace($guidText)) {
                    $status = 'Missing PSPackageFactoryGuid'
                }
                else {
                    try {
                        [void][guid]$guidText
                        $status = 'Yes'
                    }
                    catch {
                        $status = 'Invalid PSPackageFactoryGuid'
                    }
                }
            }
            catch {
                $status = 'Invalid JSON'
            }

            $rows.Add([PSCustomObject]@{
                    DefinitionId         = [string]$definitionFile.FullName
                    DefinitionPath       = [string]$definitionFile.FullName
                    Name                 = $name
                    Publisher            = $publisher
                    Version              = $version
                    Status               = if ($status -eq 'Yes') { 'Valid' } else { $status }
                    DefinitionValid      = $status
                    PSPackageFactoryGuid = $guidText
                    DefinitionObject     = $definitionObject
                })
        }

        $sortedRows = @($rows | Sort-Object -Property Publisher, Name, DefinitionPath)
        $syncHash.IntuneDefinitionRows = $sortedRows

        if ($null -ne $intuneDefinitionsCountLabel) {
            $validCount = @($sortedRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count
            $intuneDefinitionsCountLabel.Text = "$($sortedRows.Count) loaded ($validCount valid)"
        }

        & $refreshIntuneComparison

        if ($sortedRows.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message "Intune: no App.json files found under '$definitionsRoot'." -Level Warning
        }
        else {
            $validCount = @($sortedRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count
            Write-UILog -SyncHash $syncHash -Message "Intune: loaded $($sortedRows.Count) definitions from App.json files ($validCount valid)." -Level Info
        }
    }

    $loadIntuneWin32Apps = {
        if ($syncHash.IsIntuneImportLoading) {
            return
        }

        if ($null -ne $syncHash.PendingIntuneImportTimer -and $syncHash.PendingIntuneImportTimer.IsEnabled) {
            $syncHash.PendingIntuneImportTimer.Stop()
            $syncHash.PendingIntuneImportTimer = $null
        }

        foreach ($pendingOp in @('PendingIntuneImportPS', 'PendingIntuneImportRunspace', 'PendingIntuneImportAsync')) {
            $syncHash[$pendingOp] = $null
        }

        & $setIntuneImportLoadingState -IsLoading $true -Message 'Listing Win32 apps from Microsoft Intune...'
        Write-UILog -SyncHash $syncHash -Message 'Intune: retrieving Win32 apps via Microsoft Graph...' -Level Info

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                $result = [PSCustomObject]@{
                    Success = $false
                    Rows    = @()
                    Error   = ''
                }

                try {
                    if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
                        throw 'Invoke-MgGraphRequest is not available. Ensure Microsoft.Graph.Authentication is imported and Connect-MgGraph has been called.'
                    }

                    $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$filter=isOf(''microsoft.graph.win32LobApp'')&$top=999'
                    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
                    $rawApps = @($response.value)

                    $rows = [System.Collections.Generic.List[object]]::new()

                    foreach ($application in $rawApps) {
                        if ($null -eq $application) {
                            continue
                        }

                        $notesText = [string]$application.notes
                        $notesJson = $null
                        $notesValid = 'No'

                        if (-not [string]::IsNullOrWhiteSpace($notesText)) {
                            try {
                                $notesJson = $notesText | ConvertFrom-Json -ErrorAction Stop
                                $notesValid = 'Yes'
                            }
                            catch {
                                $notesValid = 'No'
                            }
                        }

                        $createdBy = if ($null -ne $notesJson -and $notesJson.PSObject.Properties.Name -contains 'CreatedBy') { [string]$notesJson.CreatedBy } else { '' }
                        $guidText = if ($null -ne $notesJson -and $notesJson.PSObject.Properties.Name -contains 'Guid') { [string]$notesJson.Guid }      else { '' }
                        $isPsPackageFactory = ($notesText -match 'PSPackageFactory') -or ($createdBy -ieq 'PSPackageFactory')

                        if (-not $isPsPackageFactory) {
                            continue
                        }

                        $rows.Add([PSCustomObject]@{
                                IntuneAppId    = [string]$application.id
                                DisplayName    = [string]$application.displayName
                                Publisher      = [string]$application.publisher
                                DisplayVersion = [string]$application.displayVersion
                                NotesGuid      = $guidText
                                NotesValid     = $notesValid
                            })
                    }

                    $result.Success = $true
                    $result.Rows = @($rows | Sort-Object -Property Publisher, DisplayName, IntuneAppId)
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            })

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

                $result = $null
                try {
                    $output = $syncHash.PendingIntuneImportPS.EndInvoke($syncHash.PendingIntuneImportAsync)
                    if ($null -ne $output -and $output.Count -gt 0) {
                        $result = $output[$output.Count - 1]
                    }
                }
                catch {
                    $result = [PSCustomObject]@{ Success = $false; Rows = @(); Error = $_.Exception.Message }
                }
                finally {
                    try { $syncHash.PendingIntuneImportPS.Dispose() } catch {}
                    try { $syncHash.PendingIntuneImportRunspace.Dispose() } catch {}
                    $syncHash.PendingIntuneImportPS = $null
                    $syncHash.PendingIntuneImportRunspace = $null
                    $syncHash.PendingIntuneImportAsync = $null
                }

                try {
                    if ($null -eq $result -or -not $result.Success) {
                        $syncHash.IntuneWin32Rows = @()
                        $errorMessage = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Error)) { 'Unknown error occurred while listing Win32 apps.' } else { [string]$result.Error }
                        Write-UILog -SyncHash $syncHash -Message "Intune: failed to list Win32 apps: $errorMessage" -Level Error
                    }
                    else {
                        $rows = @($result.Rows)
                        $syncHash.IntuneWin32Rows = $rows
                        Write-UILog -SyncHash $syncHash -Message "Intune: loaded $($rows.Count) Win32 app(s) tagged by PSPackageFactory." -Level Info
                    }

                    & $refreshIntuneComparison
                }
                finally {
                    & $setIntuneImportLoadingState -IsLoading $false
                }
            })

        $pollTimer.Start()
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

        if ([string]$DefinitionRow.SourceType -ieq 'Evergreen') {
            $sourceApp = [string]$DefinitionRow.SourceApp
            $sourceFilter = [string]$DefinitionRow.SourceFilter

            if (-not [string]::IsNullOrWhiteSpace($sourceApp)) {
                $escapedSourceApp = $sourceApp.Replace("'", "''")
                $commandMessage = if ([string]::IsNullOrWhiteSpace($sourceFilter)) {
                    "Get-EvergreenApp -Name '$escapedSourceApp'"
                }
                else {
                    "Get-EvergreenApp -Name '$escapedSourceApp' | Where-Object { $sourceFilter }"
                }

                Write-UILog -SyncHash $syncHash -Message $commandMessage -Level Cmd
            }
        }

        return (& $getAppMetadataCommand -Definition $DefinitionRow.DefinitionObject)
    }

    $refreshNerdioComparison = {
        $definitionRows = @($syncHash.NerdioDefinitionRows)
        $shellAppRows = @($syncHash.NerdioShellAppRows)

        $evergreenCache = @{}
        $comparisonRows = [System.Collections.Generic.List[object]]::new()
        $matchedShellAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $shellAppMatchLookup = @{}

        foreach ($shellAppRow in $shellAppRows) {
            $lookupKey = ('{0}|{1}' -f ([string]$shellAppRow.Publisher).Trim(), ([string]$shellAppRow.Name).Trim()).ToLowerInvariant()
            if (-not $shellAppMatchLookup.ContainsKey($lookupKey)) {
                $shellAppMatchLookup[$lookupKey] = [System.Collections.Generic.List[object]]::new()
            }

            $shellAppMatchLookup[$lookupKey].Add($shellAppRow)
        }

        $matchedCount = 0
        $updateCount = 0
        $compareUnavailableCount = 0
        $definitionOnlyCount = 0
        $nerdioOnlyCount = 0
        $duplicateCount = 0

        foreach ($definitionRow in $definitionRows) {
            $publisher = [string]$definitionRow.Publisher
            $appName = [string]$definitionRow.AppName
            $definitionValid = [string]$definitionRow.DefinitionValid
            $sourceType = [string]$definitionRow.SourceType
            $lookupKey = ('{0}|{1}' -f $publisher.Trim(), $appName.Trim()).ToLowerInvariant()

            $baseRow = [PSCustomObject]@{
                RowType          = 'Definition'
                DefinitionPath   = [string]$definitionRow.DefinitionPath
                Publisher        = $publisher
                AppName          = $appName
                DisplayName      = $appName
                NerdioAppName    = '-'
                NerdioAppId      = ''
                VersionCount     = '-'
                DefinitionValid  = $definitionValid
                MatchStatus      = '-'
                NerdioVersion    = '-'
                EvergreenVersion = '-'
                UpdateNeeded     = '-'
                Action           = '-'
                IsMatched        = 'No'
                IsNewApp         = 'No'
                HasDefinition    = 'Yes'
                HasNerdioApp     = 'No'
                CompareMessage   = ''
            }

            if ($definitionValid -ne 'Yes') {
                $baseRow.MatchStatus = 'Invalid definition'
                $baseRow.IsNewApp = 'No'
                $comparisonRows.Add($baseRow)
                continue
            }

            if ($sourceType -ine 'Evergreen') {
                $baseRow.MatchStatus = 'Unsupported source type'
                $baseRow.CompareMessage = "Source type '$sourceType' is not supported for compare."
                $baseRow.IsNewApp = 'No'
                $comparisonRows.Add($baseRow)
                continue
            }

            $matchedRows = @()
            if ($shellAppMatchLookup.ContainsKey($lookupKey)) {
                $matchedRows = @($shellAppMatchLookup[$lookupKey])
            }

            if ($matchedRows.Count -eq 0) {
                $baseRow.MatchStatus = 'No matching Shell App'
                $baseRow.CompareMessage = 'Definition has no match in Nerdio Manager.'
                $baseRow.IsNewApp = 'Yes'
                $baseRow.Action = 'Import'
                $definitionOnlyCount++
                $comparisonRows.Add($baseRow)
                continue
            }

            if ($matchedRows.Count -gt 1) {
                $baseRow.MatchStatus = 'Duplicate matches'
                $baseRow.CompareMessage = 'More than one Nerdio Shell App matched by publisher and name.'
                $baseRow.IsNewApp = 'No'
                $duplicateCount++
                $comparisonRows.Add($baseRow)
                continue
            }

            $matchedShellApp = $matchedRows[0]
            $baseRow.MatchStatus = 'Matched'
            $baseRow.IsMatched = 'Yes'
            $baseRow.IsNewApp = 'No'
            $baseRow.HasNerdioApp = 'Yes'
            $baseRow.NerdioAppName = [string]$matchedShellApp.Name
            $baseRow.NerdioAppId = [string]$matchedShellApp.Id
            $baseRow.NerdioVersion = [string]$matchedShellApp.LatestVersion
            $baseRow.VersionCount = if ([string]$matchedShellApp.VersionCount -match '^\d+$') { [string]$matchedShellApp.VersionCount } else { '-' }
            $null = $matchedShellAppIds.Add([string]$matchedShellApp.Id)
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
                    $baseRow.MatchStatus = 'Matched (compare unavailable)'
                    $baseRow.CompareMessage = "Evergreen lookup failed: $($_.Exception.Message)"
                    $baseRow.UpdateNeeded = 'Compare unavailable'
                    $comparisonRows.Add($baseRow)
                    $compareUnavailableCount++
                    continue
                }
            }

            if ($null -eq $evergreenMetadata -or [string]::IsNullOrWhiteSpace([string]$evergreenMetadata.Version)) {
                $baseRow.MatchStatus = 'Matched (compare unavailable)'
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
                $baseRow.MatchStatus = 'Matched (compare unavailable)'
                $baseRow.UpdateNeeded = 'Compare unavailable'
                $baseRow.CompareMessage = "Unable to parse versions. Nerdio='$($baseRow.NerdioVersion)' Evergreen='$($baseRow.EvergreenVersion)'"
                $comparisonRows.Add($baseRow)
                $compareUnavailableCount++
                continue
            }

            if ($evergreenParsed.Parsed -gt $nerdioParsed.Parsed) {
                $baseRow.MatchStatus = 'Matched (update available)'
                $baseRow.UpdateNeeded = 'Yes'
                $baseRow.Action = 'Update'
                $baseRow.CompareMessage = 'Evergreen version is newer than Nerdio latest version.'
                $updateCount++
            }
            else {
                $baseRow.MatchStatus = 'Matches (No update required)'
                $baseRow.UpdateNeeded = 'No'
                $baseRow.CompareMessage = 'Nerdio latest version is current.'
            }

            $comparisonRows.Add($baseRow)
        }

        foreach ($shellAppRow in $shellAppRows) {
            $shellAppId = [string]$shellAppRow.Id
            if ($matchedShellAppIds.Contains($shellAppId)) {
                continue
            }

            $nerdioOnlyName = [string]$shellAppRow.Name
            $comparisonRows.Add([PSCustomObject]@{
                    RowType          = 'Nerdio'
                    DefinitionPath   = ''
                    Publisher        = [string]$shellAppRow.Publisher
                    AppName          = '-'
                    DisplayName      = $nerdioOnlyName
                    NerdioAppName    = $nerdioOnlyName
                    NerdioAppId      = $shellAppId
                    VersionCount     = if ([string]$shellAppRow.VersionCount -match '^\d+$') { [string]$shellAppRow.VersionCount } else { '-' }
                    DefinitionValid  = '-'
                    MatchStatus      = 'No local definition'
                    NerdioVersion    = [string]$shellAppRow.LatestVersion
                    EvergreenVersion = '-'
                    UpdateNeeded     = '-'
                    Action           = '-'
                    IsMatched        = 'No'
                    IsNewApp         = 'No'
                    HasDefinition    = 'No'
                    HasNerdioApp     = 'Yes'
                    CompareMessage   = 'Nerdio Shell App was not matched to a local definition.'
                })
            $nerdioOnlyCount++
        }

        $sortedRows = @(
            $comparisonRows | Sort-Object -Property `
            @{ Expression = {
                    if ([string]$_.IsNewApp -eq 'Yes') { return 0 }
                    if ([string]$_.UpdateNeeded -eq 'Yes') { return 1 }
                    if ([string]$_.UpdateNeeded -eq 'Compare unavailable') { return 2 }
                    if ([string]$_.MatchStatus -eq 'Duplicate matches') { return 3 }
                    if ([string]$_.MatchStatus -eq 'Invalid definition') { return 4 }
                    if ([string]$_.MatchStatus -eq 'Unsupported source type') { return 5 }
                    if ([string]$_.RowType -eq 'Nerdio') { return 6 }
                    return 7
                } 
            },
            Publisher,
            AppName,
            RowType,
            NerdioAppId
        )
        $syncHash.NerdioComparisonRows = $sortedRows
        $nerdioDefinitionsListView.ItemsSource = $sortedRows

        if ($null -ne $nerdioDefinitionsCountLabel) {
            $validDefinitionCount = @($definitionRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count
            $nerdioDefinitionsCountLabel.Text = "$($definitionRows.Count) definitions ($validDefinitionCount valid)"
        }

        if ($null -ne $nerdioShellAppsCountLabel -and -not $syncHash.IsNerdioShellAppsLoading) {
            $nerdioShellAppsCountLabel.Text = "$($shellAppRows.Count) apps"
        }

        if ($null -ne $nerdioActionStatusLabel) {
            $nerdioActionStatusLabel.Text = "Rows: $($sortedRows.Count) | Matched: $matchedCount | Update needed: $updateCount | New imports: $definitionOnlyCount | Nerdio only: $nerdioOnlyCount | Duplicate matches: $duplicateCount | Compare unavailable: $compareUnavailableCount"
        }

        & $updateNerdioRowActionButtons

        Write-UILog -SyncHash $syncHash -Message "Nerdio compare complete: rows=$($sortedRows.Count), matched=$matchedCount, update needed=$updateCount, definition only=$definitionOnlyCount, nerdio only=$nerdioOnlyCount, duplicate=$duplicateCount, compare unavailable=$compareUnavailableCount." -Level Info
    }

    $loadNerdioDefinitions = {
        $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$nerdioDefinitionsPathBox.Text)
        $nerdioDefinitionsPathBox.Text = $definitionsRoot
        & $applyNerdioDefinitionsPathToConfig

        if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
            $syncHash.NerdioDefinitionRows = @()
            & $refreshNerdioComparison
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: provide a definitions folder path first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $definitionsRoot -PathType Container)) {
            $syncHash.NerdioDefinitionRows = @()
            & $refreshNerdioComparison
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
            & $refreshNerdioComparison
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
                    DefinitionPath   = $definitionPath
                    Publisher        = $publisher
                    AppName          = $appName
                    DefinitionValid  = $definitionValid
                    SourceType       = $sourceType
                    SourceApp        = $sourceApp
                    SourceFilter     = $sourceFilter
                    DefinitionObject = $definitionObject
                })
        }

        $sortedRows = @($rows | Sort-Object -Property DefinitionPath, Publisher, AppName)
        $syncHash.NerdioDefinitionRows = $sortedRows
        & $refreshNerdioComparison

        $validCount = @($sortedRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count

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

                    $module = Get-Module -Name NerdioShellApps -ErrorAction SilentlyContinue
                    if ($null -ne $module -and $null -ne $module.SessionState -and $null -ne $module.SessionState.PSVariable) {
                        $module.SessionState.PSVariable.Set('InformationPreference', 'SilentlyContinue')
                    }

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
                        $nerdioShellAppsCountLabel.Text = '0 apps'
                        $errorMessage = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Error)) { 'Unknown error occurred while listing Shell Apps.' } else { [string]$result.Error }
                        Write-UILog -SyncHash $syncHash -Message "Nerdio: failed to list Shell Apps: $errorMessage" -Level Error
                    }
                    else {
                        $rows = @($result.Rows)
                        $syncHash.NerdioShellAppRows = $rows
                        $nerdioShellAppsCountLabel.Text = "$($rows.Count) apps"
                        Write-UILog -SyncHash $syncHash -Message "Nerdio: loaded $($rows.Count) Shell App(s) from Nerdio Manager." -Level Info
                    }

                    & $refreshNerdioComparison

                    if (-not [string]::IsNullOrWhiteSpace([string]$syncHash.PendingNerdioPostImportVerifyAppId)) {
                        $verifyAppId = [string]$syncHash.PendingNerdioPostImportVerifyAppId
                        $verifyAppName = [string]$syncHash.PendingNerdioPostImportVerifyAppName
                        $expectedEvergreenVersion = [string]$syncHash.PendingNerdioPostImportExpectedEvergreenVersion

                        $verifiedRow = @(
                            $syncHash.NerdioComparisonRows | Where-Object {
                                [string]$_.NerdioAppId -eq $verifyAppId -and [string]$_.HasDefinition -eq 'Yes'
                            } | Select-Object -First 1
                        )

                        if ($verifiedRow.Count -eq 0) {
                            $verifyMessage = "Post-import verification for '$verifyAppName' could not find a matching comparison row (Shell App ID: $verifyAppId)."
                            if ($null -ne $nerdioActionStatusLabel) {
                                $nerdioActionStatusLabel.Text = $verifyMessage
                            }
                            Write-UILog -SyncHash $syncHash -Message "Nerdio: $verifyMessage" -Level Warning
                        }
                        else {
                            $row = $verifiedRow[0]
                            $comparisonSummary = "Nerdio version $([string]$row.NerdioVersion) vs Evergreen $([string]$row.EvergreenVersion)"
                            if ([string]$row.IsMatched -eq 'Yes' -and [string]$row.UpdateNeeded -eq 'No') {
                                $verifyMessage = "Post-import verification passed for '$verifyAppName': status Matched. $comparisonSummary."
                                if ($null -ne $nerdioActionStatusLabel) {
                                    $nerdioActionStatusLabel.Text = $verifyMessage
                                }
                                Write-UILog -SyncHash $syncHash -Message "Nerdio: $verifyMessage" -Level Info
                            }
                            elseif ([string]$row.IsMatched -eq 'Yes' -and [string]$row.UpdateNeeded -eq 'Yes') {
                                $verifyMessage = "Post-import verification shows update still needed for '$verifyAppName'. $comparisonSummary."
                                if (-not [string]::IsNullOrWhiteSpace($expectedEvergreenVersion)) {
                                    $verifyMessage = "$verifyMessage Expected Evergreen at import time: $expectedEvergreenVersion."
                                }
                                if ($null -ne $nerdioActionStatusLabel) {
                                    $nerdioActionStatusLabel.Text = $verifyMessage
                                }
                                Write-UILog -SyncHash $syncHash -Message "Nerdio: $verifyMessage" -Level Warning
                            }
                            elseif ([string]$row.UpdateNeeded -eq 'Compare unavailable') {
                                $verifyMessage = "Post-import verification is inconclusive for '$verifyAppName': version comparison unavailable."
                                if ($null -ne $nerdioActionStatusLabel) {
                                    $nerdioActionStatusLabel.Text = $verifyMessage
                                }
                                Write-UILog -SyncHash $syncHash -Message "Nerdio: $verifyMessage" -Level Warning
                            }
                            else {
                                $verifyMessage = "Post-import verification could not confirm a matched state for '$verifyAppName' (status: $([string]$row.MatchStatus))."
                                if ($null -ne $nerdioActionStatusLabel) {
                                    $nerdioActionStatusLabel.Text = $verifyMessage
                                }
                                Write-UILog -SyncHash $syncHash -Message "Nerdio: $verifyMessage" -Level Warning
                            }
                        }

                        $syncHash.PendingNerdioPostImportVerifyAppId = ''
                        $syncHash.PendingNerdioPostImportVerifyAppName = ''
                        $syncHash.PendingNerdioPostImportExpectedEvergreenVersion = ''
                    }
                }
                finally {
                    & $setNerdioShellAppsLoadingState -IsLoading $false
                }
            })

        $pollTimer.Start()
    }

    $startNerdioAddVersion = {
        $selectedRow = $syncHash.NerdioSelectedComparisonRow
        if ($null -eq $selectedRow) {
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: no row selected for adding a version.' -Level Warning
            return
        }

        if ([string]$selectedRow.IsMatched -ne 'Yes' -or [string]$selectedRow.UpdateNeeded -ne 'Yes') {
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: selected row is not eligible for adding a version (matched app with update available required).' -Level Warning
            return
        }

        if ($syncHash.IsNerdioShellAppsLoading) {
            return
        }

        $modulePath = & $normalizeDirectoryPath -PathValue ([string]$nerdioModulePathSettingsBox.Text)
        if ([string]::IsNullOrWhiteSpace($modulePath) -or -not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: module path is not configured or does not exist.' -Level Error
            return
        }

        $shellAppId = [string]$selectedRow.NerdioAppId
        $definitionPath = [string]$selectedRow.DefinitionPath
        $appName = [string]$selectedRow.AppName

        if ([string]::IsNullOrWhiteSpace($shellAppId)) {
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: selected row does not have a Shell App ID.' -Level Error
            return
        }

        if ([string]::IsNullOrWhiteSpace($definitionPath) -or -not (Test-Path -LiteralPath $definitionPath -PathType Container)) {
            Write-UILog -SyncHash $syncHash -Message "Nerdio: definition path is missing or does not exist: $definitionPath" -Level Error
            return
        }

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

        & $setNerdioShellAppsLoadingState -IsLoading $true -Message "Adding new version to Shell App '$appName'..."
        Write-UILog -SyncHash $syncHash -Message "Nerdio: adding new version to Shell App '$appName' (id: $shellAppId)..." -Level Info

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string]$ModulePath,
                    [PSCustomObject]$NerdioAuthContext,
                    [string]$ShellAppId,
                    [string]$DefinitionPath
                )

                $result = [PSCustomObject]@{
                    Success = $false
                    Error   = ''
                }

                try {
                    Import-Module -Name $ModulePath -Force -ErrorAction Stop | Out-Null

                    $module = Get-Module -Name NerdioShellApps -ErrorAction SilentlyContinue
                    if ($null -ne $module -and $null -ne $module.SessionState -and $null -ne $module.SessionState.PSVariable) {
                        $module.SessionState.PSVariable.Set('InformationPreference', 'SilentlyContinue')
                    }

                    $setNmeCredentialsCommand = Get-Command -Name 'NerdioShellApps\Set-NmeCredentials'     -ErrorAction SilentlyContinue
                    $connectNmeCommand = Get-Command -Name 'NerdioShellApps\Connect-Nme'            -ErrorAction SilentlyContinue
                    $getShellAppDefCommand = Get-Command -Name 'NerdioShellApps\Get-ShellAppDefinition' -ErrorAction SilentlyContinue
                    $getAppMetadataCommand = Get-Command -Name 'NerdioShellApps\Get-AppMetadata'        -ErrorAction SilentlyContinue
                    $newShellAppVersionCommand = Get-Command -Name 'NerdioShellApps\New-ShellAppVersion'    -ErrorAction SilentlyContinue

                    if ($null -eq $setNmeCredentialsCommand) { throw 'Required command Set-NmeCredentials was not found in NerdioShellApps module.' }
                    if ($null -eq $connectNmeCommand) { throw 'Required command Connect-Nme was not found in NerdioShellApps module.' }
                    if ($null -eq $getShellAppDefCommand) { throw 'Required command Get-ShellAppDefinition was not found in NerdioShellApps module.' }
                    if ($null -eq $getAppMetadataCommand) { throw 'Required command Get-AppMetadata was not found in NerdioShellApps module.' }
                    if ($null -eq $newShellAppVersionCommand) { throw 'Required command New-ShellAppVersion was not found in NerdioShellApps module.' }

                    foreach ($required in @(
                            @{ Name = 'Tenant ID'; Value = [string]$NerdioAuthContext.TenantId },
                            @{ Name = 'NME Host'; Value = [string]$NerdioAuthContext.NmeHost },
                            @{ Name = 'Client ID'; Value = [string]$NerdioAuthContext.ClientId },
                            @{ Name = 'API Scope'; Value = [string]$NerdioAuthContext.ApiScope },
                            @{ Name = 'Client Secret'; Value = [string]$NerdioAuthContext.ClientSecret }
                        )) {
                        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                            throw "Nerdio API $($required.Name) is required to add a Shell App version."
                        }
                    }

                    & $setNmeCredentialsCommand `
                        -ClientId           ([string]$NerdioAuthContext.ClientId) `
                        -ClientSecret       ([string]$NerdioAuthContext.ClientSecret) `
                        -TenantId           ([string]$NerdioAuthContext.TenantId) `
                        -ApiScope           ([string]$NerdioAuthContext.ApiScope) `
                        -OAuthToken         ([string]$NerdioAuthContext.OAuthTokenUrl) `
                        -SubscriptionId     ([string]$NerdioAuthContext.SubscriptionId) `
                        -ResourceGroupName  ([string]$NerdioAuthContext.ResourceGroup) `
                        -StorageAccountName ([string]$NerdioAuthContext.StorageAccount) `
                        -ContainerName      ([string]$NerdioAuthContext.Container) `
                        -NmeHost            ([string]$NerdioAuthContext.NmeHost)

                    $null = & $connectNmeCommand -PassThru

                    $definition = & $getShellAppDefCommand -Path $DefinitionPath
                    if ($null -eq $definition) {
                        throw "Failed to load Shell App definition from: $DefinitionPath"
                    }

                    $appMetadata = $definition | & $getAppMetadataCommand
                    if ($null -eq $appMetadata) {
                        throw 'Failed to retrieve app metadata from the definition source.'
                    }

                    $null = & $newShellAppVersionCommand -Id $ShellAppId -AppMetadata $appMetadata

                    $result.Success = $true
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            }).AddArgument($modulePath).AddArgument($nerdioAuthContext).AddArgument($shellAppId).AddArgument($definitionPath)

        $syncHash.PendingNerdioAddVersionPS = $ps
        $syncHash.PendingNerdioAddVersionRunspace = $rs
        $syncHash.PendingNerdioAddVersionAsync = $ps.BeginInvoke()

        $syncHash.PendingNerdioAddVersionAppName = $appName

        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $syncHash.PendingNerdioAddVersionTimer = $pollTimer

        $pollTimer.add_Tick({
                if ($null -eq $syncHash.PendingNerdioAddVersionAsync -or -not $syncHash.PendingNerdioAddVersionAsync.IsCompleted) {
                    return
                }

                if ($null -ne $syncHash.PendingNerdioAddVersionTimer) {
                    $syncHash.PendingNerdioAddVersionTimer.Stop()
                    $syncHash.PendingNerdioAddVersionTimer = $null
                }

                $addVersionResult = $null
                try {
                    $output = $syncHash.PendingNerdioAddVersionPS.EndInvoke($syncHash.PendingNerdioAddVersionAsync)
                    if ($null -ne $output -and $output.Count -gt 0) {
                        $addVersionResult = $output[$output.Count - 1]
                    }
                }
                catch {
                    $addVersionResult = [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
                }
                finally {
                    try { $syncHash.PendingNerdioAddVersionPS.Dispose() } catch {}
                    try { $syncHash.PendingNerdioAddVersionRunspace.Dispose() } catch {}
                    $syncHash.PendingNerdioAddVersionPS = $null
                    $syncHash.PendingNerdioAddVersionRunspace = $null
                    $syncHash.PendingNerdioAddVersionAsync = $null
                }

                if ($null -eq $addVersionResult -or -not $addVersionResult.Success) {
                    $errMsg = if ($null -eq $addVersionResult -or [string]::IsNullOrWhiteSpace([string]$addVersionResult.Error)) {
                        'Unknown error occurred while adding Shell App version.'
                    }
                    else {
                        [string]$addVersionResult.Error
                    }
                    Write-UILog -SyncHash $syncHash -Message "Nerdio: failed to add Shell App version: $errMsg" -Level Error
                    & $setNerdioShellAppsLoadingState -IsLoading $false
                }
                else {
                    $completedAppName = [string]$syncHash.PendingNerdioAddVersionAppName
                    $syncHash.PendingNerdioAddVersionAppName = $null
                    Write-UILog -SyncHash $syncHash -Message "Nerdio: successfully added new version to Shell App '$completedAppName'." -Level Info
                    try {
                        $syncHash.PendingNerdioPostImportVerifyAppId = [string]$shellAppId
                        $syncHash.PendingNerdioPostImportVerifyAppName = [string]$completedAppName
                        $syncHash.PendingNerdioPostImportExpectedEvergreenVersion = [string]$selectedRow.EvergreenVersion
                        & $setNerdioShellAppsLoadingState -IsLoading $false
                        & $loadNerdioShellApps
                    }
                    catch {
                        Write-UILog -SyncHash $syncHash -Message "Nerdio: refresh after adding Shell App version failed: $($_.Exception.Message)" -Level Error
                        $syncHash.PendingNerdioPostImportVerifyAppId = ''
                        $syncHash.PendingNerdioPostImportVerifyAppName = ''
                        $syncHash.PendingNerdioPostImportExpectedEvergreenVersion = ''
                    }
                    finally {
                        if ($syncHash.IsNerdioShellAppsLoading) {
                            & $setNerdioShellAppsLoadingState -IsLoading $false
                        }
                    }
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
            $statusBrush = & $getThemeStatusBrush -ResourceKey 'StatusPositiveBrush' -FallbackBrush ([System.Windows.Media.Brushes]::LightGreen)
            $intuneSettingsModuleStatusLabel.Foreground = $statusBrush
            if ($null -ne $intuneSettingsModuleStatusDot) {
                $intuneSettingsModuleStatusDot.Fill = $statusBrush
            }
        }
        else {
            $statusBrush = & $getThemeStatusBrush -ResourceKey 'StatusErrorBrush' -FallbackBrush ([System.Windows.Media.Brushes]::OrangeRed)
            $intuneSettingsModuleStatusLabel.Foreground = $statusBrush
            if ($null -ne $intuneSettingsModuleStatusDot) {
                $intuneSettingsModuleStatusDot.Fill = $statusBrush
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
            $syncHash.AzureAuthState.IsAuthenticated = $true
            $syncHash.AzureAuthState.AccountId = [string]$r.AccountId
            $syncHash.AzureAuthState.TenantId = [string]$r.TenantId
            $syncHash.AzureAuthState.SubscriptionName = [string]$r.SubscriptionName
            $syncHash.AzureAuthState.ErrorMessage = ''

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

            $syncHash.Config.AzureAuthSettings.TenantId = [string]$syncHash.ImportTenantIdBox.Text
            $syncHash.Config.AzureAuthSettings.LastAccountId = [string]$r.AccountId
            $syncHash.Config.AzureAuthSettings.LastTenantId = [string]$r.TenantId
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
            $syncHash.AzureAuthState.IsAuthenticated = $false
            $syncHash.AzureAuthState.AccountId = ''
            $syncHash.AzureAuthState.TenantId = ''
            $syncHash.AzureAuthState.SubscriptionName = ''
            $syncHash.AzureAuthState.IntuneConnected = $false
            $syncHash.AzureAuthState.IntuneConnectError = ''
            $syncHash.AzureAuthState.ErrorMessage = if ($null -eq $r) { 'Unknown sign-in error.' } else { [string]$r.ErrorMessage }
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
        $resourceGroup = [string]$nmeResourceGroupCombo.SelectedItem
        $storageAccount = [string]$nmeStorageAccountCombo.SelectedItem
        $container = [string]$nmeContainerCombo.SelectedItem

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
            $syncHash.NerdioAzureAuthState.IsAuthenticated = $true
            $syncHash.NerdioAzureAuthState.AccountId = [string]$r.AccountId
            $syncHash.NerdioAzureAuthState.TenantId = [string]$r.TenantId
            $syncHash.NerdioAzureAuthState.SubscriptionName = [string]$r.SubscriptionName
            $syncHash.NerdioAzureAuthState.ErrorMessage = ''

            if (-not [string]::IsNullOrWhiteSpace([string]$r.TenantId)) {
                $nerdioTenantIdBox.Text = [string]$r.TenantId
            }

            $syncHash.Config.AzureAuthSettings.NerdioTenantId = [string]$nerdioTenantIdBox.Text
            $syncHash.Config.AzureAuthSettings.NerdioLastAccountId = [string]$r.AccountId
            $syncHash.Config.AzureAuthSettings.NerdioLastTenantId = [string]$r.TenantId
            $syncHash.Config.AzureAuthSettings.NerdioLastSignedInUtc = (Get-Date).ToUniversalTime().ToString('o')
            Set-UIConfig -Config $syncHash.Config

            Write-UILog -SyncHash $syncHash -Message "Nerdio Azure sign-in succeeded as $($r.AccountId) (subscription: $($r.SubscriptionName), tenant: $($r.TenantId))." -Level Info

            # Populate the Resource Group dropdown from the target subscription
            Write-UILog -SyncHash $syncHash -Message 'Loading resource groups...' -Level Info
            $nmeResourceGroupCombo.Items.Clear()
            $nmeStorageAccountCombo.Items.Clear()
            $nmeContainerCombo.Items.Clear()
            $nmeStorageAccountCombo.IsEnabled = $false
            $nmeContainerCombo.IsEnabled = $false

            $rgs = Get-NerdioAzureResourceGroups
            foreach ($rg in $rgs) { [void]$nmeResourceGroupCombo.Items.Add($rg) }
            $nmeResourceGroupCombo.IsEnabled = ($nmeResourceGroupCombo.Items.Count -gt 0)
            Write-UILog -SyncHash $syncHash -Message "$($nmeResourceGroupCombo.Items.Count) resource group(s) loaded." -Level Info

            # Restore saved storage selections (if they still exist in the subscription).
            $savedResourceGroup = [string]$syncHash.Config.NerdioSettings.NmeResourceGroup
            $savedStorageAccount = [string]$syncHash.Config.NerdioSettings.NmeStorageAccount
            $savedContainer = [string]$syncHash.Config.NerdioSettings.NmeContainer

            if (-not [string]::IsNullOrWhiteSpace($savedResourceGroup)) {
                $matchedResourceGroup = @($nmeResourceGroupCombo.Items | Where-Object { [string]$_ -eq $savedResourceGroup } | Select-Object -First 1)
                if ($matchedResourceGroup.Count -gt 0) {
                    $nmeResourceGroupCombo.SelectedItem = $matchedResourceGroup[0]
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($savedStorageAccount)) {
                $matchedStorageAccount = @($nmeStorageAccountCombo.Items | Where-Object { [string]$_ -eq $savedStorageAccount } | Select-Object -First 1)
                if ($matchedStorageAccount.Count -gt 0) {
                    $nmeStorageAccountCombo.SelectedItem = $matchedStorageAccount[0]
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($savedContainer)) {
                $matchedContainer = @($nmeContainerCombo.Items | Where-Object { [string]$_ -eq $savedContainer } | Select-Object -First 1)
                if ($matchedContainer.Count -gt 0) {
                    $nmeContainerCombo.SelectedItem = $matchedContainer[0]
                }
            }
        }
        else {
            $syncHash.NerdioAzureAuthState.IsAuthenticated = $false
            $syncHash.NerdioAzureAuthState.AccountId = ''
            $syncHash.NerdioAzureAuthState.TenantId = ''
            $syncHash.NerdioAzureAuthState.SubscriptionName = ''
            $syncHash.NerdioAzureAuthState.ErrorMessage = if ($null -eq $r) { 'Unknown sign-in error.' } else { [string]$r.ErrorMessage }
            Write-UILog -SyncHash $syncHash -Message "Nerdio Azure sign-in failed: $($syncHash.NerdioAzureAuthState.ErrorMessage)" -Level Error
        }

        $syncHash.NerdioAzureAuthState.IsAuthInProgress = $false
        & $refreshNerdioAzureAuthUi
    }

    $startNerdioAzureSignOut = {
        Invoke-NerdioAzureSignOut

        $syncHash.NerdioAzureAuthState.IsAuthenticated = $false
        $syncHash.NerdioAzureAuthState.IsAuthInProgress = $false
        $syncHash.NerdioAzureAuthState.AccountId = ''
        $syncHash.NerdioAzureAuthState.TenantId = ''
        $syncHash.NerdioAzureAuthState.SubscriptionName = ''
        $syncHash.NerdioAzureAuthState.ErrorMessage = ''

        # Clear and disable the storage dropdowns
        $nmeResourceGroupCombo.Items.Clear()
        $nmeStorageAccountCombo.Items.Clear()
        $nmeContainerCombo.Items.Clear()
        $nmeResourceGroupCombo.IsEnabled = $false
        $nmeStorageAccountCombo.IsEnabled = $false
        $nmeContainerCombo.IsEnabled = $false

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
        if ($null -ne $syncHash.DownloadProgressBar) {
            $syncHash.DownloadProgressBar.Visibility = [System.Windows.Visibility]::Visible
            $syncHash.DownloadProgressBar.IsIndeterminate = $true
        }

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
                    $doneCount = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
                    $failedCount = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
                    $totalCount = $syncHash.DownloadQueue.Count
                    $finalQueueText = "Queue: $totalCount items (Pending: $pendingCount, Done: $doneCount, Failed: $failedCount)"

                    $syncHash.Window.Dispatcher.Invoke([action] {
                            $syncHash.IsRunning = $false
                            & $updateDownloadAllButtonState
                            if ($null -ne $syncHash.DownloadProgressBar) {
                                $syncHash.DownloadProgressBar.IsIndeterminate = $false
                                $syncHash.DownloadProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
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

    $startUpdateEvergreen = {
        if ($syncHash.IsRunning) {
            Write-UILog -SyncHash $syncHash -Message 'Another operation is currently running.' -Level Warning
            return
        }

        $syncHash.IsRunning = $true
        if ($null -ne $syncHash.RunUpdateEvergreenButton) {
            $syncHash.RunUpdateEvergreenButton.IsEnabled = $false
        }
        if ($null -ne $syncHash.UpdateStatusLabel) {
            $syncHash.UpdateStatusLabel.Text = 'Running Update-Evergreen...'
        }

        $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
        $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
        $writeUpdateOutputPath = Join-Path -Path $privateRoot -ChildPath 'Write-UpdateOutput.ps1'

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string]$WriteUILogPath,
                    [string]$WriteUpdateOutputPath
                )

                . $WriteUILogPath
                . $WriteUpdateOutputPath

                try {
                    Import-Module Evergreen -ErrorAction Stop | Out-Null

                    Write-UpdateOutput -SyncHash $syncHash -Message 'Update-Evergreen' -Level Cmd
                    Write-UILog -SyncHash $syncHash -Message 'Update-Evergreen' -Level Cmd

                    Update-Evergreen *>&1 | ForEach-Object {
                        $record = $_
                        $lineLevel = 'Info'
                        $lineMessage = ''

                        if ($record -is [System.Management.Automation.ErrorRecord]) {
                            $lineLevel = 'Error'
                            $lineMessage = $record.ToString()
                        }
                        elseif ($record -is [System.Management.Automation.WarningRecord]) {
                            $lineLevel = 'Warning'
                            $lineMessage = [string]$record.Message
                        }
                        elseif ($record -is [System.Management.Automation.VerboseRecord]) {
                            $lineMessage = [string]$record.Message
                        }
                        elseif ($record -is [System.Management.Automation.DebugRecord]) {
                            $lineMessage = [string]$record.Message
                        }
                        elseif ($record -is [System.Management.Automation.InformationRecord]) {
                            $lineMessage = [string]$record.MessageData
                        }
                        elseif ($record -is [System.Management.Automation.ProgressRecord]) {
                            $lineMessage = "$([string]$record.Activity): $([string]$record.StatusDescription)"
                        }
                        else {
                            $lineMessage = [string]$record
                        }

                        if (-not [string]::IsNullOrWhiteSpace($lineMessage)) {
                            Write-UpdateOutput -SyncHash $syncHash -Message $lineMessage -Level $lineLevel
                            Write-UILog -SyncHash $syncHash -Message $lineMessage -Level $lineLevel
                        }
                    }

                    Write-UpdateOutput -SyncHash $syncHash -Message 'Update-Evergreen completed.' -Level Info
                    Write-UILog -SyncHash $syncHash -Message 'Update-Evergreen completed.' -Level Info
                }
                catch {
                    Write-UpdateOutput -SyncHash $syncHash -Message "Update-Evergreen failed: $_" -Level Error
                    Write-UILog -SyncHash $syncHash -Message "Update-Evergreen failed: $_" -Level Error
                }
                finally {
                    $syncHash.Window.Dispatcher.Invoke([action] {
                            $syncHash.IsRunning = $false
                            if ($null -ne $syncHash.RunUpdateEvergreenButton) {
                                $syncHash.RunUpdateEvergreenButton.IsEnabled = $true
                            }
                            if ($null -ne $syncHash.UpdateStatusLabel) {
                                $syncHash.UpdateStatusLabel.Text = 'Ready to run Update-Evergreen.'
                            }
                        }, 'Normal')
                }
            }).AddArgument($writeUILogPath).AddArgument($writeUpdateOutputPath)

        $async = $ps.BeginInvoke()
        & $registerBackgroundOperation -Name 'UpdateEvergreen' -PowerShellInstance $ps -RunspaceInstance $rs -AsyncResult $async
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

            $currentOutputPath = & $normalizeDirectoryPath -PathValue ([string]$syncHash.Config.OutputPath)
            if ([string]::IsNullOrWhiteSpace($currentOutputPath)) {
                $currentOutputPath = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'
                $syncHash.Config.OutputPath = $currentOutputPath
                Set-UIConfig -Config $syncHash.Config
            }
            if ($null -ne $outputPathBox) {
                $outputPathBox.Text = $currentOutputPath
            }

            & $refreshQueueView
            $libraryPathViewBox.Text = $syncHash.Config.LibraryPath
            $importTenantIdBox.Text = [string]$syncHash.Config.AzureAuthSettings.TenantId
            $nerdioTenantIdBox.Text = [string]$syncHash.Config.AzureAuthSettings.NerdioTenantId
            $nerdioModulePathSettingsBox.Text = [string]$syncHash.Config.NerdioSettings.ModulePath
            $nmeHostBox.Text = [string]$syncHash.Config.NerdioSettings.NmeHost
            $nmeClientIdBox.Text = [string]$syncHash.Config.NerdioSettings.NmeClientId
            $nmeApiScopeBox.Text = [string]$syncHash.Config.NerdioSettings.NmeApiScope
            $nmeOAuthTokenUrlBox.Text = [string]$syncHash.Config.NerdioSettings.NmeOAuthTokenUrl
            $nmeSubscriptionIdBox.Text = [string]$syncHash.Config.NerdioSettings.NmeSubscriptionId
            $nerdioDefinitionsPathBox.Text = [string]$syncHash.Config.NerdioSettings.DefinitionsPath
            $intuneDefinitionsPathBox.Text = [string]$syncHash.Config.IntuneSettings.DefinitionsPath
            $intunePackageOutputPathBox.Text = [string]$syncHash.Config.IntuneSettings.PackageOutputPath
            if ($null -ne $syncHash.Config.InstallSettings) {
                $installDefinitionsPathBox.Text = [string]$syncHash.Config.InstallSettings.DefinitionsPath
            }
            & $setInstallElevationState
            [void](& $loadNerdioShellAppsModule)
            [void](& $loadIntuneWin32AppModule)
            & $refreshImportAuthUi
            & $refreshNerdioApiAuthUi
            & $refreshNerdioAzureAuthUi
            & $setImportProvider -Provider $syncHash.Config.ImportSettings.CurrentProvider

            if ($null -eq $syncHash.Config.ShowImportTab) {
                $syncHash.Config.ShowImportTab = $false
            }
            if ($null -eq $syncHash.Config.ShowInstallTab) {
                $syncHash.Config.ShowInstallTab = [bool]$syncHash.Config.ShowImportTab
            }
            if ($null -ne $showImportTabCheckBox) {
                $showImportTabCheckBox.IsChecked = [bool]$syncHash.Config.ShowImportTab
            }
            if ($null -ne $showInstallTabCheckBox) {
                $showInstallTabCheckBox.IsChecked = [bool]$syncHash.Config.ShowInstallTab
            }
            & $setImportTabVisibility -ShowImport ([bool]$syncHash.Config.ShowImportTab) -ShowInstall ([bool]$syncHash.Config.ShowInstallTab)

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
                    if ([bool]$syncHash.Config.ShowImportTab) {
                        $navImport.IsChecked = $true
                    }
                    else {
                        $navApps.IsChecked = $true
                    }
                }
                'Install' {
                    if ([bool]$syncHash.Config.ShowInstallTab) {
                        $navInstall.IsChecked = $true
                    }
                    else {
                        $navApps.IsChecked = $true
                    }
                }
                'Settings' {
                    $navSettings.IsChecked = $true
                }
                'Update' {
                    $navUpdate.IsChecked = $true
                }
                'About' {
                    $navAbout.IsChecked = $true
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
                elseif ($navInstall.IsChecked) {
                    & $setInstallElevationState
                    & $refreshInstallRows
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
        NavInstall  = $installPanel
        NavSettings = $settingsPanel
        NavUpdate   = $updatePanel
        NavAbout    = $aboutPanel
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

    foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navImport, $navInstall, $navSettings, $navUpdate, $navAbout)) {
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

            # Auto-load local definitions only — do not query Intune or Nerdio Manager.
            # Skip if compare data is already populated: definitions are already visible in
            # the comparison view, and re-loading when IntuneWin32Rows / NerdioShellAppRows
            # are non-empty would cause refreshComparison to call external APIs for matched rows.
            $savedIntunePath = if ($null -ne $syncHash.Config.IntuneSettings) {
                [string]$syncHash.Config.IntuneSettings.DefinitionsPath
            }
            else {
                ''
            }
            if (-not [string]::IsNullOrWhiteSpace($savedIntunePath) -and
                (Test-Path -LiteralPath $savedIntunePath -PathType Container) -and
                $syncHash.IntuneWin32Rows.Count -eq 0) {
                & $loadIntuneDefinitions
            }

            $savedNerdioPath = if ($null -ne $syncHash.Config.NerdioSettings) {
                [string]$syncHash.Config.NerdioSettings.DefinitionsPath
            }
            else {
                ''
            }
            if (-not [string]::IsNullOrWhiteSpace($savedNerdioPath) -and
                (Test-Path -LiteralPath $savedNerdioPath -PathType Container) -and
                $syncHash.NerdioShellAppRows.Count -eq 0) {
                & $loadNerdioDefinitions
            }
        })

    $navInstall.add_Checked({
            & $setInstallElevationState
            $savedInstallPath = if ($null -ne $syncHash.Config.InstallSettings) {
                [string]$syncHash.Config.InstallSettings.DefinitionsPath
            }
            else {
                ''
            }
            if (-not [string]::IsNullOrWhiteSpace($savedInstallPath) -and
                (Test-Path -LiteralPath $savedInstallPath -PathType Container)) {
                & $loadInstallDefinitions
            }
            else {
                & $refreshInstallRows
            }
        })

    $navUpdate.add_Checked({
            if ($null -ne $syncHash.UpdateStatusLabel -and -not $syncHash.IsRunning) {
                $syncHash.UpdateStatusLabel.Text = 'Ready to run Update-Evergreen.'
            }
        })

    $importProviderTabControl.add_SelectionChanged({
            param($s, $e)
            if ($s -ne $importProviderTabControl) { return }
            # Index 2 is the shared Authentication tab - not a provider workflow, nothing to switch
            if ($importProviderTabControl.SelectedIndex -eq 2) { return }
            $provider = if ($importProviderTabControl.SelectedIndex -eq 0) { 'Intune' } else { 'Nerdio' }
            & $setImportProvider -Provider $provider -Persist
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

    # Enable/disable the Azure sign-in button based on whether Subscription ID is provided,
    # but only when not already signed in (sign-in is disabled while authenticated).
    $nmeSubscriptionIdBox.add_TextChanged({
            $notAuthenticated = -not [bool]$syncHash.NerdioAzureAuthState.IsAuthenticated
            $nerdioAzureSignInButton.IsEnabled = $notAuthenticated -and (-not [string]::IsNullOrWhiteSpace($nmeSubscriptionIdBox.Text))
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
            $nmeContainerCombo.IsEnabled = $false
            if ([string]::IsNullOrWhiteSpace($rg)) { return }

            $existingResourceGroup = [string]$syncHash.Config.NerdioSettings.NmeResourceGroup
            $syncHash.Config.NerdioSettings.NmeResourceGroup = $rg
            if ($rg -ne $existingResourceGroup) {
                $syncHash.Config.NerdioSettings.NmeStorageAccount = ''
                $syncHash.Config.NerdioSettings.NmeContainer = ''
            }
            Set-UIConfig -Config $syncHash.Config

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

            $existingStorageAccount = [string]$syncHash.Config.NerdioSettings.NmeStorageAccount
            $syncHash.Config.NerdioSettings.NmeResourceGroup = $rg
            $syncHash.Config.NerdioSettings.NmeStorageAccount = $sa
            if ($sa -ne $existingStorageAccount) {
                $syncHash.Config.NerdioSettings.NmeContainer = ''
            }
            Set-UIConfig -Config $syncHash.Config

            Write-UILog -SyncHash $syncHash -Message "Loading containers for '$sa'..." -Level Info
            $containers = Get-NerdioAzureStorageContainers -ResourceGroupName $rg -StorageAccountName $sa
            foreach ($c in $containers) { [void]$nmeContainerCombo.Items.Add($c) }
            $nmeContainerCombo.IsEnabled = ($nmeContainerCombo.Items.Count -gt 0)
            Write-UILog -SyncHash $syncHash -Message "$($nmeContainerCombo.Items.Count) container(s) loaded." -Level Info
        })

    $nmeContainerCombo.add_SelectionChanged({
            $rg = [string]$nmeResourceGroupCombo.SelectedItem
            $sa = [string]$nmeStorageAccountCombo.SelectedItem
            $container = [string]$nmeContainerCombo.SelectedItem
            if ([string]::IsNullOrWhiteSpace($rg) -or [string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($container)) { return }

            $syncHash.Config.NerdioSettings.NmeResourceGroup = $rg
            $syncHash.Config.NerdioSettings.NmeStorageAccount = $sa
            $syncHash.Config.NerdioSettings.NmeContainer = $container
            Set-UIConfig -Config $syncHash.Config
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
            if (-not (& $requireImportAuth -ActionName 'List Shell Apps and compare updates' -Provider 'Nerdio')) { return }
            & $loadNerdioShellApps
        })

    $nerdioDefinitionsListView.add_SelectionChanged({
            & $updateNerdioRowActionButtons
        })

    $nerdioAddVersionButton.add_Click({
            if (-not (& $requireImportAuth -ActionName 'Add Shell App version' -Provider 'Nerdio')) { return }
            & $startNerdioAddVersion
        })

    $nerdioImportNewButton.add_Click({
            if (-not (& $requireImportAuth -ActionName 'Import new Shell App' -Provider 'Nerdio')) { return }
            Write-UILog -SyncHash $syncHash -Message 'Nerdio: import as new Shell App is not implemented yet.' -Level Info
        })

    $intuneRefreshCatalogButton.add_Click({
            if (-not (& $requireImportAuth -ActionName 'List Intune Win32 apps')) { return }
            & $loadIntuneWin32Apps
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
            & $loadIntuneDefinitions
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

    $intuneWin32AppsListView.add_SelectionChanged({
            & $updateIntuneRowActionButtons
        })

    $intuneWin32AppsListView.AddHandler(
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
            if ([string]$syncHash.IntuneSortProperty -eq $sortProperty -and [string]$syncHash.IntuneSortDirection -eq 'Ascending') {
                $newDirection = 'Descending'
            }

            $syncHash.IntuneSortProperty = $sortProperty
            $syncHash.IntuneSortDirection = $newDirection

            & $applyIntuneListSort
        }
    )

    $intuneApplyImportButton.add_Click({
            if (-not (& $requireImportAuth -ActionName 'Intune apply import')) { return }
            & $startIntuneImportOperation
        })

    $intuneReloadModuleSettingsButton.add_Click({
            [void](& $loadIntuneWin32AppModule -Force)
        })

    $installBrowseDefinitionsButton.add_Click({
            $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
            $dlg.Description = 'Select package definitions folder for local install'
            if (-not [string]::IsNullOrWhiteSpace($installDefinitionsPathBox.Text)) {
                $dlg.SelectedPath = $installDefinitionsPathBox.Text
            }

            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
                $installDefinitionsPathBox.Text = $normalised
                & $applyInstallPathsToConfig
            }
        })

    $installLoadDefinitionsButton.add_Click({
            & $loadInstallDefinitions
        })

    $installDefinitionsPathBox.add_LostFocus({
            $normalised = & $normalizeDirectoryPath -PathValue $installDefinitionsPathBox.Text
            $installDefinitionsPathBox.Text = $normalised
            & $applyInstallPathsToConfig
        })

    $installResolveLatestButton.add_Click({
            & $resolveInstallLatestVersions
        })

    $installPackagesListView.add_SelectionChanged({
            & $updateInstallRowActionButtons
        })

    $installPackagesListView.AddHandler(
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
            if ([string]$syncHash.InstallSortProperty -eq $sortProperty -and [string]$syncHash.InstallSortDirection -eq 'Ascending') {
                $newDirection = 'Descending'
            }

            $syncHash.InstallSortProperty = $sortProperty
            $syncHash.InstallSortDirection = $newDirection

            & $applyInstallListSort
        }
    )

    $installApplyButton.add_Click({
            & $startInstallSelectedOperation
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
            $syncHash.PendingLoadAsync = $null
            $syncHash.PendingLoadAppName = $null

            $syncHash.CurrentAppResults = @()
            $syncHash.VersionsListView.ItemsSource = @()
            $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
            $filterWrapPanel.Children.Clear()
            $syncHash.FilterState = @{}

            $selectedApp = $appsComboBox.SelectedItem
            if ($null -ne $selectedApp) {
                $appDetailTitle.Text = "$($selectedApp.Name)"

                # Load from cache if available; otherwise show the panel empty (user clicks Refresh)
                $cachePath = & $getAppCacheFile -AppName $selectedApp.Name
                if (Test-Path -LiteralPath $cachePath) {
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
                    $appDetailEmpty.Visibility = [System.Windows.Visibility]::Collapsed
                    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
                }
            }
            else {
                $appDetailEmpty.Visibility = [System.Windows.Visibility]::Visible
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
                    $_.AppName -eq $queueItem.AppName -and
                    $_.Version -eq $queueItem.Version -and
                    $_.Architecture -eq $queueItem.Architecture -and
                    $_.Channel -eq $queueItem.Channel -and
                    $_.Platform -eq $queueItem.Platform
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

    if ($null -ne $syncHash.RunUpdateEvergreenButton) {
        $syncHash.RunUpdateEvergreenButton.add_Click({
                & $startUpdateEvergreen
            })
    }

    if ($null -ne $clearUpdateOutputButton) {
        $clearUpdateOutputButton.add_Click({
                if ($null -ne $syncHash.UpdateOutputTextBox) {
                    $syncHash.UpdateOutputTextBox.Clear()
                }
            })
    }

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

            if (($selected -eq 'Import' -and -not [bool]$syncHash.Config.ShowImportTab) -or ($selected -eq 'Install' -and -not [bool]$syncHash.Config.ShowInstallTab)) {
                $selected = 'Apps'
                $startupViewComboBox.SelectedIndex = 0
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

            $themeComboBox.SelectedIndex = if ([string]$syncHash.Config.Theme -eq 'Dark') { 1 } else { 0 }
            if ($null -ne $showImportTabCheckBox) {
                $showImportTabCheckBox.IsChecked = [bool]$syncHash.Config.ShowImportTab
            }
            if ($null -ne $showInstallTabCheckBox) {
                $showInstallTabCheckBox.IsChecked = [bool]$syncHash.Config.ShowInstallTab
            }
            & $setImportTabVisibility -ShowImport ([bool]$syncHash.Config.ShowImportTab) -ShowInstall ([bool]$syncHash.Config.ShowInstallTab)

            switch ([string]$syncHash.Config.StartupView) {
                'Download' { $startupViewComboBox.SelectedIndex = 1 }
                'Library' { $startupViewComboBox.SelectedIndex = 2 }
                'Import' { $startupViewComboBox.SelectedIndex = 3 }
                'Install' { $startupViewComboBox.SelectedIndex = 4 }
                'Settings' { $startupViewComboBox.SelectedIndex = 5 }
                'Update' { $startupViewComboBox.SelectedIndex = 6 }
                'About' { $startupViewComboBox.SelectedIndex = 7 }
                default { $startupViewComboBox.SelectedIndex = 0 }
            }
        })

    if ($null -ne $showImportTabCheckBox) {
        $showImportTabCheckBox.add_Click({
                $showImport = [bool]$showImportTabCheckBox.IsChecked
                $syncHash.Config.ShowImportTab = $showImport
                & $setImportTabVisibility -ShowImport $showImport -ShowInstall ([bool]$syncHash.Config.ShowInstallTab)
                Set-UIConfig -Config $syncHash.Config
            })
    }

    if ($null -ne $showInstallTabCheckBox) {
        $showInstallTabCheckBox.add_Click({
                $showInstall = [bool]$showInstallTabCheckBox.IsChecked
                $syncHash.Config.ShowInstallTab = $showInstall
                & $setImportTabVisibility -ShowImport ([bool]$syncHash.Config.ShowImportTab) -ShowInstall $showInstall
                Set-UIConfig -Config $syncHash.Config
            })
    }

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
                & $updateDownloadAllButtonState
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
            & $updateDownloadAllButtonState
        })

    $nerdioModulePathSettingsBox.add_LostFocus({
            [void](& $loadNerdioShellAppsModule)
        })

    # Show window (blocking)
    [void]$window.ShowDialog()
}
