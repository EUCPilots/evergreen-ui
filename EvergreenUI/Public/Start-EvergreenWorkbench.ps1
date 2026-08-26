#Requires -Version 5.1
<#
.EXTERNALHELP EvergreenUI-help.xml
#>
function Start-EvergreenWorkbench {
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'Low')]
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

    # try {
    #     [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
    #     Write-Verbose -Message 'EvergreenUI: WPF render mode forced to SoftwareOnly to avoid render-target quota failures.'
    # }
    # catch {
    #     # best-effort - if this fails, continue with WPF defaults
    #     Write-Verbose -Message "EvergreenUI: Unable to set WPF render mode. $_"
    # }

    $nerdioBundledModulePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Resources\NerdioShellApps.psm1'

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
        RequiredModules   = $null
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

        $prerequisiteStatus = Get-EvergreenUIPrerequisiteStatus -ManifestPath $moduleManifestPath
        $moduleMetadata.RequiredModules = @($prerequisiteStatus.Required + $prerequisiteStatus.Optional | ForEach-Object {
                [PSCustomObject]@{
                    Name             = $_.Name
                    InstalledVersion = if ($null -eq $_.InstalledVersion) { 'Not installed' } else { $_.InstalledVersion }
                    Feature          = $_.Feature
                    Satisfied        = $_.Satisfied
                }
            })
    }
    catch {
        # About panel metadata is best-effort only.
        Write-Verbose -Message "EvergreenUI: $_"
    }

    # Shared state
    $syncHash = [hashtable]::Synchronized(@{
            Window                                          = $null
            LogTextBox                                      = $null
            LogScrollViewer                                 = $null
            LogFilePath                                     = ''
            IsClosing                                       = $false
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
            LibraryUpdateProgressBar                        = $null
            UpdateOutputTextBox                             = $null
            UpdateOutputScrollViewer                        = $null
            RunUpdateEvergreenButton                        = $null
            UpdateStatusLabel                               = $null
            LibraryData                                     = @()
            ActiveBackgroundOperations                      = [hashtable]::Synchronized(@{})
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
            IntuneCompareHasRun                             = $false
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
            VersionsSortProperty                            = ''
            VersionsSortDirection                           = 'Ascending'
            VersionsColSavedWidths                          = @{}
            DownloadQueueSortProperty                       = ''
            DownloadQueueSortDirection                      = 'Ascending'
            LibraryContentsSortProperty                     = ''
            LibraryContentsSortDirection                    = 'Ascending'
            LibraryDetailsSortProperty                      = ''
            LibraryDetailsSortDirection                     = 'Ascending'
            NerdioSortProperty                              = ''
            NerdioSortDirection                             = 'Ascending'
            NerdioActionButtonStates                         = @{}
            M365SortProperty                                = ''
            M365SortDirection                               = 'Ascending'
            PendingNerdioShellAppsTimer                     = $null
            PendingNerdioShellAppsPS                        = $null
            PendingNerdioShellAppsRunspace                  = $null
            PendingNerdioShellAppsAsync                     = $null
            IsNerdioShellAppsLoading                        = $false
            PendingNerdioAddVersionTimer                    = $null
            PendingNerdioAddVersionPS                       = $null
            PendingNerdioAddVersionRunspace                 = $null
            PendingNerdioAddVersionAsync                    = $null
            PendingNerdioPruneVersionsTimer                 = $null
            PendingNerdioPruneVersionsPS                    = $null
            PendingNerdioPruneVersionsRunspace              = $null
            PendingNerdioPruneVersionsAsync                 = $null
            PendingNerdioPruneVersionsAppName               = ''
            PendingNerdioImportNewTimer                     = $null
            PendingNerdioImportNewPS                        = $null
            PendingNerdioImportNewRunspace                  = $null
            PendingNerdioImportNewAsync                     = $null
            PendingNerdioImportNewAppName                   = ''
            PendingNerdioPostImportVerifyAppId              = ''
            PendingNerdioPostImportVerifyAppName            = ''
            PendingNerdioPostImportExpectedEvergreenVersion = ''
            NerdioDefinitionRows                            = @()
            NerdioShellAppRows                              = @()
            NerdioCompareHasRun                             = $false
            NerdioComparisonRows                            = @()
            NerdioSelectedComparisonRow                     = $null
            IsM365ImportLoading                             = $false
            PendingM365ImportTimer                          = $null
            PendingM365ImportPS                             = $null
            PendingM365ImportRunspace                       = $null
            PendingM365ImportAsync                          = $null
            IsM365EvergreenLoading                          = $false
            PendingM365EvergreenTimer                       = $null
            PendingM365EvergreenPS                          = $null
            PendingM365EvergreenRunspace                    = $null
            PendingM365EvergreenAsync                       = $null
            M365ConfigRows                                  = @()
            M365EvergreenRows                               = @()
            ImportCurrentProvider                           = [string]$config.ImportSettings.CurrentProvider
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
            EvergreenModuleLoaded                           = $false
            MgGraphModuleLoaded                             = $false
            IntuneWin32AppLoaded                            = $false
            AzModulesLoaded                                 = $false
            NerdioShellAppsLoaded                           = $false
            ImportModulesInitialized                        = $false
        })

    # Initialize feature-scoped state containers for gradual refactoring
    Initialize-FeatureScopedState -SyncHash $syncHash

    # Load XAML layout
    $xamlPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -ChildPath "Resources") -ChildPath "EvergreenUI.xaml"
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead((Resolve-Path -Path $xamlPath).Path)
        $window = [System.Windows.Markup.XamlReader]::Load($stream)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    # Set window/taskbar icon from bundled resource when available.
    $iconPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Resources\evergreenbulb.png'
    if (Test-Path -Path $iconPath) {
        try {
            $iconUri = [System.Uri]::new((Resolve-Path -Path $iconPath).Path)
            $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new($iconUri)
        }
        catch {
            # Ignore icon load failures and continue startup.
            Write-Verbose -Message "EvergreenUI: $_"
        }
    }

    # Resolve named controls
    $syncHash.Window = $window
    $syncHash.LogTextBox = $window.FindName('LogTextBox')
    $syncHash.LogScrollViewer = $window.FindName('LogScrollViewer')

    $criticalControlNames = @(
        'RootGrid', 'ThemeComboBox', 'NavToggleButton', 'NavApps', 'NavDownload',
        'NavLibrary', 'NavPackages', 'NavImport', 'NavInstall', 'NavSettings',
        'NavUpdate', 'NavAbout', 'AppsPanel', 'DownloadPanel', 'LibraryPanel',
        'PackagesPanel', 'ImportPanel', 'InstallPanel', 'SettingsPanel',
        'UpdatePanel', 'AboutPanel', 'LogTextBox', 'LogScrollViewer'
    )
    $missingControls = @($criticalControlNames | Where-Object { $null -eq $window.FindName($_) })
    if ($missingControls.Count -gt 0) {
        $missingNames = $missingControls -join ', '
        throw "EvergreenUI XAML is missing required named control(s): $missingNames"
    }

    $rootGrid = $window.FindName('RootGrid')
    $evergreenVersionText = $window.FindName('EvergreenVersionText')
    $evergreenStatusDot = $window.FindName('EvergreenStatusDot')
    $themeComboBox = $window.FindName('ThemeComboBox')

    $navToggleButton = $window.FindName('NavToggleButton')
    $navApps = $window.FindName('NavApps')
    $navDownload = $window.FindName('NavDownload')
    $navLibrary = $window.FindName('NavLibrary')
    $navPackages = $window.FindName('NavPackages')
    $navImport = $window.FindName('NavImport')
    $navInstall = $window.FindName('NavInstall')
    $navSettings = $window.FindName('NavSettings')
    $navUpdate = $window.FindName('NavUpdate')
    $navAbout = $window.FindName('NavAbout')

    $appsPanel = $window.FindName('AppsPanel')
    $downloadPanel = $window.FindName('DownloadPanel')
    $libraryPanel = $window.FindName('LibraryPanel')
    $packagesPanel = $window.FindName('PackagesPanel')
    $importPanel = $window.FindName('ImportPanel')
    $installPanel = $window.FindName('InstallPanel')
    $settingsPanel = $window.FindName('SettingsPanel')
    $updatePanel = $window.FindName('UpdatePanel')
    $aboutPanel = $window.FindName('AboutPanel')

    $refreshAppsButton = $window.FindName('RefreshAppsButton')
    $appSearchBox = $window.FindName('AppSearchBox')
    $appsListBox = $window.FindName('AppsListBox')
    $loadAppVersionsButton = $window.FindName('LoadAppVersionsButton')
    $filterWrapPanel = $window.FindName('FilterWrapPanel')
    $clearFiltersButton = $window.FindName('ClearFiltersButton')
    $exportCsvButton = $window.FindName('ExportCsvButton')
    $addToLibraryButton = $window.FindName('AddToLibraryButton')
    $appsActionStatusLabel = $window.FindName('AppsActionStatusLabel')
    $addToQueueButton = $window.FindName('AddToQueueButton')

    $removeQueueItemButton = $window.FindName('RemoveQueueItemButton')
    $clearQueueButton = $window.FindName('ClearQueueButton')
    $openDownloadFolderButton = $window.FindName('OpenDownloadFolderButton')

    $libraryPathViewBox = $window.FindName('LibraryPathViewBox')
    $browseLibraryButton = $window.FindName('BrowseLibraryButton')
    $libraryNewButton = $window.FindName('LibraryNewButton')
    $libraryRefreshButton = $window.FindName('LibraryRefreshButton')
    $libraryOpenFolderButton = $window.FindName('LibraryOpenFolderButton')

    $syncHash.LibraryContentsListView = $window.FindName('LibraryContentsListView')
    $syncHash.LibraryDetailsListView = $window.FindName('LibraryDetailsListView')
    $syncHash.LibraryStatusLabel = $window.FindName('LibraryStatusLabel')
    $syncHash.LibraryUpdateButton = $window.FindName('LibraryUpdateButton')
    $syncHash.LibraryUpdateProgressBar = $window.FindName('LibraryUpdateProgressBar')
    $syncHash.RunUpdateEvergreenButton = $window.FindName('RunUpdateEvergreenButton')
    $syncHash.UpdateOutputTextBox = $window.FindName('UpdateOutputTextBox')
    $syncHash.UpdateOutputScrollViewer = $window.FindName('UpdateOutputScrollViewer')
    $syncHash.UpdateStatusLabel = $window.FindName('UpdateStatusLabel')

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
    $syncHash.AppLastRefreshedLabel = $window.FindName('AppLastRefreshedLabel')

    $copyLogButton = $window.FindName('CopyLogButton')
    $saveLogButton = $window.FindName('SaveLogButton')
    $logToggleButton = $window.FindName('LogToggleButton')

    $outputPathBox = $window.FindName('OutputPathBox')
    $evergreenAppsPathBox = $window.FindName('EvergreenAppsPathBox')
    $showImportTabToggle = $window.FindName('ShowImportTabToggle')
    $showInstallTabToggle = $window.FindName('ShowInstallTabToggle')
    $browseOutputButton = $window.FindName('BrowseOutputButton')
    $openEvergreenAppsFolderButton = $window.FindName('OpenEvergreenAppsFolderButton')
    $clearCacheButton = $window.FindName('ClearCacheButton')
    $openCacheFolderButton = $window.FindName('OpenCacheFolderButton')
    $openLogsFolderButton = $window.FindName('OpenLogsFolderButton')
    $clearLogsButton = $window.FindName('ClearLogsButton')
    $aboutNameValue = $window.FindName('AboutNameValue')
    $aboutVersionValue = $window.FindName('AboutVersionValue')
    $aboutPrereleaseValue = $window.FindName('AboutPrereleaseValue')
    $aboutAuthorValue = $window.FindName('AboutAuthorValue')
    $aboutCompanyValue = $window.FindName('AboutCompanyValue')
    $aboutCopyrightValue = $window.FindName('AboutCopyrightValue')
    $aboutLicenseValue = $window.FindName('AboutLicenseValue')
    $aboutProjectUriValue = $window.FindName('AboutProjectUriValue')
    $aboutDescriptionValue = $window.FindName('AboutDescriptionValue')
    $aboutRequiredModulesList = $window.FindName('AboutRequiredModulesList')

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
    $browseIntuneDefinitionsButton = $window.FindName('BrowseIntuneDefinitionsButton')
    $intuneLoadDefinitionsButton = $window.FindName('IntuneLoadDefinitionsButton')
    $intuneUpdateDefinitionsButton = $window.FindName('IntuneUpdateDefinitionsButton')
    $intuneDefinitionsCountLabel = $window.FindName('IntuneDefinitionsCountLabel')
    $intuneWin32AppsCountLabel = $window.FindName('IntuneWin32AppsCountLabel')
    $intuneConnectionStatusDot = $window.FindName('IntuneConnectionStatusDot')
    $intuneConnectionStatusLabel = $window.FindName('IntuneConnectionStatusLabel')
    $intuneWin32AppsListView = $window.FindName('IntuneWin32AppsListView')
    $intuneActionStatusLabel = $window.FindName('IntuneActionStatusLabel')
    $intuneDefinitionsLoadingPanel = $window.FindName('IntuneDefinitionsLoadingPanel')
    $intuneDefinitionsLoadingLabel = $window.FindName('IntuneDefinitionsLoadingLabel')
    $intuneDefinitionsProgressBar = $window.FindName('IntuneDefinitionsProgressBar')
    $intuneImportLoadingPanel = $window.FindName('IntuneImportLoadingPanel')
    $intuneImportLoadingLabel = $window.FindName('IntuneImportLoadingLabel')
    $intuneImportProgressBar = $window.FindName('IntuneImportProgressBar')
    # Local Install controls
    $installLoadDefinitionsButton = $window.FindName('InstallLoadDefinitionsButton')
    $installResolveLatestButton = $window.FindName('InstallResolveLatestButton')
    $installHideIncompatibleArchitectureToggle = $window.FindName('InstallHideIncompatibleArchitectureToggle')
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
    $browseNerdioDefinitionsButton = $window.FindName('BrowseNerdioDefinitionsButton')
    $nerdioLoadConfigsButton = $window.FindName('NerdioLoadConfigsButton')
    $nerdioLoadDefinitionsButton = $window.FindName('NerdioLoadDefinitionsButton')
    $nerdioListShellAppsButton = $window.FindName('NerdioListShellAppsButton')
    $nerdioDefinitionsListView = $window.FindName('NerdioDefinitionsListView')
    $nerdioDefinitionsCountLabel = $window.FindName('NerdioDefinitionsCountLabel')
    $nerdioPackagesDefinitionsCountLabel = $window.FindName('NerdioPackagesDefinitionsCountLabel')
    $nerdioShellAppsCountLabel = $window.FindName('NerdioShellAppsCountLabel')
    $nerdioShellAppsLoadingPanel = $window.FindName('NerdioShellAppsLoadingPanel')
    $nerdioShellAppsLoadingLabel = $window.FindName('NerdioShellAppsLoadingLabel')
    $nerdioShellAppsProgressBar = $window.FindName('NerdioShellAppsProgressBar')
    $nerdioAddVersionButton = $window.FindName('NerdioAddVersionButton')
    $nerdioPruneVersionsButton = $window.FindName('NerdioPruneVersionsButton')
    $nerdioImportNewButton = $window.FindName('NerdioImportNewButton')
    $nerdioActionStatusLabel = $window.FindName('NerdioActionStatusLabel')
    $nerdioImportAuthStatusDot = $window.FindName('NerdioImportAuthStatusDot')
    $nerdioImportAuthStatusLabel = $window.FindName('NerdioImportAuthStatusLabel')
    $nerdioAzureAuthStatusDot = $window.FindName('NerdioAzureAuthStatusDot')
    $nerdioAzureAuthStatusLabel = $window.FindName('NerdioAzureAuthStatusLabel')
    $nerdioAzureSignInButton = $window.FindName('NerdioAzureSignInButton')
    $nerdioAzureSignOutButton = $window.FindName('NerdioAzureSignOutButton')
    $intuneApplyImportButton = $window.FindName('IntuneApplyImportButton')
    $intuneApplyUpdateImportButton = $window.FindName('IntuneApplyUpdateImportButton')
    # Microsoft 365 Apps controls
    $m365ConfigPathBox = $window.FindName('M365ConfigPathBox')
    $browseM365ConfigButton = $window.FindName('BrowseM365ConfigButton')
    $m365LoadConfigsButton = $window.FindName('M365LoadConfigsButton')
    $m365ChannelCombo = $window.FindName('M365ChannelCombo')
    $m365CompanyNameBox = $window.FindName('M365CompanyNameBox')
    $m365ImportForCombo = $window.FindName('M365ImportForCombo')
    $m365ConfigsCountLabel = $window.FindName('M365ConfigsCountLabel')
    $m365PackagesConfigsCountLabel = $window.FindName('M365PackagesConfigsCountLabel')
    $m365EvergreenVersionLabel = $window.FindName('M365EvergreenVersionLabel')
    $m365IntuneAuthStatusDot = $window.FindName('M365IntuneAuthStatusDot')
    $m365IntuneAuthStatusLabel = $window.FindName('M365IntuneAuthStatusLabel')
    $m365NerdioAuthStatusDot = $window.FindName('M365NerdioAuthStatusDot')
    $m365NerdioAuthStatusLabel = $window.FindName('M365NerdioAuthStatusLabel')
    $m365ConfigsLoadingPanel = $window.FindName('M365ConfigsLoadingPanel')
    $m365ConfigsLoadingLabel = $window.FindName('M365ConfigsLoadingLabel')
    $m365ConfigsProgressBar = $window.FindName('M365ConfigsProgressBar')
    $m365ConfigsListView = $window.FindName('M365ConfigsListView')
    $m365ImportIntuneButton = $window.FindName('M365ImportIntuneButton')
    $m365ImportNerdioButton = $window.FindName('M365ImportNerdioButton')
    $m365ActionStatusLabel = $window.FindName('M365ActionStatusLabel')
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
    $syncHash.M365ConfigsLoadingPanel = $m365ConfigsLoadingPanel
    $syncHash.M365ConfigsLoadingLabel = $m365ConfigsLoadingLabel
    $syncHash.M365ActionStatusLabel = $m365ActionStatusLabel
    $syncHash.M365EvergreenVersionLabel = $m365EvergreenVersionLabel
    $syncHash.M365ConfigsListView = $m365ConfigsListView

    $aboutNameValue.Text = [string]$moduleMetadata.Name
    $aboutVersionValue.Text = [string]$moduleMetadata.Version
    $aboutPrereleaseValue.Text = if ([string]::IsNullOrWhiteSpace([string]$moduleMetadata.Prerelease)) { 'No' } else { [string]$moduleMetadata.Prerelease }
    $aboutAuthorValue.Text = [string]$moduleMetadata.Author
    $aboutCompanyValue.Text = [string]$moduleMetadata.CompanyName
    $aboutCopyrightValue.Text = [string]$moduleMetadata.Copyright
    $aboutLicenseValue.Text = [string]$moduleMetadata.License
    $aboutProjectUriValue.Text = [string]$moduleMetadata.ProjectUri
    $aboutDescriptionValue.Text = [string]$moduleMetadata.Description
    if ($null -ne $moduleMetadata.RequiredModules -and $moduleMetadata.RequiredModules.Count -gt 0) {
        $aboutRequiredModulesList.ItemsSource = $moduleMetadata.RequiredModules
    }

    $setNerdioShellAppsLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsNerdioShellAppsLoading = $IsLoading

        Set-LoadingState -ButtonStates $syncHash.NerdioActionButtonStates -IsLoading $IsLoading `
            -Buttons $nerdioListShellAppsButton -LoadingControls @($nerdioShellAppsLoadingPanel, $nerdioShellAppsProgressBar) `
            -LoadingLabel $nerdioShellAppsLoadingLabel -LoadingMessage $Message `
            -IdleLoadingMessage 'Loading Shell Apps from Nerdio Manager...'

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
        $canPruneVersions = $false

        if ($null -ne $selectedRow) {
            $hasDefinition = ([string]$selectedRow.HasDefinition -eq 'Yes')
            $isMatched = ([string]$selectedRow.IsMatched -eq 'Yes')
            $isNewApp = ([string]$selectedRow.IsNewApp -eq 'Yes')
            $updateNeeded = ([string]$selectedRow.UpdateNeeded -eq 'Yes')
            $hasShellAppId = -not [string]::IsNullOrWhiteSpace([string]$selectedRow.NerdioAppId)

            $canImportNew = $hasDefinition -and $isNewApp `
                -and ([bool]$syncHash.IntuneWin32AppLoaded) `
                -and ([bool]$syncHash.AzModulesLoaded)
            $canAddVersion = $isMatched -and $updateNeeded `
                -and ([bool]$syncHash.IntuneWin32AppLoaded) `
                -and ([bool]$syncHash.AzModulesLoaded)
            $canPruneVersions = $hasShellAppId -and ([bool]$syncHash.NerdioShellAppsLoaded)
        }

        if ($null -ne $nerdioImportNewButton) {
            $nerdioImportNewButton.IsEnabled = (-not $syncHash.IsNerdioShellAppsLoading) -and $canImportNew
        }

        if ($null -ne $nerdioAddVersionButton) {
            $nerdioAddVersionButton.IsEnabled = (-not $syncHash.IsNerdioShellAppsLoading) -and $canAddVersion
        }

        if ($null -ne $nerdioPruneVersionsButton) {
            $nerdioPruneVersionsButton.IsEnabled = (-not $syncHash.IsNerdioShellAppsLoading) -and $canPruneVersions
        }
    }

    $updateIntuneRowActionButtons = {
        $selectedItems = if ($null -eq $intuneWin32AppsListView) { @() } else { @($intuneWin32AppsListView.SelectedItems) }

        $actionableItems = @($selectedItems | Where-Object {
                [string]$_.ImportAction -eq 'Import new app' -or [string]$_.ImportAction -eq 'Import new version and supersede'
            })

        $hasCustomRequirementRuleInSelection = @($actionableItems | Where-Object { [bool]$_.HasCustomRequirementRule }).Count -gt 0

        $canImport = ($actionableItems.Count -gt 0) `
            -and (-not $syncHash.IsIntuneImportLoading) `
            -and ([bool]$syncHash.IntuneWin32AppLoaded) `
            -and ([bool]$syncHash.MgGraphModuleLoaded) `
            -and (-not $hasCustomRequirementRuleInSelection)

        if ($null -ne $intuneApplyImportButton) {
            $intuneApplyImportButton.IsEnabled = $canImport
            $intuneApplyImportButton.Content = if ($actionableItems.Count -gt 1) {
                "Import $($actionableItems.Count) Win32 apps"
            }
            else {
                'Import Win32 app'
            }
        }

        $canImportUpdate = ($actionableItems.Count -gt 0) `
            -and (-not $syncHash.IsIntuneImportLoading) `
            -and ([bool]$syncHash.IntuneWin32AppLoaded) `
            -and ([bool]$syncHash.MgGraphModuleLoaded)

        if ($null -ne $intuneApplyUpdateImportButton) {
            $intuneApplyUpdateImportButton.IsEnabled = $canImportUpdate
            $intuneApplyUpdateImportButton.Content = if ($actionableItems.Count -gt 1) {
                "Import $($actionableItems.Count) Win32 updates"
            }
            else {
                'Import Win32 update'
            }
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
                'Workbench is running elevated'
            }
            else {
                'Not elevated - installers may prompt for UAC'
            }
        }
    }

    $applyIntuneListSort = {
        [void](Set-ListViewSort -ListView $intuneWin32AppsListView -Property ([string]$syncHash.IntuneSortProperty) -Direction ([string]$syncHash.IntuneSortDirection))
    }

    $applyInstallListSort = {
        [void](Set-ListViewSort -ListView $installPackagesListView -Property ([string]$syncHash.InstallSortProperty) -Direction ([string]$syncHash.InstallSortDirection))
    }

    $applyVersionsListSort = {
        [void](Set-ListViewSort -ListView $syncHash.VersionsListView -Property ([string]$syncHash.VersionsSortProperty) -Direction ([string]$syncHash.VersionsSortDirection))
    }

    $applyDownloadQueueSort = {
        [void](Set-ListViewSort -ListView $syncHash.DownloadQueueListView -Property ([string]$syncHash.DownloadQueueSortProperty) -Direction ([string]$syncHash.DownloadQueueSortDirection))
    }

    $applyLibraryContentsSort = {
        [void](Set-ListViewSort -ListView $syncHash.LibraryContentsListView -Property ([string]$syncHash.LibraryContentsSortProperty) -Direction ([string]$syncHash.LibraryContentsSortDirection))
    }

    $applyLibraryDetailsSort = {
        [void](Set-ListViewSort -ListView $syncHash.LibraryDetailsListView -Property ([string]$syncHash.LibraryDetailsSortProperty) -Direction ([string]$syncHash.LibraryDetailsSortDirection))
    }

    $applyNerdioSort = {
        [void](Set-ListViewSort -ListView $nerdioDefinitionsListView -Property ([string]$syncHash.NerdioSortProperty) -Direction ([string]$syncHash.NerdioSortDirection))
    }

    $applyM365Sort = {
        [void](Set-ListViewSort -ListView $m365ConfigsListView -Property ([string]$syncHash.M365SortProperty) -Direction ([string]$syncHash.M365SortDirection))
    }

    $setIntuneLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = '',
            [ValidateSet('Import', 'Definitions')]
            [string]$Panel = 'Import'
        )

        $syncHash.IsIntuneImportLoading = $IsLoading

        $isDefinitionPanel = $Panel -eq 'Definitions'
        $loadingControls = if ($isDefinitionPanel) {
            @($intuneDefinitionsLoadingPanel, $intuneDefinitionsProgressBar)
        }
        else {
            @($intuneImportLoadingPanel, $intuneImportProgressBar)
        }
        $loadingLabel = if ($isDefinitionPanel) { $intuneDefinitionsLoadingLabel } else { $intuneImportLoadingLabel }
        $idleLoadingMessage = if ($isDefinitionPanel) { 'Updating definitions...' } else { 'Importing Win32 apps...' }

        Set-LoadingState -ButtonStates $syncHash.IntuneActionButtonStates -IsLoading $IsLoading `
            -Buttons @($intuneRefreshCatalogButton, $intuneApplyImportButton, $intuneApplyUpdateImportButton, $intuneUpdateDefinitionsButton) `
            -LoadingControls $loadingControls -LoadingLabel $loadingLabel -LoadingMessage $(if ($isDefinitionPanel -or $IsLoading) { $Message } else { '' }) `
            -IdleLoadingMessage $idleLoadingMessage -StatusLabel $intuneActionStatusLabel

        & $updateIntuneRowActionButtons
    }

    $setInstallLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsInstallLoading = $IsLoading

        Set-LoadingState -ButtonStates $syncHash.InstallActionButtonStates -IsLoading $IsLoading `
            -Buttons @($installLoadDefinitionsButton, $installResolveLatestButton, $installApplyButton) `
            -LoadingControls @($installLoadingPanel, $installProgressBar) -LoadingLabel $installLoadingLabel `
            -LoadingMessage $Message -IdleLoadingMessage 'Working...' -StatusLabel $installActionStatusLabel `
            -ClearStatusOnIdle $false

        & $updateInstallRowActionButtons
    }

    $refreshInstallRows = {
        $definitionRows = @($syncHash.InstallDefinitionRows)
        $rows = [System.Collections.Generic.List[object]]::new()
        $actionableCount = 0
        $hideIncompatibleArchitecture = $false
        if ($null -ne $installHideIncompatibleArchitectureToggle) {
            $hideIncompatibleArchitecture = [bool]$installHideIncompatibleArchitectureToggle.IsChecked
        }
        elseif ($null -ne $syncHash.Config.InstallSettings) {
            $hideIncompatibleArchitecture = [bool]$syncHash.Config.InstallSettings.HideIncompatibleArchitecture
        }

        $localArch = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'x64' }
            'x86' { 'x86' }
            'ARM64' { 'arm64' }
            default { 'x64' }
        }

        foreach ($definitionRow in $definitionRows) {
            $definitionObject = $definitionRow.DefinitionObject
            $architecture = '-'
            $displayArchitecture = '-'
            $installedVersion = '-'
            $detectionStatus = 'Not evaluated'
            $installStatus = 'Needs latest check'
            $installAction = '-'
            $latestVersion = [string]$definitionRow.LatestVersion

            if ($null -ne $definitionObject) {
                $requirementArchValue = [string]$definitionObject.RequirementRule.Architecture
                if (-not [string]::IsNullOrWhiteSpace($requirementArchValue)) {
                    $architecture = $requirementArchValue
                }
                $appArchValue = [string]$definitionObject.Application.Architecture
                if (-not [string]::IsNullOrWhiteSpace($appArchValue)) {
                    $displayArchitecture = $appArchValue
                }
            }

            $isArchCompatible = if ($architecture -eq '-' -or [string]::IsNullOrWhiteSpace($architecture) -or
                $architecture -eq 'All' -or $architecture -eq 'x86,x64,arm64') {
                $true
            }
            else {
                $archList = @($architecture -split ',' | ForEach-Object { $_.Trim().ToLower() })
                $archList -contains $localArch
            }

            if ([string]$definitionRow.DefinitionValid -ne 'Yes' -or $null -eq $definitionObject) {
                $installStatus = [string]$definitionRow.Status
                $installAction = 'Fix definition'
            }
            elseif (-not $isArchCompatible) {
                $installStatus = "Incompatible architecture ($architecture)"
                $installAction = 'Incompatible'
                if ($hideIncompatibleArchitecture) {
                    continue
                }
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

                    $hasDetectedInstallEvidence = -not [string]::IsNullOrWhiteSpace([string]$detectionResult.DetectedVersion)

                    if (-not $detectionResult.Installed) {
                        if ($hasDetectedInstallEvidence) {
                            if ([string]::IsNullOrWhiteSpace($latestVersion)) {
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
                        else {
                            $installStatus = 'Not installed'
                            $installAction = 'Install'
                        }
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
                    Architecture      = $displayArchitecture
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
        $definitionsRoot = ''
        if ($null -ne $intuneDefinitionsPathBox) {
            $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$intuneDefinitionsPathBox.Text)
            $intuneDefinitionsPathBox.Text = $definitionsRoot
            & $applyIntunePathsToConfig
        }
        elseif ($null -ne $syncHash.Config.IntuneSettings) {
            $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$syncHash.Config.IntuneSettings.DefinitionsPath)
        }

        if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
            $syncHash.InstallDefinitionRows = @()
            & $refreshInstallRows
            Write-UILog -SyncHash $syncHash -Message 'Install: set a package definitions folder path on the Packages tab first.' -Level Warning
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
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Invoke-PackageFilter.ps1'
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
                    $cacheState = Initialize-InstallLatestCache -CacheFile $cacheFilePath

                    $rows = [System.Collections.Generic.List[object]]::new()
                    foreach ($definitionRow in $DefinitionRows) {
                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$definitionRow.DefinitionPath) -DefinitionObject $definitionRow.DefinitionObject -CacheRootPath $CacheRootPath -CacheState $cacheState
                        $rows.Add([PSCustomObject]@{
                                DefinitionPath = [string]$definitionRow.DefinitionPath
                                Succeeded      = [bool]$latestResult.Succeeded
                                LatestVersion  = [string]$latestResult.Version
                                LatestError    = [string]$latestResult.Error
                                IsFromCache    = [bool]$latestResult.IsFromCache
                            })
                    }

                    $writeCount = @($rows | Where-Object { -not [bool]$_.IsFromCache }).Count
                    $cacheWasWritten = Save-InstallLatestCache -CacheState $cacheState
                    if ($cacheWasWritten -and $writeCount -gt 0) {
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

        $completionAction_InstallLatestVersion = {
            param($Operation, $Result, $State)
            
            $completionResult = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $completionResult = $Result.Output[0]
            }
            elseif ($Result.Error) {
                $completionResult = [PSCustomObject]@{ Success = $false; Rows = @(); Error = $Result.Error.Exception.Message }
            }
            else {
                $completionResult = $null
            }

            try {
                if ($null -eq $completionResult -or -not $completionResult.Success) {
                    $err = if ($null -eq $completionResult -or [string]::IsNullOrWhiteSpace([string]$completionResult.Error)) { 'Unknown latest version error.' } else { [string]$completionResult.Error }
                    Write-UILog -SyncHash $syncHash -Message "Install: latest version resolution failed: $err" -Level Error
                }
                else {
                    $latestMap = @{}
                    foreach ($row in @($completionResult.Rows)) {
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

                    $cacheCount = @($completionResult.Rows | Where-Object { [bool]$_.Succeeded -and [bool]$_.IsFromCache }).Count
                    $freshCount = @($completionResult.Rows | Where-Object { [bool]$_.Succeeded -and -not [bool]$_.IsFromCache }).Count
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
        }

        & $registerBackgroundOperation -Feature 'Install' -OperationId 'LatestVersion' -PowerShellInstance $ps -RunspaceInstance $rs -CompletionAction $completionAction_InstallLatestVersion
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
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Read-PackageDefinition.ps1'
            'Get-SafeFolderName.ps1'
            'Invoke-PackageFilter.ps1'
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
                        $readResult = Read-PackageDefinition -Path ([string]$action.DefinitionPath)
                        if (-not $readResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = $readResult.Error
                                })
                            continue
                        }
                        $definitionObject = $readResult.Definition

                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$action.DefinitionPath) -DefinitionObject $definitionObject -CacheRootPath $CacheRootPath
                        if (-not [string]::IsNullOrWhiteSpace([string]$latestResult.CacheFile)) {
                            if ([bool]$latestResult.IsFromCache) {
                                Write-UILog -SyncHash $syncHash -Message "Install: cache read for '$([string]$action.Name)' - $([string]$latestResult.Version) from '$([string]$latestResult.CacheFile)'." -Level Info
                            }
                            elseif ([bool]$latestResult.Succeeded) {
                                Write-UILog -SyncHash $syncHash -Message "Install: wrote to cache for '$([string]$action.Name)' - $([string]$latestResult.Version) at '$([string]$latestResult.CacheFile)'." -Level Info
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

        $completionAction_InstallExecute = {
            param($Operation, $Result, $State)
            
            $completionResult = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $completionResult = $Result.Output[0]
            }
            elseif ($Result.Error) {
                $completionResult = [PSCustomObject]@{ Success = $false; Completed = @(); Failed = @(); Error = $Result.Error.Exception.Message }
            }
            else {
                $completionResult = $null
            }

            try {
                if ($null -eq $completionResult -or -not $completionResult.Success) {
                    $err = if ($null -eq $completionResult -or [string]::IsNullOrWhiteSpace([string]$completionResult.Error)) { 'Unknown install error.' } else { [string]$completionResult.Error }
                    Write-UILog -SyncHash $syncHash -Message "Install: operation failed: $err" -Level Error
                }
                else {
                    foreach ($item in @($completionResult.Completed)) {
                        Write-UILog -SyncHash $syncHash -Message "Install: completed '$([string]$item.Name)' (exit code $([int]$item.ExitCode))." -Level Info
                        foreach ($definitionRow in @($syncHash.InstallDefinitionRows)) {
                            if ([string]$definitionRow.DefinitionPath -eq [string]$item.DefinitionPath) {
                                $definitionRow.LatestVersion = [string]$item.LatestVersion
                                break
                            }
                        }
                    }

                    foreach ($item in @($completionResult.Failed)) {
                        Write-UILog -SyncHash $syncHash -Message "Install: failed '$([string]$item.Name)': $([string]$item.Error)" -Level Error
                    }
                }

                & $setInstallElevationState
                & $refreshInstallRows
            }
            finally {
                & $setInstallLoadingState -IsLoading $false
            }
        }

        & $registerBackgroundOperation -Feature 'Install' -OperationId 'Execute' -PowerShellInstance $ps -RunspaceInstance $rs -CompletionAction $completionAction_InstallExecute
    }

    $startIntuneImportOperation = {
        param(
            [bool]$ImportAsUpdate = $false
        )

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
                    AsUpdateApp      = $ImportAsUpdate
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

        & $setIntuneLoadingState -IsLoading $true -Message "Importing $($importActions.Count) app(s)..." -Panel 'Import'
        Write-UILog -SyncHash $syncHash -Message "Intune: starting import of $($importActions.Count) app(s)..." -Level Info

        # Resolve required private helper scripts explicitly so the runspace does not import the full UI module.
        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $helperScripts = @(
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Read-PackageDefinition.ps1'
            'Get-SafeFolderName.ps1'
            'Invoke-PackageFilter.ps1'
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
                    Success      = $false
                    Completed    = [System.Collections.Generic.List[object]]::new()
                    Failed       = [System.Collections.Generic.List[object]]::new()
                    StoppedEarly = $false
                    Error        = ''
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
                        $readResult = Read-PackageDefinition -Path ([string]$action.DefinitionPath)
                        if (-not $readResult.Succeeded) {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = $readResult.Error })
                            $result.StoppedEarly = ($itemIndex -lt $totalCount)
                            break
                        }
                        $definitionObject = $readResult.Definition

                        # Stage 1: resolve latest version, download, and package
                        $buildResult = Invoke-IntunePackageBuild -ComparisonRow ([PSCustomObject]@{
                                DefinitionPath   = $action.DefinitionPath
                                DefinitionObject = $definitionObject
                                DefinitionId     = $action.DefinitionPath
                            }) -WorkingPath $WorkingPath -SyncHash $syncHash

                        if (-not $buildResult.Succeeded) {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = "Build: $($buildResult.Error)" })
                            $result.StoppedEarly = ($itemIndex -lt $totalCount)
                            break
                        }

                        # Stage 2: upload to Intune via Graph
                        $importResult = Invoke-IntuneGraphWin32Import `
                            -DefinitionObject  $definitionObject `
                            -IntuneWinPath     $buildResult.IntuneWinPath `
                            -SetupFilePath     $buildResult.SetupFileUsed `
                            -DownloadedVersion $buildResult.DownloadedVersion `
                            -PSPackageFactoryGuid $action.PSPackageFactory `
                            -DefinitionPath    $action.DefinitionPath `
                            -ImportAsUpdate:$action.AsUpdateApp `
                            -SyncHash          $syncHash

                        if (-not $importResult.Succeeded) {
                            $result.Failed.Add([PSCustomObject]@{ AppName = $action.AppName; Error = "Import: $($importResult.Error)" })
                            $result.StoppedEarly = ($itemIndex -lt $totalCount)
                            break
                        }

                        # Stage 3: configure supersedence for updates (base install apps only; update apps are independent)
                        if (-not $action.AsUpdateApp -and $action.IsUpdate -and -not [string]::IsNullOrWhiteSpace($action.PreviousAppId)) {
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

        $completionAction_IntuneImport = {
            param($Operation, $Result, $State)

            # Do not name this $result: PowerShell variable names are case-insensitive and would overwrite $Result.
            $payload = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $payload = $Result.Output[0]
            }
            elseif ($Result.Error) {
                $payload = [PSCustomObject]@{ Success = $false; Completed = @(); Failed = @(); Error = $Result.Error.Exception.Message }
            }

            try {
                if ($null -eq $payload -or -not $payload.Success) {
                    $errMsg = if ($null -eq $payload -or [string]::IsNullOrWhiteSpace($payload.Error)) { 'Unknown error during import.' } else { $payload.Error }
                    Write-UILog -SyncHash $syncHash -Message "Intune: import run failed: $errMsg" -Level Error
                }
                else {
                    $completedCount = @($payload.Completed).Count
                    $failedCount = @($payload.Failed).Count
                    if ($payload.StoppedEarly) {
                        $skippedCount = $State.ImportActions.Count - $completedCount - $failedCount
                        Write-UILog -SyncHash $syncHash -Message "Intune: import stopped after failure - $completedCount succeeded, $failedCount failed, $skippedCount not attempted." -Level Warning
                    }
                    else {
                        Write-UILog -SyncHash $syncHash -Message "Intune: import complete - $completedCount succeeded, $failedCount failed." -Level Info
                    }
                    foreach ($item in @($payload.Completed)) {
                        Write-UILog -SyncHash $syncHash -Message "  + Imported '$($item.DisplayName)' v$($item.Version) (id: $($item.AppId))" -Level Info
                    }
                    foreach ($item in @($payload.Failed)) {
                        Write-UILog -SyncHash $syncHash -Message "  - Failed '$($item.AppName)': $($item.Error)" -Level Error
                    }
                }

                # Clear loading state before refresh, otherwise loadIntuneWin32Apps exits early.
                & $setIntuneLoadingState -IsLoading $false

                # Refresh the comparison table against the updated Intune catalog
                & $loadIntuneWin32Apps
            }
            finally {
                & $setIntuneLoadingState -IsLoading $false
            }
        }

        $state_IntuneImport = @{ ImportActions = $importActions }
        & $registerBackgroundOperation -Feature 'IntuneImport' -OperationId 'Win32' -PowerShellInstance $ps -RunspaceInstance $rs -CompletionAction $completionAction_IntuneImport -CallbackState $state_IntuneImport
    }

    # -- Microsoft 365 Apps tab scriptblocks ----------------------------------

    $updateM365ActionButtons = {
        $selected = if ($null -ne $m365ConfigsListView) { $m365ConfigsListView.SelectedItem } else { $null }
        $hasValid = ($null -ne $selected) -and ([string]$selected.Status -eq 'Valid')
        $notLoading = -not $syncHash.IsM365ImportLoading

        $intuneReady = $hasValid -and $notLoading -and
        $syncHash.AzureAuthState.IsAuthenticated -and
        $syncHash.AzureAuthState.IntuneConnected

        $nerdioReady = $hasValid -and $notLoading -and
        $syncHash.NerdioApiAuthState.IsAuthenticated

        if ($null -ne $m365ImportIntuneButton) { $m365ImportIntuneButton.IsEnabled = $intuneReady }
        if ($null -ne $m365ImportNerdioButton) { $m365ImportNerdioButton.IsEnabled = $nerdioReady }
    }

    $setM365LoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $syncHash.IsM365ImportLoading = $IsLoading

        & $updateM365ActionButtons

        Set-LoadingState -ButtonStates @{} -IsLoading $IsLoading `
            -LoadingControls $m365ConfigsLoadingPanel -LoadingLabel $m365ConfigsLoadingLabel `
            -LoadingMessage $Message -IdleLoadingMessage 'Loading...' -StatusLabel $m365ActionStatusLabel
    }

    $loadM365EvergreenVersions = {
        # Cancel any in-progress Evergreen fetch
        if ($null -ne $syncHash.PendingM365EvergreenTimer -and $syncHash.PendingM365EvergreenTimer.IsEnabled) {
            $syncHash.PendingM365EvergreenTimer.Stop()
            $syncHash.PendingM365EvergreenTimer = $null
        }
        foreach ($key in @('PendingM365EvergreenPS', 'PendingM365EvergreenRunspace', 'PendingM365EvergreenAsync')) {
            $syncHash[$key] = $null
        }

        $syncHash.IsM365EvergreenLoading = $true

        if ($null -ne $m365ConfigsLoadingPanel) { $m365ConfigsLoadingPanel.Visibility = 'Visible' }
        if ($null -ne $m365ConfigsLoadingLabel) { $m365ConfigsLoadingLabel.Text = 'Fetching latest M365 versions from Evergreen...' }

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $formatLogEntryScript = Join-Path -Path $privateRootPath -ChildPath 'Format-LogEntry.ps1'
        $writeUILogScript = Join-Path -Path $privateRootPath -ChildPath 'Write-UILog.ps1'

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param([string]$FormatLogEntryScript, [string]$WriteUILogScript)
                try {
                    if (Test-Path -LiteralPath $FormatLogEntryScript -PathType Leaf) { . $FormatLogEntryScript }
                    if (Test-Path -LiteralPath $WriteUILogScript -PathType Leaf) { . $WriteUILogScript }
                    if (-not (Get-Command -Name 'Get-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }
                    $rows = @(Get-EvergreenApp -Name 'Microsoft365Apps' -ErrorAction Stop)
                    return $rows
                }
                catch {
                    Write-UILog -SyncHash $syncHash -Message "M365: failed to fetch Evergreen versions: $($_.Exception.Message)" -Level Error
                    return @()
                }
            }).AddArgument($formatLogEntryScript).AddArgument($writeUILogScript)

        $completionAction_M365Evergreen = {
            param($Operation, $Result, $State)

            $evRows = @()
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $evRows = @($Result.Output[0])
            }

            $syncHash.M365EvergreenRows = $evRows

            # Update EvergreenVersion on each config row
            $selectedChannel = if ($null -ne $m365ChannelCombo) { [string]$m365ChannelCombo.SelectedItem.Content } else { '' }
            foreach ($row in $syncHash.M365ConfigRows) {
                $match = $evRows | Where-Object { $_.Channel -eq $row.Channel } |
                Sort-Object -Property { [System.Version]$_.Version } -Descending |
                Select-Object -First 1
                if ($null -ne $match) {
                    $row.EvergreenVersion = [string]$match.Version
                }
            }

            if ($null -ne $m365ConfigsListView) { $m365ConfigsListView.Items.Refresh() }

            # Update version label for the currently selected channel
            if (-not [string]::IsNullOrWhiteSpace($selectedChannel)) {
                $channelMatch = $evRows | Where-Object { $_.Channel -eq $selectedChannel } |
                Sort-Object -Property { [System.Version]$_.Version } -Descending |
                Select-Object -First 1
                if ($null -ne $channelMatch -and $null -ne $m365EvergreenVersionLabel) {
                    $m365EvergreenVersionLabel.Text = [string]$channelMatch.Version
                }
            }

            if ($null -ne $m365ConfigsLoadingPanel) { $m365ConfigsLoadingPanel.Visibility = 'Collapsed' }
            $syncHash.IsM365EvergreenLoading = $false
        }

        $syncHash.PendingM365EvergreenPS = $ps
        $syncHash.PendingM365EvergreenRunspace = $rs

        & $registerBackgroundOperation -Feature 'M365Evergreen' -OperationId 'Check' `
            -PowerShellInstance $ps -RunspaceInstance $rs `
            -CompletionAction $completionAction_M365Evergreen
    }

    $loadM365Configs = {
        $configPath = & $normalizeDirectoryPath -PathValue ([string]$m365ConfigPathBox.Text)
        $m365ConfigPathBox.Text = $configPath
        & $applyM365PathsToConfig

        if ([string]::IsNullOrWhiteSpace($configPath)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: configuration path is not set.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $configPath -PathType Container)) {
            Write-UILog -SyncHash $syncHash -Message "M365: configuration path does not exist: '$configPath'" -Level Warning
            return
        }

        Write-UILog -SyncHash $syncHash -Message "M365: loading configurations from '$configPath'..." -Level Info

        try {
            $rows = @(Get-M365AppConfiguration -DefinitionsRoot $configPath)
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "M365: failed to load configurations: $($_.Exception.Message)" -Level Error
            return
        }

        $syncHash.M365ConfigRows = $rows

        $observableRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($row in $rows) { $observableRows.Add($row) }
        $m365ConfigsListView.ItemsSource = $observableRows

        $validCount = @($rows | Where-Object { $_.Status -eq 'Valid' }).Count
        $m365ConfigsCountText = "$($rows.Count) configuration$(if ($rows.Count -ne 1) {'s'}) ($validCount valid)"
        $m365ConfigsCountLabel.Text = $m365ConfigsCountText
        if ($null -ne $m365PackagesConfigsCountLabel) {
            $m365PackagesConfigsCountLabel.Text = $m365ConfigsCountText
        }

        Write-UILog -SyncHash $syncHash -Message "M365: loaded $($rows.Count) configuration(s)." -Level Info

        & $loadM365EvergreenVersions
    }

    $startM365IntuneImport = {
        if ($syncHash.IsM365ImportLoading) {
            Write-UILog -SyncHash $syncHash -Message 'M365: another import action is already in progress.' -Level Warning
            return
        }

        $selectedRow = $m365ConfigsListView.SelectedItem
        if ($null -eq $selectedRow) {
            Write-UILog -SyncHash $syncHash -Message 'M365: no configuration selected.' -Level Warning
            return
        }

        if ([string]$selectedRow.Status -ne 'Valid') {
            Write-UILog -SyncHash $syncHash -Message "M365: selected configuration '$([string]$selectedRow.FileName)' is not valid (status: $([string]$selectedRow.Status))." -Level Warning
            return
        }

        $configDirPath = & $normalizeDirectoryPath -PathValue ([string]$m365ConfigPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($configDirPath) -or -not (Test-Path -LiteralPath $configDirPath -PathType Container)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: configuration directory path is not valid.' -Level Warning
            return
        }

        # Package output path - re-use Intune output path setting as M365 shares the same working area
        $packageOutputPath = & $normalizeDirectoryPath -PathValue ([string]$intunePackageOutputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($packageOutputPath)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: package output path is not configured. Set it in the Microsoft Intune Win32 Apps pane first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $packageOutputPath -PathType Container)) {
            try { $null = New-Item -ItemType Directory -Path $packageOutputPath -Force -ErrorAction Stop }
            catch {
                Write-UILog -SyncHash $syncHash -Message "M365: cannot create package output path '$packageOutputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        if (-not (& $loadIntuneWin32AppModule)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: IntuneWin32App module is required for packaging but could not be loaded.' -Level Warning
            return
        }

        $channel = if ($null -ne $m365ChannelCombo -and $null -ne $m365ChannelCombo.SelectedItem) { [string]$m365ChannelCombo.SelectedItem.Content } else { '' }
        $companyName = [string]$m365CompanyNameBox.Text.Trim()
        $importFor = if ($null -ne $m365ImportForCombo -and $null -ne $m365ImportForCombo.SelectedItem) { [string]$m365ImportForCombo.SelectedItem.Content } else { '' }
        $tenantId = [string]$syncHash.Config.AzureAuthSettings.TenantId

        if ([string]::IsNullOrWhiteSpace($channel)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: no channel selected.' -Level Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($companyName)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: company name is required.' -Level Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($importFor)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: import session type is required.' -Level Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: tenant ID is required. Sign in on the Authentication tab first.' -Level Warning
            return
        }

        $displayName = [string]$selectedRow.DisplayName

        # Resolve the App.json template bundled with the module
        $appJsonTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Resources\m365-app.json'
        $appJsonTemplatePath = if (Test-Path -LiteralPath $appJsonTemplatePath -PathType Leaf) {
            (Resolve-Path -LiteralPath $appJsonTemplatePath).Path
        }
        else { '' }

        if ([string]::IsNullOrWhiteSpace($appJsonTemplatePath)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: App.json template not found in module Resources folder.' -Level Warning
            return
        }

        # Capture variables for closure
        $capturedRow = $selectedRow
        $capturedConfigDirPath = $configDirPath
        $capturedChannel = $channel
        $capturedCompanyName = $companyName
        $capturedImportFor = $importFor
        $capturedTenantId = $tenantId
        $capturedPackageOutputPath = $packageOutputPath
        $capturedAppJsonTemplate = $appJsonTemplatePath

        & $setM365LoadingState -IsLoading $true -Message "Building package for '$displayName'..."
        Write-UILog -SyncHash $syncHash -Message "M365: starting Intune import for '$displayName' (channel: $channel)..." -Level Info

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $helperScripts = @(
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Invoke-M365AppPackageBuild.ps1'
            'Invoke-IntuneGraphWin32Import.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]      $HelperScripts,
                    [PSCustomObject]$ConfigRow,
                    [string]        $ConfigDirectoryPath,
                    [string]        $Channel,
                    [string]        $CompanyName,
                    [string]        $ImportFor,
                    [string]        $TenantId,
                    [string]        $WorkingPath,
                    [string]        $AppJsonTemplatePath
                )

                $result = [PSCustomObject]@{
                    Success     = $false
                    DisplayName = [string]$ConfigRow.DisplayName
                    AppId       = ''
                    Version     = ''
                    Error       = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Get-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    if (-not (Get-Command -Name 'New-IntuneWin32AppPackage' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name IntuneWin32App -ErrorAction Stop | Out-Null
                    }

                    $buildResult = Invoke-M365AppPackageBuild `
                        -ConfigRow            $ConfigRow `
                        -ConfigDirectoryPath  $ConfigDirectoryPath `
                        -Channel              $Channel `
                        -CompanyName          $CompanyName `
                        -ImportFor            $ImportFor `
                        -TenantId             $TenantId `
                        -WorkingPath          $WorkingPath `
                        -AppJsonTemplatePath  $AppJsonTemplatePath `
                        -SyncHash             $syncHash

                    if (-not $buildResult.Succeeded) {
                        throw "Package build failed: $($buildResult.Error)"
                    }

                    $result.Version = $buildResult.Version

                    if ([string]::IsNullOrWhiteSpace($buildResult.AppJsonPath) -or
                        -not (Test-Path -LiteralPath $buildResult.AppJsonPath -PathType Leaf)) {
                        throw "App.json was not produced by the build step."
                    }

                    $appJsonContent = Get-Content -LiteralPath $buildResult.AppJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
                    $psPackageGuid = [string]$appJsonContent.Information.PSPackageFactoryGuid
                    $importDisplayName = [string]$appJsonContent.Information.DisplayName

                    $syncHash.Window.Dispatcher.Invoke([action] {
                            if ($null -ne $syncHash.M365ActionStatusLabel) {
                                $syncHash.M365ActionStatusLabel.Text = 'Uploading to Intune...'
                            }
                            if ($null -ne $syncHash.M365ConfigsLoadingLabel) {
                                $syncHash.M365ConfigsLoadingLabel.Text = "Uploading '$importDisplayName' to Intune..."
                            }
                        }, 'Normal')

                    $importResult = Invoke-IntuneGraphWin32Import `
                        -DefinitionObject     $appJsonContent `
                        -DefinitionPath       $buildResult.AppJsonPath `
                        -IntuneWinPath        $buildResult.IntuneWinPath `
                        -SetupFilePath        $buildResult.SetupFileUsed `
                        -DownloadedVersion    $buildResult.Version `
                        -PSPackageFactoryGuid $psPackageGuid `
                        -SyncHash             $syncHash

                    if (-not $importResult.Succeeded) {
                        throw "Intune import failed: $($importResult.Error)"
                    }

                    $result.AppId = $importResult.IntuneAppId
                    $result.Success = $true
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            })
        [void]$ps.AddArgument(@($helperScripts))
        [void]$ps.AddArgument($capturedRow)
        [void]$ps.AddArgument($capturedConfigDirPath)
        [void]$ps.AddArgument($capturedChannel)
        [void]$ps.AddArgument($capturedCompanyName)
        [void]$ps.AddArgument($capturedImportFor)
        [void]$ps.AddArgument($capturedTenantId)
        [void]$ps.AddArgument($capturedPackageOutputPath)
        [void]$ps.AddArgument($capturedAppJsonTemplate)

        $completionAction_M365ImportIntune = {
            param($Operation, $Result, $State)

            # Do not name this $result: PowerShell variable names are case-insensitive and would overwrite $Result.
            $payload = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $payload = $Result.Output[$Result.Output.Count - 1]
            }
            elseif ($Result.Error) {
                $payload = [PSCustomObject]@{ Success = $false; DisplayName = ''; AppId = ''; Version = ''; Error = $Result.Error.Exception.Message }
            }

            try {
                if ($null -eq $payload -or -not $payload.Success) {
                    $errMsg = if ($null -eq $payload -or [string]::IsNullOrWhiteSpace($payload.Error)) { 'Unknown error during M365 Intune import.' } else { $payload.Error }
                    Write-UILog -SyncHash $syncHash -Message "M365: Intune import failed: $errMsg" -Level Error
                }
                else {
                    Write-UILog -SyncHash $syncHash -Message "M365: Intune import succeeded - '$([string]$payload.DisplayName)' v$([string]$payload.Version) (id: $([string]$payload.AppId))" -Level Info
                }
            }
            finally {
                & $setM365LoadingState -IsLoading $false
            }
        }

        $syncHash.PendingM365ImportPS = $ps
        $syncHash.PendingM365ImportRunspace = $rs

        & $registerBackgroundOperation -Feature 'M365Import' -OperationId 'Build' `
            -PowerShellInstance $ps -RunspaceInstance $rs `
            -CompletionAction $completionAction_M365ImportIntune
    }

    $startM365NerdioImport = {
        if ($syncHash.IsM365ImportLoading) {
            Write-UILog -SyncHash $syncHash -Message 'M365: another import action is already in progress.' -Level Warning
            return
        }

        $selectedRow = $m365ConfigsListView.SelectedItem
        if ($null -eq $selectedRow) {
            Write-UILog -SyncHash $syncHash -Message 'M365: no configuration selected.' -Level Warning
            return
        }

        if ([string]$selectedRow.Status -ne 'Valid') {
            Write-UILog -SyncHash $syncHash -Message "M365: selected configuration '$([string]$selectedRow.FileName)' is not valid." -Level Warning
            return
        }

        $configDirPath = & $normalizeDirectoryPath -PathValue ([string]$m365ConfigPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($configDirPath) -or -not (Test-Path -LiteralPath $configDirPath -PathType Container)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: configuration directory path is not valid.' -Level Warning
            return
        }

        $packageOutputPath = & $normalizeDirectoryPath -PathValue ([string]$intunePackageOutputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($packageOutputPath)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: package output path is not configured. Set it in the Microsoft Intune Win32 Apps pane first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $packageOutputPath -PathType Container)) {
            try { $null = New-Item -ItemType Directory -Path $packageOutputPath -Force -ErrorAction Stop }
            catch {
                Write-UILog -SyncHash $syncHash -Message "M365: cannot create package output path '$packageOutputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        $shellAppDirPath = Join-Path -Path $configDirPath -ChildPath 'shell-app'
        if (-not (Test-Path -LiteralPath $shellAppDirPath -PathType Container)) {
            Write-UILog -SyncHash $syncHash -Message "M365: 'shell-app' directory not found at '$shellAppDirPath'. Create it with Definition.json, Detect.ps1, Install.ps1, and Uninstall.ps1." -Level Warning
            return
        }

        foreach ($requiredFile in @('Definition.json', 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1')) {
            $requiredFilePath = Join-Path -Path $shellAppDirPath -ChildPath $requiredFile
            if (-not (Test-Path -LiteralPath $requiredFilePath -PathType Leaf)) {
                Write-UILog -SyncHash $syncHash -Message "M365: required shell-app file '$requiredFile' not found in '$shellAppDirPath'." -Level Warning
                return
            }
        }

        $modulePath = & $normalizeDirectoryPath -PathValue $nerdioBundledModulePath
        if ([string]::IsNullOrWhiteSpace($modulePath) -or -not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            Write-UILog -SyncHash $syncHash -Message "M365: bundled Nerdio module is missing: $modulePath" -Level Error
            return
        }

        $channel = if ($null -ne $m365ChannelCombo -and $null -ne $m365ChannelCombo.SelectedItem) { [string]$m365ChannelCombo.SelectedItem.Content } else { '' }
        $companyName = [string]$m365CompanyNameBox.Text.Trim()
        $importFor = if ($null -ne $m365ImportForCombo -and $null -ne $m365ImportForCombo.SelectedItem) { [string]$m365ImportForCombo.SelectedItem.Content } else { '' }
        $tenantId = [string]$syncHash.Config.AzureAuthSettings.TenantId

        if ([string]::IsNullOrWhiteSpace($channel)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: no channel selected.' -Level Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($companyName)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: company name is required.' -Level Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($importFor)) {
            Write-UILog -SyncHash $syncHash -Message 'M365: import session type is required.' -Level Warning
            return
        }

        $displayName = [string]$selectedRow.DisplayName

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

        $capturedRow = $selectedRow
        $capturedConfigDirPath = $configDirPath
        $capturedShellAppDirPath = $shellAppDirPath
        $capturedChannel = $channel
        $capturedCompanyName = $companyName
        $capturedImportFor = $importFor
        $capturedTenantId = $tenantId
        $capturedPackageOutputPath = $packageOutputPath
        $capturedModulePath = $modulePath
        $capturedNerdioAuth = $nerdioAuthContext

        & $setM365LoadingState -IsLoading $true -Message "Building package for '$displayName'..."
        Write-UILog -SyncHash $syncHash -Message "M365: starting Nerdio Shell App import for '$displayName' (channel: $channel)..." -Level Info

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $helperScripts = @(
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Invoke-M365AppShellAppBuild.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $syncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]      $HelperScripts,
                    [PSCustomObject]$ConfigRow,
                    [string]        $ConfigDirectoryPath,
                    [string]        $Channel,
                    [string]        $CompanyName,
                    [string]        $ImportFor,
                    [string]        $TenantId,
                    [string]        $WorkingPath,
                    [string]        $ShellAppDirPath,
                    [string]        $NerdioModulePath,
                    [PSCustomObject]$NerdioAuthContext
                )

                $result = [PSCustomObject]@{
                    Success     = $false
                    DisplayName = [string]$ConfigRow.DisplayName
                    Version     = ''
                    Error       = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Get-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    $buildResult = Invoke-M365AppShellAppBuild `
                        -ConfigRow           $ConfigRow `
                        -ConfigDirectoryPath $ConfigDirectoryPath `
                        -Channel             $Channel `
                        -CompanyName         $CompanyName `
                        -ImportFor           $ImportFor `
                        -TenantId            $TenantId `
                        -WorkingPath         $WorkingPath `
                        -SyncHash            $syncHash

                    if (-not $buildResult.Succeeded) {
                        throw "Shell App zip build failed: $($buildResult.Error)"
                    }

                    $result.Version = $buildResult.Version

                    $syncHash.Window.Dispatcher.Invoke([action] {
                            if ($null -ne $syncHash.M365ActionStatusLabel) {
                                $syncHash.M365ActionStatusLabel.Text = 'Uploading to Nerdio Manager...'
                            }
                            if ($null -ne $syncHash.M365ConfigsLoadingLabel) {
                                $syncHash.M365ConfigsLoadingLabel.Text = "Uploading '$([string]$ConfigRow.DisplayName)' to Nerdio Manager..."
                            }
                        }, 'Normal')

                    Import-Module -Name $NerdioModulePath -Force -ErrorAction Stop | Out-Null

                    $module = Get-Module -Name NerdioShellApps -ErrorAction SilentlyContinue
                    if ($null -ne $module -and $null -ne $module.SessionState -and $null -ne $module.SessionState.PSVariable) {
                        $module.SessionState.PSVariable.Set('InformationPreference', 'SilentlyContinue')
                    }

                    $setNmeCredCmd = Get-Command -Name 'NerdioShellApps\Set-NmeCredentials'    -ErrorAction SilentlyContinue
                    $connectNmeCmd = Get-Command -Name 'NerdioShellApps\Connect-Nme'            -ErrorAction SilentlyContinue
                    $getShellAppDefCmd = Get-Command -Name 'NerdioShellApps\Get-ShellAppDefinition' -ErrorAction SilentlyContinue
                    $newShellAppCmd = Get-Command -Name 'NerdioShellApps\New-ShellApp'           -ErrorAction SilentlyContinue

                    if ($null -eq $setNmeCredCmd) { throw 'Set-NmeCredentials not found in NerdioShellApps module.' }
                    if ($null -eq $connectNmeCmd) { throw 'Connect-Nme not found in NerdioShellApps module.' }
                    if ($null -eq $getShellAppDefCmd) { throw 'Get-ShellAppDefinition not found in NerdioShellApps module.' }
                    if ($null -eq $newShellAppCmd) { throw 'New-ShellApp not found in NerdioShellApps module.' }

                    foreach ($required in @(
                            @{ Name = 'Tenant ID'; Value = [string]$NerdioAuthContext.TenantId },
                            @{ Name = 'NME Host'; Value = [string]$NerdioAuthContext.NmeHost },
                            @{ Name = 'Client ID'; Value = [string]$NerdioAuthContext.ClientId },
                            @{ Name = 'API Scope'; Value = [string]$NerdioAuthContext.ApiScope },
                            @{ Name = 'Client Secret'; Value = [string]$NerdioAuthContext.ClientSecret }
                        )) {
                        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                            throw "Nerdio API $($required.Name) is required."
                        }
                    }

                    & $setNmeCredCmd `
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

                    $null = & $connectNmeCmd -PassThru

                    $definition = & $getShellAppDefCmd -Path $ShellAppDirPath
                    if ($null -eq $definition) {
                        throw "Failed to load Shell App definition from: $ShellAppDirPath"
                    }

                    $definition.name = [string]$ConfigRow.DisplayName

                    # Append description note with setup.exe version, SharedComputerLicensing, and XML file name
                    if (-not [string]::IsNullOrWhiteSpace($buildResult.DescriptionNote)) {
                        $hasDescProp = $null -ne $definition.PSObject.Properties['description']
                        $existingDesc = if ($hasDescProp) { [string]$definition.description } else { '' }
                        $newDesc = if ([string]::IsNullOrWhiteSpace($existingDesc)) {
                            $buildResult.DescriptionNote
                        }
                        else {
                            "$existingDesc`n$($buildResult.DescriptionNote)"
                        }
                        if ($hasDescProp) {
                            $definition.description = $newDesc
                        }
                        else {
                            $definition | Add-Member -MemberType NoteProperty -Name 'description' -Value $newDesc -Force
                        }
                    }

                    $appMetadata = [PSCustomObject]@{
                        Version = $buildResult.Version
                        File    = $buildResult.ZipPath
                        URI     = ''
                    }

                    $null = & $newShellAppCmd -Definition $definition -AppMetadata $appMetadata

                    $result.Success = $true
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            })
        [void]$ps.AddArgument(@($helperScripts))
        [void]$ps.AddArgument($capturedRow)
        [void]$ps.AddArgument($capturedConfigDirPath)
        [void]$ps.AddArgument($capturedChannel)
        [void]$ps.AddArgument($capturedCompanyName)
        [void]$ps.AddArgument($capturedImportFor)
        [void]$ps.AddArgument($capturedTenantId)
        [void]$ps.AddArgument($capturedPackageOutputPath)
        [void]$ps.AddArgument($capturedShellAppDirPath)
        [void]$ps.AddArgument($capturedModulePath)
        [void]$ps.AddArgument($capturedNerdioAuth)

        $completionAction_M365ImportNerdio = {
            param($Operation, $Result, $State)

            # Do not name this $result: PowerShell variable names are case-insensitive and would overwrite $Result.
            $payload = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $payload = $Result.Output[$Result.Output.Count - 1]
            }
            elseif ($Result.Error) {
                $payload = [PSCustomObject]@{ Success = $false; DisplayName = ''; Version = ''; Error = $Result.Error.Exception.Message }
            }

            try {
                if ($null -eq $payload -or -not $payload.Success) {
                    $errMsg = if ($null -eq $payload -or [string]::IsNullOrWhiteSpace($payload.Error)) { 'Unknown error during M365 Nerdio import.' } else { $payload.Error }
                    Write-UILog -SyncHash $syncHash -Message "M365: Nerdio import failed: $errMsg" -Level Error
                }
                else {
                    Write-UILog -SyncHash $syncHash -Message "M365: Nerdio Shell App created for '$([string]$payload.DisplayName)' v$([string]$payload.Version)." -Level Info
                }
            }
            finally {
                & $setM365LoadingState -IsLoading $false
            }
        }

        $syncHash.PendingM365ImportPS = $ps
        $syncHash.PendingM365ImportRunspace = $rs

        & $registerBackgroundOperation -Feature 'M365Import' -OperationId 'BuildNerdio' `
            -PowerShellInstance $ps -RunspaceInstance $rs `
            -CompletionAction $completionAction_M365ImportNerdio
    }

    # Apply persisted window size with safe minimums
    $window.Width = [Math]::Max(900, [double]$syncHash.Config.WindowWidth)
    $window.Height = [Math]::Max(600, [double]$syncHash.Config.WindowHeight)

    # Register all UI features via modular registration handlers (item 17, phase 5)
    # This orchestrates event handler setup for all eight navigation views and their
    # associated workflows (Apps, Download, Library, Install, Import, Settings, Update, About).
    # Each feature registration function sets up its own event handlers and helper scriptblocks,
    # keeping the public function focused on orchestration rather than implementation detail.
    Register-UIFeatures -SyncHash $syncHash -Window $window

    # Show window (blocking)
    [void]$window.ShowDialog()
}
