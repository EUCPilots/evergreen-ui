function Register-WindowLifetime {
    <#
    .SYNOPSIS
    Registers event handlers for window loading, closing, and lifecycle management.

    .DESCRIPTION
    Sets up the window.Loaded event to initialize UI state after XAML is displayed,
    and the window.Closed event to clean up async operations, close runspaces, and
    persist final configuration. This handler is responsible for orchestrating the
    startup initialization sequence (loading app catalog, restoring config, initializing
    auth UI) and shutdown cleanup to prevent orphaned runspaces or disposed dispatcher
    exceptions.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls.

    .PARAMETER Window
    The WPF Window object.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    This is the only feature handler that manages both startup and shutdown.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls,
        [System.Windows.Window]$Window
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $getControl = {
        param([string]$Name)
        if ($Controls.ContainsKey($Name) -and $null -ne $Controls[$Name]) { return $Controls[$Name] }
        return $Window.FindName($Name)
    }
    $themeComboBox = & $getControl 'ThemeComboBox'
    $evergreenVersionText = & $getControl 'EvergreenVersionText'
    $evergreenStatusDot = & $getControl 'EvergreenStatusDot'
    $appsListBox = & $getControl 'AppsListBox'
    $outputPathBox = & $getControl 'OutputPathBox'
    $libraryPathViewBox = & $getControl 'LibraryPathViewBox'
    $importTenantIdBox = & $getControl 'ImportTenantIdBox'
    $nerdioTenantIdBox = & $getControl 'NerdioTenantIdBox'
    $showImportTabToggle = & $getControl 'ShowImportTabToggle'
    $showInstallTabToggle = & $getControl 'ShowInstallTabToggle'
    $installArchitectureToggle = & $getControl 'InstallHideIncompatibleArchitectureToggle'
    $m365ConfigPathBox = & $getControl 'M365ConfigPathBox'
    $m365ChannelCombo = & $getControl 'M365ChannelCombo'
    $m365CompanyNameBox = & $getControl 'M365CompanyNameBox'
    $m365ImportForCombo = & $getControl 'M365ImportForCombo'
    $navApps = & $getControl 'NavApps'
    $navDownload = & $getControl 'NavDownload'
    $navLibrary = & $getControl 'NavLibrary'
    $navPackages = & $getControl 'NavPackages'
    $navImport = & $getControl 'NavImport'
    $navInstall = & $getControl 'NavInstall'
    $navSettings = & $getControl 'NavSettings'
    $navUpdate = & $getControl 'NavUpdate'
    $navAbout = & $getControl 'NavAbout'

    $writeStartupLog = {
        param([string]$Message, [string]$Level = 'Info')
        try {
            $dispatcher = $Window.Dispatcher
            if ($null -ne $dispatcher -and -not $dispatcher.HasShutdownStarted -and -not $dispatcher.HasShutdownFinished) {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message $Message -Level $Level
            }
        }
        catch { Write-Verbose -Message "EvergreenUI: Startup log dispatch failed: $($_.Exception.Message)" }
    }.GetNewClosure()
    $invokeSyncHelper = {
        param([string]$Name, [object[]]$Arguments = @())
        if (-not $SyncHash.ContainsKey($Name) -or $null -eq $SyncHash[$Name]) {
            Write-Verbose -Message "EvergreenUI: Startup helper '$Name' is not registered."
            return
        }
        try { & ($SyncHash[$Name]) @Arguments }
        catch {
            & $writeStartupLog -Message "Startup helper '$Name' failed: $($_.Exception.Message)" -Level Error
            Write-Verbose -Message "EvergreenUI: Startup helper '$Name' failed: $($_.Exception.Message)"
        }
    }.GetNewClosure()

        $Window.add_Loaded({
            $SyncHash['IsInitializing'] = $true
            try {
                if ([string]$SyncHash.Config.Theme -eq 'Dark') {
                    if ($null -ne $themeComboBox) { $themeComboBox.SelectedIndex = 1 }
                    & ($SyncHash['SetDarkTheme']) -Window $Window
                }
                else {
                    if ($null -ne $themeComboBox) { $themeComboBox.SelectedIndex = 0 }
                    & ($SyncHash['SetLightTheme']) -Window $Window
                }
            }
            catch { Write-Verbose -Message "EvergreenUI: Could not apply saved theme: $($_.Exception.Message)" }

            try {
                if ($null -ne $evergreenVersionText) { $evergreenVersionText.Text = 'Evergreen: loading...' }
                if ($null -ne $evergreenStatusDot) { $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::Gold }
                Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                $module = Get-Module -Name Evergreen -ListAvailable -ErrorAction Stop | Sort-Object -Property Version | Select-Object -Last 1
                if ($null -ne $module) {
                    $SyncHash.EvergreenVersion = "v$($module.Version)"
                    $SyncHash.EvergreenModuleLoaded = $true
                    if ($null -ne $evergreenVersionText) { $evergreenVersionText.Text = "Evergreen $($SyncHash.EvergreenVersion)" }
                    if ($null -ne $evergreenStatusDot) { $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen }
                    & $writeStartupLog -Message "Evergreen module $($SyncHash.EvergreenVersion) loaded."
                }
                else {
                    $SyncHash.EvergreenModuleLoaded = $false
                    if ($null -ne $evergreenVersionText) { $evergreenVersionText.Text = 'Evergreen: not loaded' }
                    if ($null -ne $evergreenStatusDot) { $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed }
                    & $writeStartupLog -Message 'Evergreen module loaded but no installed version was found.' -Level Warning
                }
            }
            catch {
                $SyncHash.EvergreenModuleLoaded = $false
                if ($null -ne $evergreenVersionText) { $evergreenVersionText.Text = 'Evergreen: failed to load' }
                if ($null -ne $evergreenStatusDot) { $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed }
                & $writeStartupLog -Message "Failed to load Evergreen module: $($_.Exception.Message)" -Level Error
            }
            & $writeStartupLog -Message "EvergreenUI started. $([string]$SyncHash.EvergreenVersion)"
            & $invokeSyncHelper -Name 'LoadAppCatalog'

            if ($null -ne $appsListBox -and [string]$SyncHash.Config.LastAppName -ne '' -and $null -ne $SyncHash.AppList) {
                try {
                    $savedApp = @($SyncHash.AppList | Where-Object { $_.Name -eq $SyncHash.Config.LastAppName } | Select-Object -First 1)
                    if ($savedApp.Count -gt 0) {
                        $appsListBox.SelectedItem = $savedApp[0]
                        $appsListBox.ScrollIntoView($savedApp[0])
                    }
                }
                catch { Write-Verbose -Message "EvergreenUI: Could not restore selected app: $($_.Exception.Message)" }
            }

            if ($null -ne $outputPathBox) { $outputPathBox.Text = [string]$SyncHash.Config.OutputPath }
            if ($null -ne $libraryPathViewBox) { $libraryPathViewBox.Text = [string]$SyncHash.Config.LibraryPath }
            if ($null -ne $importTenantIdBox) { $importTenantIdBox.Text = [string]$SyncHash.Config.AzureAuthSettings.TenantId }
            if ($null -ne $nerdioTenantIdBox) { $nerdioTenantIdBox.Text = [string]$SyncHash.Config.AzureAuthSettings.NerdioTenantId }
            if ($null -ne $showImportTabToggle) { $showImportTabToggle.IsChecked = [bool]$SyncHash.Config.ShowImportTab }
            if ($null -ne $showInstallTabToggle) { $showInstallTabToggle.IsChecked = [bool]$SyncHash.Config.ShowInstallTab }
            if ($null -ne $installArchitectureToggle) { $installArchitectureToggle.IsChecked = [bool]$SyncHash.Config.InstallSettings.HideIncompatibleArchitecture }
            if ($null -ne $m365ConfigPathBox -and $null -ne $SyncHash.Config.M365Settings) { $m365ConfigPathBox.Text = [string]$SyncHash.Config.M365Settings.DefinitionsPath }
            if ($null -ne $m365CompanyNameBox -and $null -ne $SyncHash.Config.M365Settings) { $m365CompanyNameBox.Text = [string]$SyncHash.Config.M365Settings.CompanyName }
            if ($null -ne $m365ChannelCombo -and $null -ne $SyncHash.Config.M365Settings) {
                $item = @($m365ChannelCombo.Items | Where-Object { $_.Content -eq [string]$SyncHash.Config.M365Settings.Channel } | Select-Object -First 1)
                if ($item.Count -gt 0) { $m365ChannelCombo.SelectedItem = $item[0] }
            }
            if ($null -ne $m365ImportForCombo -and $null -ne $SyncHash.Config.M365Settings) {
                $importFor = [string]$SyncHash.Config.M365Settings.ImportFor
                if ([string]::IsNullOrWhiteSpace($importFor)) { $importFor = 'Single session' }
                $item = @($m365ImportForCombo.Items | Where-Object { $_.Content -eq $importFor } | Select-Object -First 1)
                if ($item.Count -gt 0) { $m365ImportForCombo.SelectedItem = $item[0] }
            }
            & $invokeSyncHelper -Name 'SetImportTabVisibility' -Arguments @([bool]$SyncHash.Config.ShowImportTab, [bool]$SyncHash.Config.ShowInstallTab)
            foreach ($authHelper in @('RefreshImportAuthUi', 'RefreshNerdioApiAuthUi', 'RefreshNerdioAzureAuthUi')) { & $invokeSyncHelper -Name $authHelper }
            & $invokeSyncHelper -Name 'SetImportProvider' -Arguments @([string]$SyncHash.Config.ImportSettings.CurrentProvider)
            & $invokeSyncHelper -Name 'SetInstallElevationState'
            & $invokeSyncHelper -Name 'RefreshLibraryView'
            & $invokeSyncHelper -Name 'RefreshQueueView'
            & $writeStartupLog -Message 'EvergreenUI startup initialization completed.'

            $startupButton = switch ([string]$SyncHash.Config.StartupView) {
                'Download' { $navDownload }
                'Library'  { $navLibrary }
                'Packages' { $navPackages }
                'Import'   { if ([bool]$SyncHash.Config.ShowImportTab) { $navImport } else { $navApps } }
                'Install'  { if ([bool]$SyncHash.Config.ShowInstallTab) { $navInstall } else { $navApps } }
                'Settings' { $navSettings }
                'Update'   { $navUpdate }
                'About'    { $navAbout }
                default    { $navApps }
            }
            if ($null -ne $startupButton) { $startupButton.IsChecked = $true }
            [void]$Window.Dispatcher.BeginInvoke([action] {
                    $SyncHash['IsInitializing'] = $false
                }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        }.GetNewClosure())

    $Window.add_Closed({
            # WPF may already be shutting down its dispatcher. Every cleanup step
            # is isolated so one failed resource cannot strand the remaining ones.
            try {
                $SyncHash.IsClosing = $true
                if ($null -ne $SyncHash.Config) {
                    $SyncHash.Config.WindowWidth = [int]$Window.Width
                    $SyncHash.Config.WindowHeight = [int]$Window.Height
                    foreach ($entry in @(@{ Name = 'WindowLeft'; Value = $Window.Left }, @{ Name = 'WindowTop'; Value = $Window.Top })) {
                        if ($null -eq $SyncHash.Config.PSObject.Properties[$entry.Name]) { $SyncHash.Config | Add-Member -NotePropertyName $entry.Name -NotePropertyValue ([double]$entry.Value) }
                        else { $SyncHash.Config.($entry.Name) = [double]$entry.Value }
                    }
                    $currentButton = @($navApps, $navDownload, $navLibrary, $navPackages, $navImport, $navInstall, $navSettings, $navUpdate, $navAbout) | Where-Object { $null -ne $_ -and $_.IsChecked } | Select-Object -First 1
                    if ($null -ne $currentButton) { $SyncHash.Config.StartupView = ([string]$currentButton.Name).Replace('Nav', '') }
                    & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                }
            }
            catch { Write-Verbose -Message "EvergreenUI: Final config save failed: $($_.Exception.Message)" }

            # Stop named timers and timers attached to operation records before
            # disposing their runspaces. This prevents late dispatcher callbacks.
            $timers = @($SyncHash.Keys | Where-Object { $_ -like '*Timer' } | ForEach-Object { $SyncHash[$_] })
            if ($SyncHash.ContainsKey('Operations') -and $null -ne $SyncHash.Operations) {
                $timers += $SyncHash.Operations.PollingTimer
                if ($null -ne $SyncHash.Operations.Registry) { $timers += @($SyncHash.Operations.Registry.Values | ForEach-Object { $_.Timer }) }
            }
            foreach ($timer in @($timers | Where-Object { $null -ne $_ } | Select-Object -Unique)) {
                try { if ($timer.IsEnabled) { $timer.Stop() } }
                catch { Write-Verbose -Message "EvergreenUI: Timer cleanup failed: $($_.Exception.Message)" }
            }

            # Cancel, drain, and dispose each registered operation. EndInvoke is
            # attempted even after Stop because PowerShell uses it to release the
            # async pipeline and its event subscriptions.
            $operations = if ($SyncHash.ContainsKey('Operations')) { $SyncHash.Operations.Registry } else { $null }
            if ($null -ne $operations) {
                foreach ($key in @($operations.Keys)) {
                    $operation = $operations[$key]
                    try { if ($null -ne $operation.PowerShell) { $operation.PowerShell.Stop() } } catch { Write-Verbose -Message "EvergreenUI: Could not cancel '$key': $($_.Exception.Message)" }
                    try { if ($null -ne $operation.AsyncResult) { [void]$operation.PowerShell.EndInvoke($operation.AsyncResult) } } catch { Write-Verbose -Message "EvergreenUI: EndInvoke for '$key' reported: $($_.Exception.Message)" }
                    try { if ($null -ne $operation.PowerShell) { $operation.PowerShell.Dispose() } } catch { Write-Verbose -Message "EvergreenUI: PowerShell dispose for '$key' failed: $($_.Exception.Message)" }
                    try {
                        if ($null -ne $operation.Runspace) {
                            $isRunspaceOpen = $false
                            try { $isRunspaceOpen = [bool]$operation.Runspace.IsRunspaceOpen }
                            catch { $isRunspaceOpen = $operation.Runspace.RunspaceStateInfo.State -ne 'Closed' }
                            if ($isRunspaceOpen) { $operation.Runspace.Close() }
                            $operation.Runspace.Dispose()
                        }
                    }
                    catch { Write-Verbose -Message "EvergreenUI: Runspace dispose for '$key' failed: $($_.Exception.Message)" }
                    [void]$operations.Remove($key)
                }
            }

            # Legacy feature paths retain direct Pending* references. They are
            # drained as well so migration cannot leak a runspace on shutdown.
            foreach ($name in @($SyncHash.Keys | Where-Object { $_ -like 'Pending*PS' })) {
                $ps = $SyncHash[$name]
                $suffix = $name.Substring(7, $name.Length - 9)
                $asyncName = "Pending${suffix}Async"
                $runspaceName = "Pending${suffix}Runspace"
                try { if ($null -ne $ps) { $ps.Stop() } } catch { Write-Verbose -Message "EvergreenUI: Could not stop '$name': $($_.Exception.Message)" }
                try { if ($null -ne $ps -and $SyncHash.ContainsKey($asyncName) -and $null -ne $SyncHash[$asyncName]) { [void]$ps.EndInvoke($SyncHash[$asyncName]) } } catch { Write-Verbose -Message "EvergreenUI: EndInvoke for '$name' reported: $($_.Exception.Message)" }
                try { if ($null -ne $ps) { $ps.Dispose() } } catch { Write-Verbose -Message "EvergreenUI: Dispose for '$name' failed: $($_.Exception.Message)" }
                if ($SyncHash.ContainsKey($runspaceName)) {
                    try { if ($null -ne $SyncHash[$runspaceName]) { $SyncHash[$runspaceName].Dispose() } } catch { Write-Verbose -Message "EvergreenUI: Runspace dispose for '$runspaceName' failed: $($_.Exception.Message)" }
                }
            }
            Write-Verbose 'EvergreenUI: Window shutdown cleanup completed.'
            $SyncHash.Clear()
        }.GetNewClosure())

    Write-Verbose 'EvergreenUI: Window lifetime handlers registered.'
}
