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
            UiStateReady = $false
            PendingLastAppName = ''
            ArtifactFiltersPanel = $Window.FindName('ArtifactFiltersPanel')
            ArtifactControlsGrid = $Window.FindName('ArtifactControlsGrid')
            ArtifactActionsPanel = $Window.FindName('ArtifactActionsPanel')
            ArtifactCountLabel = $Window.FindName('ArtifactCountLabel')
            AppsListView = $Window.FindName('AppsListView')
            AppsListColumn = $Window.FindName('AppsListColumn')
            AppsSplitterColumn = $Window.FindName('AppsSplitterColumn')
            ArtifactsColumn = $Window.FindName('ArtifactsColumn')
            AppsListGridSplitter = $Window.FindName('AppsListGridSplitter')
            AppsQueueCountBadge = $Window.FindName('AppsQueueCountBadge')
            AppsQueueCountText = $Window.FindName('AppsQueueCountText')
            AppSearchBox = $Window.FindName('AppSearchBox')
            AppCountLabel = $Window.FindName('AppCountLabel')
            ArtifactsGrid = $Window.FindName('ArtifactsGrid')
            ExportArtifactsButton = $Window.FindName('ExportArtifactsButton')
            ShowArtifactColumnsButton = $Window.FindName('ShowArtifactColumnsButton')
            ActivityLog = $Window.FindName('ActivityLog')
            BrowseLibraryPathButton = $Window.FindName('BrowseLibraryPathButton')
            EvergreenMenuButton = $Window.FindName('EvergreenMenuButton')
            ClearCompletedQueueButton = $Window.FindName('ClearCompletedQueueButton')
            DownloadQueueListView = $Window.FindName('DownloadQueueListView')
            DownloadTrayToggleButton = $Window.FindName('DownloadTrayToggleButton')
            DownloadTrayContent = $Window.FindName('DownloadTrayContent')
            DownloadTrayGridSplitter = $Window.FindName('DownloadTrayGridSplitter')
            DownloadTrayPanel = $Window.FindName('DownloadTrayPanel')
            DownloadTrayActionButton = $Window.FindName('DownloadTrayActionButton')
            DownloadDestinationText = $Window.FindName('DownloadDestinationText')
            ChangeDownloadPathButton = $Window.FindName('ChangeDownloadPathButton')
            AppsPanel = $Window.FindName('AppsPanel')
            JobProgressBar = $Window.FindName('JobProgressBar')
            LibraryListView = $Window.FindName('LibraryListView')
            LibraryPanel = $Window.FindName('LibraryPanel')
            LibraryPathBox = $Window.FindName('LibraryPathBox')
            LibraryDetailsText = $Window.FindName('LibraryDetailsText')
            LibraryVersionsListView = $Window.FindName('LibraryVersionsListView')
            RemoveLibraryAppButton = $Window.FindName('RemoveLibraryAppButton')
            RemoveLibraryVersionsButton = $Window.FindName('RemoveLibraryVersionsButton')
            LoadedLibraryPath = ''
            LibraryJobPath = ''
            LibrarySelectedName = ''
            LibraryRemovalContext = $null
            LibraryPromptActive = $false
            LoadLibraryButton = $Window.FindName('LoadLibraryButton')
            NavApps = $Window.FindName('NavApps')
            NavLibrary = $Window.FindName('NavLibrary')
            NavPackages = $Window.FindName('NavPackages')
            NavIntune = $Window.FindName('NavIntune')
            NavNerdio = $Window.FindName('NavNerdio')
            NavSettings = $Window.FindName('NavSettings')
            NavAbout = $Window.FindName('NavAbout')
            PackagesPanel = $Window.FindName('PackagesPanel')
            PackagesTabControl = $Window.FindName('PackagesTabControl')
            DefinitionsTab = $Window.FindName('DefinitionsTab')
            InstallTab = $Window.FindName('InstallTab')
            IntunePanel = $Window.FindName('IntunePanel')
            NerdioPanel = $Window.FindName('NerdioPanel')
            InstallPanel = $Window.FindName('InstallPanel')
            SettingsPanel = $Window.FindName('SettingsPanel')
            AboutPanel = $Window.FindName('AboutPanel')
            IntuneTenantIdBox = $Window.FindName('IntuneTenantIdBox')
            UseIntuneDeviceCodeToggle = $Window.FindName('UseIntuneDeviceCodeToggle')
            ConnectIntuneButton = $Window.FindName('ConnectIntuneButton')
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
            DownloadNowButton = $Window.FindName('DownloadNowButton')
            SetLibraryPathButton = $Window.FindName('SetLibraryPathButton')
            SelectedAppText = $Window.FindName('SelectedAppText')
            StatusLabel = $Window.FindName('StatusLabel')
            SubtitleTextBlock = $Window.FindName('SubtitleTextBlock')
            ThemeCombo = $Window.FindName('ThemeCombo')
            UpdateLibraryButton = $Window.FindName('UpdateLibraryButton')
            ViewTitleText = $Window.FindName('ViewTitleText')
        })
    foreach ($name in @(
            'NerdioTenantIdBox', 'NmeSubscriptionIdBox', 'UseNerdioDeviceCodeToggle',
            'ConnectNerdioAzureButton', 'DisconnectNerdioButton', 'NmeResourceGroupCombo',
            'NmeStorageAccountCombo', 'NmeContainerCombo', 'NmeHostBox', 'NmeClientIdBox',
            'NmeApiScopeBox', 'NmeOAuthTokenUrlBox', 'NmeClientSecretBox', 'ConnectNerdioButton',
            'NerdioDefinitionsPathBox', 'BrowseNerdioDefinitionsButton',
            'SaveNerdioSettingsButton', 'SaveNerdioSetupButton',
            'NerdioApiOnlyToggle',
            'CompareNerdioButton', 'NerdioConnectionStatusLabel', 'NerdioComparisonListView',
            'CancelNerdioBatchButton', 'PublishSelectedNerdioButton', 'NerdioPublishResultsListView',
            'ReviewNerdioOutcomeButton', 'PruneNerdioVersionsButton', 'PruneSelectedNerdioVersionsButton'
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
            'SettingsDownloadPathBox', 'SettingsLibraryPathBox', 'BrowseDownloadFolderButton',
            'BrowseLibraryFolderButton', 'OpenDownloadFolderButton',
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
    Restore-EwWorkbenchStartupView -State $state
    return $state
}
