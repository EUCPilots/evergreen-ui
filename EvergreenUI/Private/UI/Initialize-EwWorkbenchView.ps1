Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $State.AppSearchBox.Text = ''
    $State.OutputPathBox.Text = [string]$State.Settings.OutputPath
    $State.LibraryPathBox.Text = [string]$State.Settings.LibraryPath
    $State.DownloadQueueListView.ItemsSource = $State.Queue
    $State.ArtifactFilterControls = @{}
    $State.AllowFilterEvents = $true
    $State.SuppressAppSelection = $false
    $State.AppsLoading = $false
    $State.AppCatalog = @()
    $State.AllArtifacts = @()

    $State.NavApps.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Apps' }
    }.GetNewClosure())
    $State.NavDownload.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Download' }
    }.GetNewClosure())
    $State.NavLibrary.Add_Checked({
        & $State.ModuleInvoker -Name 'Show-EwWorkbenchView' -Parameters @{ State = $State; View = 'Library' }
    }.GetNewClosure())
    $State.AppSearchBox.Add_TextChanged({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchAppList' -Parameters @{ State = $State }
    }.GetNewClosure())
    $State.RefreshAppsButton.Add_Click({
        try {
            $State.AppsLoading = $true
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Apps'
                Name = 'Refresh application catalog'
                ScriptBlock = { Get-EwApp -Force }
            }
        }
        catch {
            $State.AppsLoading = $false
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.AppsListView.Add_SelectionChanged({
        if ($State.SuppressAppSelection -or $State.AppsLoading -or $null -eq $State.AppsListView.SelectedItem) {
            return
        }
        $selectedApp = $State.AppsListView.SelectedItem
        $State.CurrentApp = $selectedApp
        $State.CurrentAppName = [string]$selectedApp.Name
        $State.FavoriteAppButton.Content = if ($selectedApp.IsFavourite) { 'Remove favourite' } else { 'Add favourite' }
        $State.FavoriteAppButton.IsEnabled = $null -eq $State.ActiveJobId
        $State.SelectedAppText.Text = "Loading versions for $($selectedApp.FriendlyName)..."
        $State.AllArtifacts = @()
        $State.ArtifactsGrid.ItemsSource = @()
        $State.ArtifactFiltersPanel.Children.Clear()
        $State.ArtifactCountLabel.Text = 'Loading artifacts'
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Artifacts'
                Name = "Load $($selectedApp.Name) artifacts"
                ScriptBlock = {
                    param($AppName)
                    Get-EwApp -Name $AppName
                }
                ArgumentList = @([string]$selectedApp.Name)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.FavoriteAppButton.Add_Click({
        $selectedApp = $State.AppsListView.SelectedItem
        if ($null -eq $selectedApp) {
            return
        }
        try {
            $wasFavourite = [bool]$selectedApp.IsFavourite
            if ($wasFavourite) {
                & $State.ModuleInvoker -Name 'Remove-EwFavouriteApp' -Parameters @{ Name = $selectedApp.Name } | Out-Null
            }
            else {
                & $State.ModuleInvoker -Name 'Add-EwFavouriteApp' -Parameters @{ Name = $selectedApp.Name } | Out-Null
            }
            $State.AppCatalog = @(& $State.ModuleInvoker -Name 'Get-EwApp' -Parameters @{})
            $State.SuppressAppSelection = $true
            try {
                & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchAppList' -Parameters @{ State = $State }
                $State.AppsListView.SelectedItem = $State.AppCatalog |
                    Where-Object Name -eq $selectedApp.Name |
                    Select-Object -First 1
            }
            finally {
                $State.SuppressAppSelection = $false
            }
            $State.FavoriteAppButton.Content = if ($wasFavourite) { 'Add favourite' } else { 'Remove favourite' }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Updated favourite status for $($selectedApp.FriendlyName)."
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not update favourite status: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.ArtifactsGrid.Add_SelectionChanged({
        $State.QueueDownloadButton.IsEnabled = $State.ArtifactsGrid.SelectedItems.Count -gt 0 -and $null -eq $State.ActiveJobId
    }.GetNewClosure())
    $State.QueueDownloadButton.Add_Click({
        $selectedApp = $State.CurrentApp
        if ($null -eq $selectedApp) {
            return
        }
        foreach ($artifact in @($State.ArtifactsGrid.SelectedItems)) {
            $State.Queue.Add([PSCustomObject]@{
                    Id = [guid]::NewGuid().ToString()
                    AppName = [string]$selectedApp.Name
                    Version = [string]$artifact.Version
                    Artifact = $artifact
                    Status = 'Pending'
                    SavedPath = ''
                })
        }
        $State.StartDownloadButton.IsEnabled = @($State.Queue | Where-Object Status -eq 'Pending').Count -gt 0 -and $null -eq $State.ActiveJobId
        & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
            State = $State
            Message = "Added selected $($selectedApp.FriendlyName) artifacts to the download queue."
        }
    }.GetNewClosure())

    $State.ThemeCombo.SelectedItem = [string]$State.Settings.Theme
    $State.ThemeCombo.Add_SelectionChanged({
        $themeName = [string]$State.ThemeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($themeName)) {
            return
        }
        try {
            $State.Window.ThemeMode = switch ($themeName) {
                'Light' { [System.Windows.ThemeMode]::Light }
                'Dark' { [System.Windows.ThemeMode]::Dark }
                default { [System.Windows.ThemeMode]::System }
            }
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{ Name = 'Theme'; Value = $themeName }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = "Theme set to $themeName." }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not change the theme: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.BrowseOutputPathButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select the artifact download folder'
        if (-not [string]::IsNullOrWhiteSpace($State.OutputPathBox.Text) -and
            (Test-Path -LiteralPath $State.OutputPathBox.Text -PathType Container)) {
            $dialog.InitialDirectory = $State.OutputPathBox.Text
        }
        if ($dialog.ShowDialog($State.Window)) {
            $State.OutputPathBox.Text = $dialog.FolderName
        }
    }.GetNewClosure())
    $State.SetOutputPathButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{ Name = 'OutputPath'; Value = [string]$State.OutputPathBox.Text }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = 'Download location saved.' }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not save download location: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.BrowseLibraryPathButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select the Evergreen library folder'
        if (-not [string]::IsNullOrWhiteSpace($State.LibraryPathBox.Text) -and
            (Test-Path -LiteralPath $State.LibraryPathBox.Text -PathType Container)) {
            $dialog.InitialDirectory = $State.LibraryPathBox.Text
        }
        if ($dialog.ShowDialog($State.Window)) {
            $State.LibraryPathBox.Text = $dialog.FolderName
        }
    }.GetNewClosure())
    $State.SetLibraryPathButton.Add_Click({
        try {
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{ Name = 'LibraryPath'; Value = [string]$State.LibraryPathBox.Text }
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{ State = $State; Message = 'Library location saved.' }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not save library location: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.LoadLibraryButton.Add_Click({
        $libraryPath = [string]$State.LibraryPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Library'
                Name = 'Load Evergreen library'
                ScriptBlock = {
                    param($Path)
                    Get-EwLibrary -Path $Path
                }
                ArgumentList = @($libraryPath)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())
    $State.UpdateLibraryButton.Add_Click({
        $libraryPath = [string]$State.LibraryPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'LibraryUpdate'
                Name = 'Update Evergreen library'
                ScriptBlock = {
                    param($Path)
                    $update = Update-EwLibrary -Path $Path
                    $items = @(Get-EwLibrary -Path $Path)
                    [PSCustomObject]@{
                        Result = $update
                        Items = $items
                    }
                }
                ArgumentList = @($libraryPath)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.RemoveQueuedDownloadButton.Add_Click({
        foreach ($item in @($State.DownloadQueueListView.SelectedItems)) {
            $State.Queue.Remove($item)
        }
        $State.StartDownloadButton.IsEnabled = @($State.Queue | Where-Object Status -eq 'Pending').Count -gt 0 -and $null -eq $State.ActiveJobId
    }.GetNewClosure())
    $State.ClearQueueButton.Add_Click({
        foreach ($item in @($State.Queue | Where-Object Status -ne 'Pending')) {
            $State.Queue.Remove($item)
        }
    }.GetNewClosure())
    $State.StartDownloadButton.Add_Click({
        $items = @(
            foreach ($item in $State.Queue) {
                if ($item.Status -eq 'Pending') {
                    $item.Status = 'Downloading'
                    [PSCustomObject]@{
                        Id = $item.Id
                        AppName = $item.AppName
                        Version = $item.Version
                        Artifact = $item.Artifact
                    }
                }
            }
        )
        if ($items.Count -eq 0) {
            return
        }
        $State.DownloadQueueListView.Items.Refresh()
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'Downloads'
                Name = 'Download queued artifacts'
                ScriptBlock = {
                    param([object[]]$QueueItems)
                    foreach ($item in $QueueItems) {
                        try {
                            $saved = @(Save-EwArtifact -AppName $item.AppName -Artifact $item.Artifact)
                            if ($saved.Count -eq 0) {
                                throw "No saved file was returned for $($item.AppName) $($item.Version)."
                            }
                            [PSCustomObject]@{
                                QueueId = $item.Id
                                AppName = $item.AppName
                                Version = $item.Version
                                Succeeded = $true
                                Path = [string]$saved[0].Path
                                Error = ''
                            }
                        }
                        catch {
                            [PSCustomObject]@{
                                QueueId = $item.Id
                                AppName = $item.AppName
                                Version = $item.Version
                                Succeeded = $false
                                Path = ''
                                Error = $_.Exception.Message
                            }
                        }
                    }
                }
                ArgumentList = ,([object[]]$items)
            }
        }
        catch {
            foreach ($item in $State.Queue | Where-Object Status -eq 'Downloading') {
                $item.Status = 'Pending'
            }
            $State.DownloadQueueListView.Items.Refresh()
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    Show-EwWorkbenchView -State $State -View 'Apps'
}
