function Register-UIFeatures {
    <#
    .SYNOPSIS
    Orchestrates registration of all UI feature event handlers and initialization.

    .DESCRIPTION
    This function coordinates the setup of event handlers for all eight navigation views
    (Apps, Download, Library, Packages/Install, Import, Settings, Update, About) and their
    related workflows. It is called once during window startup after XAML is loaded and
    controls are resolved.

    Rather than keeping all event registration inline in Start-EvergreenWorkbench,
    this function delegates to feature-specific registration helpers and maintains
    a clean separation of concerns.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls, state, and async operation tracking.

    .PARAMETER Window
    The WPF Window object.

    .NOTES
    This is an internal orchestration function for the EvergreenUI module.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Windows.Window]$Window
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Resolve all required control references from XAML
    # (This was previously done inline in Start-EvergreenWorkbench)
    $controls = @{}
    
    # Navigation controls
    $controls.NavToggleButton = $Window.FindName('NavToggleButton')
    $controls.NavApps = $Window.FindName('NavApps')
    $controls.NavDownload = $Window.FindName('NavDownload')
    $controls.NavLibrary = $Window.FindName('NavLibrary')
    $controls.NavPackages = $Window.FindName('NavPackages')
    $controls.NavImport = $Window.FindName('NavImport')
    $controls.NavInstall = $Window.FindName('NavInstall')
    $controls.NavSettings = $Window.FindName('NavSettings')
    $controls.NavUpdate = $Window.FindName('NavUpdate')
    $controls.NavAbout = $Window.FindName('NavAbout')

    # Panel controls
    $controls.AppsPanel = $Window.FindName('AppsPanel')
    $controls.DownloadPanel = $Window.FindName('DownloadPanel')
    $controls.LibraryPanel = $Window.FindName('LibraryPanel')
    $controls.PackagesPanel = $Window.FindName('PackagesPanel')
    $controls.ImportPanel = $Window.FindName('ImportPanel')
    $controls.InstallPanel = $Window.FindName('InstallPanel')
    $controls.SettingsPanel = $Window.FindName('SettingsPanel')
    $controls.UpdatePanel = $Window.FindName('UpdatePanel')
    $controls.AboutPanel = $Window.FindName('AboutPanel')

    # Theme controls
    $controls.ThemeComboBox = $Window.FindName('ThemeComboBox')
    $controls.RootGrid = $Window.FindName('RootGrid')

    # Log/output controls
    $controls.LogTextBox = $Window.FindName('LogTextBox')
    $controls.LogScrollViewer = $Window.FindName('LogScrollViewer')
    $controls.CopyLogButton = $Window.FindName('CopyLogButton')
    $controls.SaveLogButton = $Window.FindName('SaveLogButton')
    $controls.LogToggleButton = $Window.FindName('LogToggleButton')

    # Apps feature controls
    $controls.RefreshAppsButton = $Window.FindName('RefreshAppsButton')
    $controls.AppSearchBox = $Window.FindName('AppSearchBox')
    $controls.AppsListBox = $Window.FindName('AppsListBox')
    $controls.LoadAppVersionsButton = $Window.FindName('LoadAppVersionsButton')
    $controls.FilterWrapPanel = $Window.FindName('FilterWrapPanel')
    $controls.ClearFiltersButton = $Window.FindName('ClearFiltersButton')
    $controls.ExportCsvButton = $Window.FindName('ExportCsvButton')
    $controls.AddToLibraryButton = $Window.FindName('AddToLibraryButton')
    $controls.AppsActionStatusLabel = $Window.FindName('AppsActionStatusLabel')
    $controls.AddToQueueButton = $Window.FindName('AddToQueueButton')
    $controls.AppCountLabel = $Window.FindName('AppCountLabel')
    $controls.AppDetailEmpty = $Window.FindName('AppDetailEmpty')
    $controls.AppDetailLoading = $Window.FindName('AppDetailLoading')
    $controls.AppDetailLoadingLabel = $Window.FindName('AppDetailLoadingLabel')
    $controls.AppDetailContent = $Window.FindName('AppDetailContent')
    $controls.AppDetailTitle = $Window.FindName('AppDetailTitle')

    # Download feature controls
    $controls.RemoveQueueItemButton = $Window.FindName('RemoveQueueItemButton')
    $controls.ClearQueueButton = $Window.FindName('ClearQueueButton')
    $controls.OpenDownloadFolderButton = $Window.FindName('OpenDownloadFolderButton')
    $controls.OutputPathBox = $Window.FindName('OutputPathBox')

    # Library feature controls
    $controls.LibraryPathViewBox = $Window.FindName('LibraryPathViewBox')
    $controls.BrowseLibraryButton = $Window.FindName('BrowseLibraryButton')
    $controls.LibraryNewButton = $Window.FindName('LibraryNewButton')
    $controls.LibraryRefreshButton = $Window.FindName('LibraryRefreshButton')
    $controls.LibraryOpenFolderButton = $Window.FindName('LibraryOpenFolderButton')

    # Install/Packages feature controls
    $controls.InstallLoadDefinitionsButton = $Window.FindName('InstallLoadDefinitionsButton')
    $controls.InstallResolveLatestButton = $Window.FindName('InstallResolveLatestButton')
    $controls.InstallHideIncompatibleArchitectureToggle = $Window.FindName('InstallHideIncompatibleArchitectureToggle')
    $controls.InstallDefinitionsCountLabel = $Window.FindName('InstallDefinitionsCountLabel')
    $controls.InstallActionableCountLabel = $Window.FindName('InstallActionableCountLabel')
    $controls.InstallElevationStatusDot = $Window.FindName('InstallElevationStatusDot')
    $controls.InstallElevationStatusLabel = $Window.FindName('InstallElevationStatusLabel')
    $controls.InstallLoadingPanel = $Window.FindName('InstallLoadingPanel')
    $controls.InstallLoadingLabel = $Window.FindName('InstallLoadingLabel')
    $controls.InstallProgressBar = $Window.FindName('InstallProgressBar')
    $controls.InstallPackagesListView = $Window.FindName('InstallPackagesListView')
    $controls.InstallApplyButton = $Window.FindName('InstallApplyButton')
    $controls.InstallActionStatusLabel = $Window.FindName('InstallActionStatusLabel')
    $controls.BrowseOutputButton = $Window.FindName('BrowseOutputButton')

    # Import feature controls (shared across providers)
    $controls.ImportProviderTabControl = $Window.FindName('ImportProviderTabControl')

    # Intune/Win32 controls
    $controls.ImportTenantIdBox = $Window.FindName('ImportTenantIdBox')
    $controls.ImportAuthStatusDot = $Window.FindName('ImportAuthStatusDot')
    $controls.ImportAuthStatusLabel = $Window.FindName('ImportAuthStatusLabel')
    $controls.ImportSignInButton = $Window.FindName('ImportSignInButton')
    $controls.ImportSignOutButton = $Window.FindName('ImportSignOutButton')
    $controls.IntuneRefreshCatalogButton = $Window.FindName('IntuneRefreshCatalogButton')
    $controls.IntunePackageOutputPathBox = $Window.FindName('IntunePackageOutputPathBox')
    $controls.IntuneBrowsePackageOutputButton = $Window.FindName('IntuneBrowsePackageOutputButton')
    $controls.IntuneDefinitionsPathBox = $Window.FindName('IntuneDefinitionsPathBox')
    $controls.BrowseIntuneDefinitionsButton = $Window.FindName('BrowseIntuneDefinitionsButton')
    $controls.IntuneLoadDefinitionsButton = $Window.FindName('IntuneLoadDefinitionsButton')
    $controls.IntuneUpdateDefinitionsButton = $Window.FindName('IntuneUpdateDefinitionsButton')
    $controls.IntuneDefinitionsCountLabel = $Window.FindName('IntuneDefinitionsCountLabel')
    $controls.IntuneWin32AppsCountLabel = $Window.FindName('IntuneWin32AppsCountLabel')
    $controls.IntuneConnectionStatusDot = $Window.FindName('IntuneConnectionStatusDot')
    $controls.IntuneConnectionStatusLabel = $Window.FindName('IntuneConnectionStatusLabel')
    $controls.IntuneWin32AppsListView = $Window.FindName('IntuneWin32AppsListView')
    $controls.IntuneActionStatusLabel = $Window.FindName('IntuneActionStatusLabel')
    $controls.IntuneDefinitionsLoadingPanel = $Window.FindName('IntuneDefinitionsLoadingPanel')
    $controls.IntuneDefinitionsLoadingLabel = $Window.FindName('IntuneDefinitionsLoadingLabel')
    $controls.IntuneDefinitionsProgressBar = $Window.FindName('IntuneDefinitionsProgressBar')
    $controls.IntuneImportLoadingPanel = $Window.FindName('IntuneImportLoadingPanel')
    $controls.IntuneImportLoadingLabel = $Window.FindName('IntuneImportLoadingLabel')
    $controls.IntuneImportProgressBar = $Window.FindName('IntuneImportProgressBar')
    $controls.IntuneApplyImportButton = $Window.FindName('IntuneApplyImportButton')
    $controls.IntuneApplyUpdateImportButton = $Window.FindName('IntuneApplyUpdateImportButton')

    # Nerdio/Shell Apps controls
    $controls.NmeHostBox = $Window.FindName('NmeHostBox')
    $controls.NmeClientIdBox = $Window.FindName('NmeClientIdBox')
    $controls.NmeApiScopeBox = $Window.FindName('NmeApiScopeBox')
    $controls.NmeOAuthTokenUrlBox = $Window.FindName('NmeOAuthTokenUrlBox')
    $controls.NmeClientSecretBox = $Window.FindName('NmeClientSecretBox')
    $controls.NmeSubscriptionIdBox = $Window.FindName('NmeSubscriptionIdBox')
    $controls.NmeResourceGroupCombo = $Window.FindName('NmeResourceGroupCombo')
    $controls.NmeStorageAccountCombo = $Window.FindName('NmeStorageAccountCombo')
    $controls.NmeContainerCombo = $Window.FindName('NmeContainerCombo')
    $controls.NerdioTenantIdBox = $Window.FindName('NerdioTenantIdBox')
    $controls.NerdioApiAuthStatusDot = $Window.FindName('NerdioApiAuthStatusDot')
    $controls.NerdioApiAuthStatusLabel = $Window.FindName('NerdioApiAuthStatusLabel')
    $controls.NerdioApiSignInButton = $Window.FindName('NerdioApiSignInButton')
    $controls.NerdioApiSignOutButton = $Window.FindName('NerdioApiSignOutButton')
    $controls.NerdioDefinitionsPathBox = $Window.FindName('NerdioDefinitionsPathBox')
    $controls.BrowseNerdioDefinitionsButton = $Window.FindName('BrowseNerdioDefinitionsButton')
    $controls.NerdioLoadConfigsButton = $Window.FindName('NerdioLoadConfigsButton')
    $controls.NerdioLoadDefinitionsButton = $Window.FindName('NerdioLoadDefinitionsButton')
    $controls.NerdioListShellAppsButton = $Window.FindName('NerdioListShellAppsButton')
    $controls.NerdioDefinitionsListView = $Window.FindName('NerdioDefinitionsListView')
    $controls.NerdioDefinitionsCountLabel = $Window.FindName('NerdioDefinitionsCountLabel')
    $controls.NerdioPackagesDefinitionsCountLabel = $Window.FindName('NerdioPackagesDefinitionsCountLabel')
    $controls.NerdioShellAppsCountLabel = $Window.FindName('NerdioShellAppsCountLabel')
    $controls.NerdioShellAppsLoadingPanel = $Window.FindName('NerdioShellAppsLoadingPanel')
    $controls.NerdioShellAppsLoadingLabel = $Window.FindName('NerdioShellAppsLoadingLabel')
    $controls.NerdioShellAppsProgressBar = $Window.FindName('NerdioShellAppsProgressBar')
    $controls.NerdioAddVersionButton = $Window.FindName('NerdioAddVersionButton')
    $controls.NerdioPruneVersionsButton = $Window.FindName('NerdioPruneVersionsButton')
    $controls.NerdioImportNewButton = $Window.FindName('NerdioImportNewButton')
    $controls.NerdioActionStatusLabel = $Window.FindName('NerdioActionStatusLabel')
    $controls.NerdioImportAuthStatusDot = $Window.FindName('NerdioImportAuthStatusDot')
    $controls.NerdioImportAuthStatusLabel = $Window.FindName('NerdioImportAuthStatusLabel')
    $controls.NerdioAzureAuthStatusDot = $Window.FindName('NerdioAzureAuthStatusDot')
    $controls.NerdioAzureAuthStatusLabel = $Window.FindName('NerdioAzureAuthStatusLabel')
    $controls.NerdioAzureSignInButton = $Window.FindName('NerdioAzureSignInButton')
    $controls.NerdioAzureSignOutButton = $Window.FindName('NerdioAzureSignOutButton')

    # M365 controls
    $controls.M365ConfigPathBox = $Window.FindName('M365ConfigPathBox')
    $controls.BrowseM365ConfigButton = $Window.FindName('BrowseM365ConfigButton')
    $controls.M365LoadConfigsButton = $Window.FindName('M365LoadConfigsButton')
    $controls.M365ChannelCombo = $Window.FindName('M365ChannelCombo')
    $controls.M365CompanyNameBox = $Window.FindName('M365CompanyNameBox')
    $controls.M365ImportForCombo = $Window.FindName('M365ImportForCombo')
    $controls.M365ConfigsListView = $Window.FindName('M365ConfigsListView')
    $controls.M365ConfigsCountLabel = $Window.FindName('M365ConfigsCountLabel')
    $controls.M365PackagesConfigsCountLabel = $Window.FindName('M365PackagesConfigsCountLabel')
    $controls.M365ConfigsLoadingPanel = $Window.FindName('M365ConfigsLoadingPanel')
    $controls.M365ConfigsLoadingLabel = $Window.FindName('M365ConfigsLoadingLabel')
    $controls.M365ImportIntuneButton = $Window.FindName('M365ImportIntuneButton')
    $controls.M365ImportNerdioButton = $Window.FindName('M365ImportNerdioButton')
    $controls.M365EvergreenVersionLabel = $Window.FindName('M365EvergreenVersionLabel')

    # Settings controls
    $controls.EvergreenAppsPathBox = $Window.FindName('EvergreenAppsPathBox')
    $controls.ShowImportTabToggle = $Window.FindName('ShowImportTabToggle')
    $controls.ShowInstallTabToggle = $Window.FindName('ShowInstallTabToggle')
    $controls.OpenEvergreenAppsFolderButton = $Window.FindName('OpenEvergreenAppsFolderButton')
    $controls.ClearCacheButton = $Window.FindName('ClearCacheButton')
    $controls.OpenCacheFolderButton = $Window.FindName('OpenCacheFolderButton')
    $controls.OpenLogsFolderButton = $Window.FindName('OpenLogsFolderButton')
    $controls.ClearLogsButton = $Window.FindName('ClearLogsButton')

    # About controls
    $controls.AboutNameValue = $Window.FindName('AboutNameValue')
    $controls.AboutVersionValue = $Window.FindName('AboutVersionValue')
    $controls.AboutPrereleaseValue = $Window.FindName('AboutPrereleaseValue')
    $controls.AboutAuthorValue = $Window.FindName('AboutAuthorValue')
    $controls.AboutCompanyValue = $Window.FindName('AboutCompanyValue')
    $controls.AboutCopyrightValue = $Window.FindName('AboutCopyrightValue')
    $controls.AboutLicenseValue = $Window.FindName('AboutLicenseValue')
    $controls.AboutProjectUriValue = $Window.FindName('AboutProjectUriValue')
    $controls.AboutDescriptionValue = $Window.FindName('AboutDescriptionValue')
    $controls.AboutRequiredModulesList = $Window.FindName('AboutRequiredModulesList')

    # Store controls in SyncHash for access throughout the application
    $SyncHash.Controls = $controls
    $SyncHash['SetUIConfig'] = ${function:Set-UIConfig}.GetNewClosure()
    $SyncHash['WriteUILog'] = ${function:Write-UILog}.GetNewClosure()
    $SyncHash['SetDarkTheme'] = ${function:Set-DarkTheme}.GetNewClosure()
    $SyncHash['SetLightTheme'] = ${function:Set-LightTheme}.GetNewClosure()
    $SyncHash['GetEvergreenAppsPath'] = ${function:Get-EvergreenAppsPath}.GetNewClosure()

    # Delegate to feature-specific registration functions in order
    # Each registration function accepts $SyncHash and $controls as parameters
    # and sets up event handlers for its domain

    Write-Verbose 'EvergreenUI: Registering Apps feature...'
    Register-AppsFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Download feature...'
    Register-DownloadFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Library feature...'
    Register-LibraryFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Install feature...'
    Register-InstallFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Import feature...'
    Register-ImportFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Settings feature...'
    Register-SettingsFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Navigation feature...'
    Register-NavigationFeature -SyncHash $SyncHash -Controls $controls

    Write-Verbose 'EvergreenUI: Registering Window lifetime handlers...'
    Register-WindowLifetime -SyncHash $SyncHash -Controls $controls -Window $Window

    Write-Verbose 'EvergreenUI: UI feature registration complete.'
}
