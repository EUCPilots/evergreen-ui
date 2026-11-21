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
            LoadLibraryButton = $Window.FindName('LoadLibraryButton')
            NavApps = $Window.FindName('NavApps')
            NavDownload = $Window.FindName('NavDownload')
            NavLibrary = $Window.FindName('NavLibrary')
            OutputPathBox = $Window.FindName('OutputPathBox')
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
    Initialize-EwWorkbenchView -State $state
    return $state
}
