Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwWorkbenchState {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [object]$Window,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $module = $ExecutionContext.SessionState.Module
    $moduleInvoker = {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Parameters
        )

        & $module {
            param($CommandName, $CommandParameters)
            & $CommandName @CommandParameters
        } $Name $Parameters
    }.GetNewClosure()
    $state = [hashtable]::Synchronized(@{
            Window = $Window
            ModuleInvoker = $moduleInvoker
            Settings = $Settings
            Queue = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            ActiveJobId = $null
            ActiveJobKind = ''
            MaintenancePromptActive = $false
            MaintenanceContext = $null
            AppsDisplayStale = $false
            UpdateEvergreenButton = $Window.FindName('UpdateEvergreenButton')
            ClearWorkbenchCacheButton = $Window.FindName('ClearWorkbenchCacheButton')
            OpenCacheFolderButton = $Window.FindName('OpenCacheFolderButton')
            AppsMaintenanceStatusLabel = $Window.FindName('AppsMaintenanceStatusLabel')
            ProgressReadIndex = 0
            InformationReadIndex = 0
            ErrorReadIndex = 0
            CurrentApp = $null
            CurrentAppName = ''
            ArtifactFiltersPanel = $Window.FindName('ArtifactFiltersPanel')
            ArtifactCountLabel = $Window.FindName('ArtifactCountLabel')
            AppsListView = $Window.FindName('AppsListView')
            AppSearchBox = $Window.FindName('AppSearchBox')
            AppCountLabel = $Window.FindName('AppCountLabel')
            ArtifactsGrid = $Window.FindName('ArtifactsGrid')
            ActivityLog = $Window.FindName('ActivityLog')
            BrowseLibraryPathButton = $Window.FindName('BrowseLibraryPathButton')
            BrowseOutputPathButton = $Window.FindName('BrowseOutputPathButton')
            ClearQueueButton = $Window.FindName('ClearQueueButton')
            DownloadPanel = $Window.FindName('DownloadPanel')
            DownloadQueueListView = $Window.FindName('DownloadQueueListView')
            FavoriteAppButton = $Window.FindName('FavoriteAppButton')
            JobProgressBar = $Window.FindName('JobProgressBar')
            LibraryListView = $Window.FindName('LibraryListView')
            LibraryPanel = $Window.FindName('LibraryPanel')
            LibraryPathBox = $Window.FindName('LibraryPathBox')
            LibraryDetailsText = $Window.FindName('LibraryDetailsText')
            LibraryVersionsListView = $Window.FindName('LibraryVersionsListView')
            LoadLibraryButton = $Window.FindName('LoadLibraryButton')
            NavApps = $Window.FindName('NavApps')
            NavDownload = $Window.FindName('NavDownload')
            NavLibrary = $Window.FindName('NavLibrary')
            NavPackages = $Window.FindName('NavPackages')
            NavIntune = $Window.FindName('NavIntune')
            NavNerdio = $Window.FindName('NavNerdio')
            NavInstall = $Window.FindName('NavInstall')
            NavSettings = $Window.FindName('NavSettings')
            NavAbout = $Window.FindName('NavAbout')
            OutputPathBox = $Window.FindName('OutputPathBox')
            PackagesPanel = $Window.FindName('PackagesPanel')
            IntunePanel = $Window.FindName('IntunePanel')
            NerdioPanel = $Window.FindName('NerdioPanel')
            InstallPanel = $Window.FindName('InstallPanel')
            SettingsPanel = $Window.FindName('SettingsPanel')
            AboutPanel = $Window.FindName('AboutPanel')
            IntuneTenantIdBox = $Window.FindName('IntuneTenantIdBox')
            UseIntuneDeviceCodeToggle = $Window.FindName('UseIntuneDeviceCodeToggle')
            ConnectIntuneButton = $Window.FindName('ConnectIntuneButton')
            DisconnectIntuneButton = $Window.FindName('DisconnectIntuneButton')
            IntuneConnectionStatusLabel = $Window.FindName('IntuneConnectionStatusLabel')
            CompareIntuneButton = $Window.FindName('CompareIntuneButton')
            IntuneComparisonListView = $Window.FindName('IntuneComparisonListView')
            PublishSelectedIntuneButton = $Window.FindName('PublishSelectedIntuneButton')
            CancelIntuneBatchButton = $Window.FindName('CancelIntuneBatchButton')
            IntunePublishResultsListView = $Window.FindName('IntunePublishResultsListView')
            RetryIntuneSupersedenceButton = $Window.FindName('RetryIntuneSupersedenceButton')
            IntuneDefinitionsPathBox = $Window.FindName('IntuneDefinitionsPathBox')
            BrowseIntuneDefinitionsButton = $Window.FindName('BrowseIntuneDefinitionsButton')
            SaveIntuneDefinitionsPathButton = $Window.FindName('SaveIntuneDefinitionsPathButton')
            PackageDefinitionsListView = $Window.FindName('PackageDefinitionsListView')
            PackageDefinitionsCountLabel = $Window.FindName('PackageDefinitionsCountLabel')
            LoadPackageDefinitionsButton = $Window.FindName('LoadPackageDefinitionsButton')
            UpdatePackageDefinitionsButton = $Window.FindName('UpdatePackageDefinitionsButton')
            PackageOutputPathBox = $Window.FindName('PackageOutputPathBox')
            BrowsePackageOutputPathButton = $Window.FindName('BrowsePackageOutputPathButton')
            SavePackageOutputPathButton = $Window.FindName('SavePackageOutputPathButton')
            InstallDefinitionsListView = $Window.FindName('InstallDefinitionsListView')
            InstallDefinitionsCountLabel = $Window.FindName('InstallDefinitionsCountLabel')
            InstallActionStatusLabel = $Window.FindName('InstallActionStatusLabel')
            HideIncompatibleInstallToggle = $Window.FindName('HideIncompatibleInstallToggle')
            ReloadInstallDefinitionsButton = $Window.FindName('ReloadInstallDefinitionsButton')
            ResolveInstallVersionsButton = $Window.FindName('ResolveInstallVersionsButton')
            InstallSelectedPackagesButton = $Window.FindName('InstallSelectedPackagesButton')
            QueueDownloadButton = $Window.FindName('QueueDownloadButton')
            RefreshAppsButton = $Window.FindName('RefreshAppsButton')
            RemoveQueuedDownloadButton = $Window.FindName('RemoveQueuedDownloadButton')
            SetLibraryPathButton = $Window.FindName('SetLibraryPathButton')
            SetOutputPathButton = $Window.FindName('SetOutputPathButton')
            SelectedAppText = $Window.FindName('SelectedAppText')
            StartDownloadButton = $Window.FindName('StartDownloadButton')
            StatusLabel = $Window.FindName('StatusLabel')
            SubtitleTextBlock = $Window.FindName('SubtitleTextBlock')
            ThemeCombo = $Window.FindName('ThemeCombo')
            UpdateLibraryButton = $Window.FindName('UpdateLibraryButton')
            ViewTitleText = $Window.FindName('ViewTitleText')
            AppsPanel = $Window.FindName('AppsPanel')
        })
    foreach ($name in @(
            'NerdioTenantIdBox', 'NmeSubscriptionIdBox', 'UseNerdioDeviceCodeToggle',
            'ConnectNerdioAzureButton', 'DisconnectNerdioButton', 'NmeResourceGroupCombo',
            'NmeStorageAccountCombo', 'NmeContainerCombo', 'NmeHostBox', 'NmeClientIdBox',
            'NmeApiScopeBox', 'NmeOAuthTokenUrlBox', 'NmeClientSecretBox', 'ConnectNerdioButton',
            'NerdioDefinitionsPathBox', 'BrowseNerdioDefinitionsButton', 'SaveNerdioSettingsButton',
            'NerdioApiOnlyToggle',
            'CompareNerdioButton', 'NerdioConnectionStatusLabel', 'NerdioComparisonListView',
            'CancelNerdioBatchButton', 'PublishSelectedNerdioButton', 'NerdioPublishResultsListView',
            'ReviewNerdioOutcomeButton', 'PruneNerdioVersionsButton'
        )) {
        $state[$name] = $Window.FindName($name)
    }
    foreach ($provider in 'Intune', 'Nerdio') {
        foreach ($suffix in 'Form', 'BrowseButton', 'PathBox', 'LoadButton', 'SaveButton', 'ConfigurationCombo',
            'ChannelCombo', 'CompanyBox', 'SessionCombo', 'TargetsButton', 'TargetCombo',
            'PreviewBuildButton', 'PreviewPublishButton', 'PreviewText', 'BuildButton', 'PublishButton',
            'CancelButton', 'ResultText') {
            $name = "${provider}M365$suffix"
            $state[$name] = $Window.FindName($name)
        }
    }
    foreach ($name in 'NerdioM365OperationCombo', 'NerdioM365NameBox', 'NerdioM365AttestToggle',
        'IntuneM365RecoveryCombo', 'IntuneM365RecoveryLoadButton', 'IntuneM365ReviewButton') {
        $state[$name] = $Window.FindName($name)
    }
    foreach ($name in @(
            'SettingsDownloadPathBox', 'SettingsLibraryPathBox', 'OpenDownloadFolderButton',
            'OpenLibraryFolderButton', 'DownloadFolderStatusLabel', 'LibraryFolderStatusLabel',
            'AboutNameValue', 'AboutVersionValue', 'AboutAuthorValue', 'AboutCompanyValue',
            'AboutCopyrightValue', 'AboutDescriptionValue', 'AboutProjectLink', 'AboutLicenseLink',
            'AboutLinkStatusLabel', 'RefreshAboutDependenciesButton', 'AboutDependencyStatusLabel',
            'AboutDependenciesListView'
        )) {
        $state[$name] = $Window.FindName($name)
    }
    Initialize-EwWorkbenchView -State $state
    Initialize-EwWorkbenchInfoView -State $state
    return $state
}
