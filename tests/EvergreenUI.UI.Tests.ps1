#Requires -Version 7.6

BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force

    $waitForInfoJob = {
        param($State, [string]$Kind)

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInfoJobMonitor' -Parameters @{ State = $State }
            if ($null -eq $State.InfoJobs[$Kind].ActiveId -and $null -eq $State.InfoJobs[$Kind].Pending) {
                return
            }
            Start-Sleep -Milliseconds 50
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "The $Kind information check did not finish in time."
    }

    # Captures the window into memory and samples a blank caption pixel and a blank form pixel.
    $getCaptionSample = {
        param([System.Windows.Window]$Window)
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        if (-not ('EvergreenUI.ThemeProbe' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace EvergreenUI {
    [StructLayout(LayoutKind.Sequential)]
    public struct WindowRectangle {
        public int Left, Top, Right, Bottom;
    }
    public static class ThemeProbe {
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hwnd, out WindowRectangle rectangle);
        [DllImport("user32.dll")]
        public static extern bool PrintWindow(IntPtr hwnd, IntPtr deviceContext, uint flags);
        [DllImport("dwmapi.dll")]
        public static extern int DwmFlush();
    }
}
"@ -ErrorAction Stop
        }
        $Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
        $rectangle = [EvergreenUI.WindowRectangle]::new()
        if (-not [EvergreenUI.ThemeProbe]::GetWindowRect($handle, [ref]$rectangle)) { throw 'GetWindowRect failed.' }
        $bitmap = [System.Drawing.Bitmap]::new($rectangle.Right - $rectangle.Left, $rectangle.Bottom - $rectangle.Top)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $scale = [System.Windows.Media.VisualTreeHelper]::GetDpi($Window).DpiScaleX
            # Native colour transitions are asynchronous, so poll briefly for a settled frame.
            $deadline = [DateTime]::UtcNow.AddSeconds(2)
            do {
                $Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $null = [EvergreenUI.ThemeProbe]::DwmFlush()
                $deviceContext = $graphics.GetHdc()
                try {
                    if (-not [EvergreenUI.ThemeProbe]::PrintWindow($handle, $deviceContext, 2)) { throw 'PrintWindow failed.' }
                }
                finally {
                    $graphics.ReleaseHdc($deviceContext)
                }
                $caption = $bitmap.GetPixel([int]($bitmap.Width - 170 * $scale), [int](20 * $scale))
                $form = $bitmap.GetPixel([int]($bitmap.Width - 20 * $scale), [int](150 * $scale))
                if ($caption.ToArgb() -eq $form.ToArgb()) { break }
                Start-Sleep -Milliseconds 20
            }
            while ([DateTime]::UtcNow -lt $deadline)
            [PSCustomObject]@{ Caption = $caption; Form = $form }
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
}

AfterAll {
    Remove-Module EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Evergreen Workbench WPF shell' {
    It 'keeps WPF assemblies unloaded when the interface is declined with WhatIf' {
        InModuleScope EvergreenUI {
            $loadedBefore = @(
                [AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq 'PresentationFramework' }
            ).Count
            Start-EvergreenWorkbench -WhatIf
            $loadedAfter = @(
                [AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq 'PresentationFramework' }
            ).Count
            $loadedAfter | Should -Be $loadedBefore
        }
    }

    It 'loads the v2 XAML and exposes named controls on an STA thread' {
        InModuleScope EvergreenUI {
            [System.Threading.Thread]::CurrentThread.GetApartmentState() | Should -Be ([System.Threading.ApartmentState]::STA)
            $window = Get-EwWorkbenchWindow
            try {
                foreach ($name in @(
                        'NavApps', 'NavDownload', 'NavLibrary',
                        'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall', 'NavSettings', 'NavAbout',
                        'AppsPanel', 'DownloadPanel', 'LibraryPanel', 'PackagesPanel', 'IntunePanel', 'NerdioPanel', 'InstallPanel',
                        'SettingsPanel', 'AboutPanel', 'SettingsDownloadPathBox', 'SettingsLibraryPathBox',
                        'OpenDownloadFolderButton', 'OpenLibraryFolderButton', 'AboutDependenciesListView',
                        'RefreshAboutDependenciesButton', 'AboutProjectLink', 'AboutLicenseLink',
                        'AppSearchBox', 'AppCountLabel', 'AppsListView', 'ArtifactsGrid',
                        'DownloadQueueListView', 'LibraryListView', 'LibraryVersionsListView',
                        'PackageDefinitionsListView', 'InstallDefinitionsListView',
                        'LoadPackageDefinitionsButton', 'UpdatePackageDefinitionsButton',
                        'ReloadInstallDefinitionsButton', 'ResolveInstallVersionsButton',
                        'InstallSelectedPackagesButton', 'ConnectIntuneButton', 'CompareIntuneButton',
                        'IntuneComparisonListView', 'PublishSelectedIntuneButton', 'CancelIntuneBatchButton',
                        'IntunePublishResultsListView', 'RetryIntuneSupersedenceButton', 'ThemeCombo', 'ActivityLog'
                    )) {
                    $window.FindName($name) | Should -Not -BeNullOrEmpty
                }

                $window.ThemeMode.ToString() | Should -Be 'System'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'switches views and filters artifacts using dropdowns for all property sizes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavDownload.IsChecked = $true
                $state.DownloadPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Collapsed'

                $state.AllArtifacts = @(
                    foreach ($index in 1..24) {
                        [PSCustomObject]@{
                            Version = "$index.0"
                            Architecture = if ($index % 2 -eq 0) { 'x64' } else { 'x86' }
                            Channel = "channel$((($index - 1) % 8) + 1)"
                            Language = "language$index"
                            Track = "track$index"
                            Category = if ($index -eq 1) { 'All' } else { 'Other' }
                            URI = if ($index % 4 -eq 0) { "https://example.test/app$index.exe" } else { "https://example.test/app$index.msi" }
                        }
                    }
                )
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                foreach ($filter in $state.ArtifactFilterControls.Values) {
                    $filter.Control | Should -BeOfType ([System.Windows.Controls.ComboBox])
                    $filter.Control.SelectedIndex | Should -Be 0
                    $filter.Control.SelectedItem | Should -Be 'All'
                }
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                $architectureFilter = $state.ArtifactFilterControls['Architecture']
                $architectureFilter.Control.SelectedItem = 'x64'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 12
                $channelFilter = $state.ArtifactFilterControls['Channel']
                $channelFilter.Control.SelectedItem = 'channel8'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 3
                $typeFilter = $state.ArtifactFilterControls['_DerivedType']
                $typeFilter.Control.SelectedItem = 'msi'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 0
                $typeFilter.Control.SelectedIndex = 0
                $channelFilter.Control.SelectedIndex = 0
                $architectureFilter.Control.SelectedIndex = 0
                $state.ArtifactFilterControls['Track'].Control.SelectedItem = 'track1'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1
                $state.ArtifactFilterControls['Track'].Control.SelectedIndex = 0
                $categoryFilter = $state.ArtifactFilterControls['Category'].Control
                $categoryFilter.SelectedIndex = 1
                $categoryFilter.SelectedItem | Should -Be 'All'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1
                $categoryFilter.SelectedIndex = 0
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                $architectureFilter.Control.SelectedItem = 'x64'
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                $state.ArtifactFilterControls['Architecture'].Control.SelectedIndex | Should -Be 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses the theme foreground for unselected sidebar items across light and dark modes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                foreach ($mode in 'Light', 'Dark', 'Light') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    foreach ($name in 'NavDownload', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall', 'NavSettings', 'NavAbout') {
                        $window.FindName($name).Foreground.Color |
                            Should -Be $window.TryFindResource('TextFillColorPrimaryBrush').Color
                    }
                    $window.FindName('NavApps').Foreground.Color |
                        Should -Be ([System.Windows.Media.Colors]::White)
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'matches the native caption to the form when the window first loads' {
        if ([Environment]::OSVersion.Version.Build -lt 22000) {
            Set-ItResult -Skipped -Because 'Native caption colour overrides require Windows 11.'
            return
        }
        InModuleScope EvergreenUI -Parameters @{ Sample = $getCaptionSample } {
            param($Sample)
            # Light exposes a missed override because the native light caption differs from the form.
            $window = Get-EwWorkbenchWindow
            $window.ThemeMode = [System.Windows.ThemeMode]::Light
            try {
                $window.Show()
                $result = & $Sample -Window $window
                $result.Caption.ToArgb() | Should -Be $result.Form.ToArgb() -Because 'the caption should match the form on load'
                $color = $window.TryFindResource('ApplicationBackgroundBrush').Color
                $result.Form.R | Should -Be $color.R
                $result.Form.G | Should -Be $color.G
                $result.Form.B | Should -Be $color.B
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'matches the native caption to the form across light and dark theme changes' {
        if ([Environment]::OSVersion.Version.Build -lt 22000) {
            Set-ItResult -Skipped -Because 'Native caption colour overrides require Windows 11.'
            return
        }
        InModuleScope EvergreenUI -Parameters @{ Sample = $getCaptionSample } {
            param($Sample)
            $window = Get-EwWorkbenchWindow
            $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
            Mock Set-EwSetting {}
            try {
                $window.Show()
                foreach ($mode in 'Light', 'Dark', 'Light', 'System') {
                    $state.ThemeCombo.SelectedItem = $mode
                    $result = & $Sample -Window $window
                    $result.Caption.ToArgb() | Should -Be $result.Form.ToArgb() -Because "the $mode caption should match the form"
                    $color = $window.TryFindResource('ApplicationBackgroundBrush').Color
                    $result.Form.R | Should -Be $color.R
                    $result.Form.G | Should -Be $color.G
                    $result.Form.B | Should -Be $color.B
                }
            }
            finally {
                $window.Close()
            }
        }
    }
    It 'starts loading package definitions through the shared job API' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneDefinitionsPathBox.Text = 'C:\Definitions'
                Mock Start-EwJob {
                    [PSCustomObject]@{
                        Id = [guid]::NewGuid()
                        Name = 'Load Intune package definitions'
                    }

                }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.LoadPackageDefinitionsButton.RaiseEvent($eventArgs)
                $state.ActiveJobKind | Should -Be 'PackageDefinitions'
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Load Intune package definitions' }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'does not publish when Intune batch confirmation is declined' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonRoot = 'C:\Definitions'
                $state.Settings.IntuneDefinitionsPath = 'C:\Definitions'
                $state.Settings.PackageOutputPath = 'C:\Packages'
                $item = [PSCustomObject]@{
                    DefinitionName = 'App'; DefinitionPath = 'C:\Definitions\App\App.json'
                    MatchStatus = 'Matched (current)'; IntuneAppId = 'old-id'; ImportAsUpdate = $false
                }
                $state.IntuneComparisonListView.ItemsSource = @($item)
                $state.IntuneComparisonListView.SelectedItem = $item
                Mock Confirm-EwWorkbenchIntuneBatch { $false }
                Mock Start-EwJob {}
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.PublishSelectedIntuneButton.RaiseEvent($eventArgs)
                Should -Invoke Confirm-EwWorkbenchIntuneBatch -Exactly 1
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps architecture and download URI in queued artifact rows' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.CurrentApp = [PSCustomObject]@{
                    Name = 'ContosoApp'
                    FriendlyName = 'Contoso App'
                }
                $artifact = [PSCustomObject]@{
                    Version = '2.0'
                    Architecture = 'x64'
                    URI = 'https://example.test/contoso.msi'
                }
                $state.ArtifactsGrid.ItemsSource = @($artifact)
                $state.ArtifactsGrid.SelectedItem = $artifact
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.QueueDownloadButton.RaiseEvent($eventArgs)
                $state.Queue.Count | Should -Be 1
                $state.Queue[0].Architecture | Should -Be 'x64'
                $state.Queue[0].URI | Should -Be 'https://example.test/contoso.msi'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'defaults package output to the saved download path and persists an explicit package path' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.Settings.PackageOutputPath = ''
                $state.OutputPathBox.Text = 'C:\Downloads'
                Mock Set-EwSetting {}
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.SetOutputPathButton.RaiseEvent($eventArgs)
                $state.PackageOutputPathBox.Text | Should -Be 'C:\Downloads'

                $state.PackageOutputPathBox.Text = 'C:\Packages'
                $state.SavePackageOutputPathButton.RaiseEvent($eventArgs)
                $state.Settings.PackageOutputPath | Should -Be 'C:\Packages'
                Should -Invoke Set-EwSetting -Exactly 1 -ParameterFilter { $Name -eq 'OutputPath' }
                Should -Invoke Set-EwSetting -Exactly 1 -ParameterFilter { $Name -eq 'PackageOutputPath' }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'shows version metadata when a library application is selected' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $application = [PSCustomObject]@{
                    Name = 'Contoso App'
                    SourceItem = [PSCustomObject]@{
                        Versions = @(
                            [PSCustomObject]@{
                                Version = '2.0'
                                Architecture = 'x64'
                                Type = 'msi'
                                URI = 'https://example.test/contoso.msi'
                            }
                        )
                    }
                }
                $state.LibraryListView.ItemsSource = @($application)
                $state.LibraryListView.SelectedItem = $application
                $state.LibraryDetailsText.Text | Should -Be 'Versions for Contoso App: 1'
                $version = $state.LibraryVersionsListView.ItemsSource[0]
                $version.Architecture | Should -Be 'x64'
                $version.URI | Should -Be 'https://example.test/contoso.msi'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'does not start an install job when the batch confirmation is declined' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $definition = [PSCustomObject]@{
                    Name = 'Contoso App'
                    DefinitionPath = 'C:\Definitions\Contoso\App.json'
                    DefinitionValid = 'Yes'
                }
                $state.InstallDefinitions.Add($definition)
                $state.InstallDefinitionsListView.SelectedItem = $definition
                Mock Confirm-EwWorkbenchInstallBatch { $false }
                Mock Start-EwJob {}
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.InstallSelectedPackagesButton.RaiseEvent($eventArgs)
                Should -Invoke Confirm-EwWorkbenchInstallBatch -Exactly 1
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'starts one shared job after an install batch is confirmed' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $definition = [PSCustomObject]@{
                    Name = 'Contoso App'
                    DefinitionPath = 'C:\Definitions\Contoso\App.json'
                    DefinitionValid = 'Yes'
                }
                $state.InstallDefinitions.Add($definition)
                $state.InstallDefinitionsListView.SelectedItem = $definition
                Mock Confirm-EwWorkbenchInstallBatch { $true }
                Mock Start-EwJob {
                    [PSCustomObject]@{
                        Id = [guid]::NewGuid()
                        Name = 'Install selected applications'
                    }
                }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.InstallSelectedPackagesButton.RaiseEvent($eventArgs)
                $state.ActiveJobKind | Should -Be 'InstallPackages'
                Should -Invoke Confirm-EwWorkbenchInstallBatch -Exactly 1
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Install selected applications' }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'applies each install result to its definition row' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $successfulPath = 'C:\Definitions\Contoso\App.json'
                $failedPath = 'C:\Definitions\Fabrikam\App.json'
                $successfulDefinition = [PSCustomObject]@{
                    Name = 'Contoso App'
                    DefinitionPath = $successfulPath
                    DefinitionValid = 'Yes'
                    IsInstalled = $false
                    InstalledVersion = ''
                    LatestVersion = ''
                    InstallStatus = 'Not installed'
                    InstallAction = 'Install'
                    Error = ''
                }
                $failedDefinition = [PSCustomObject]@{
                    Name = 'Fabrikam App'
                    DefinitionPath = $failedPath
                    DefinitionValid = 'Yes'
                    IsInstalled = $false
                    InstalledVersion = ''
                    LatestVersion = ''
                    InstallStatus = 'Not installed'
                    InstallAction = 'Install'
                    Error = ''
                }
                $state.InstallDefinitions.Add($successfulDefinition)
                $state.InstallDefinitions.Add($failedDefinition)
                $jobId = [guid]::NewGuid()
                $state.ActiveJobId = $jobId
                $state.ActiveJobKind = 'InstallPackages'
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id
                        Progress = @()
                        Information = @()
                        Errors = @()
                        Output = @(
                            [PSCustomObject]@{
                                Name = 'Contoso App'
                                DefinitionPath = $successfulPath
                                Succeeded = $true
                                DownloadedVersion = '2.0'
                                Error = ''
                            }
                            [PSCustomObject]@{
                                Name = 'Fabrikam App'
                                DefinitionPath = $failedPath
                                Succeeded = $false
                                DownloadedVersion = ''
                                Error = 'Installer exited with code 1.'
                            }
                        )
                        TerminatingError = $null
                        State = 'Completed'
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $successfulDefinition.IsInstalled | Should -BeTrue
                $successfulDefinition.InstalledVersion | Should -Be '2.0'
                $failedDefinition.InstallStatus | Should -Be 'Installation failed'
                $failedDefinition.Error | Should -Be 'Installer exited with code 1.'
                $state.ActiveJobId | Should -BeNullOrEmpty
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'starts catalog work through the shared job API' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-EwJob {
                    [PSCustomObject]@{
                        Id = [guid]::NewGuid()
                        Name = 'Refresh application catalog'
                    }
                }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.RefreshAppsButton.RaiseEvent($eventArgs)
                $state.ActiveJobKind | Should -Be 'Apps'
                $state.ActiveJobId | Should -BeOfType ([guid])
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Refresh application catalog' }
            }
            finally {
                $window.Close()
            }
        }
    }
}

Describe 'Workbench Settings and About' {
    BeforeEach {
        $originalAppData = $env:APPDATA
        $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
    }

    AfterEach {
        $env:APPDATA = $originalAppData
    }

    It 'navigates to Settings and About without hiding existing views' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Invoke-EwWorkbenchSettingsRefresh {}
                Mock Invoke-EwWorkbenchAboutRefresh {}
                $state.NavSettings.IsChecked = $true
                $state.SettingsPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Collapsed'
                $state.NavAbout.IsChecked = $true
                $state.AboutPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.SettingsPanel.Visibility.ToString() | Should -Be 'Collapsed'
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.RefreshAboutDependenciesButton.RaiseEvent($eventArgs)
                foreach ($name in 'NavApps', 'NavDownload', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall') {
                    $state[$name].Visibility.ToString() | Should -Be 'Visible'
                }
                Should -Invoke Invoke-EwWorkbenchSettingsRefresh -Exactly 1
                Should -Invoke Invoke-EwWorkbenchAboutRefresh -Exactly 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'shows saved paths rather than unsaved edits and explains unavailable folders' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $download = Join-Path -Path $Root -ChildPath 'Download folder'
            $library = Join-Path -Path $Root -ChildPath 'Missing library'
            $null = New-Item -Path $download -ItemType Directory -Force
            Set-EwSetting -Name OutputPath -Value $download
            Set-EwSetting -Name LibraryPath -Value $library
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.OutputPathBox.Text = 'C:\UnsavedDownload'
                $state.LibraryPathBox.Text = 'C:\UnsavedLibrary'
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                & $Wait -State $state -Kind 'Library'
                $state.SettingsDownloadPathBox.IsReadOnly | Should -BeTrue
                $state.SettingsLibraryPathBox.IsReadOnly | Should -BeTrue
                $state.SettingsDownloadPathBox.Text | Should -Be $download
                $state.SettingsLibraryPathBox.Text | Should -Be $library
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeTrue
                $state.OpenLibraryFolderButton.IsEnabled | Should -BeFalse
                $state.LibraryFolderStatusLabel.Text | Should -Match 'unavailable'
                Test-Path -LiteralPath $library | Should -BeFalse

                Set-EwSetting -Name LibraryPath -Value ''
                $state.NavApps.IsChecked = $true
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                $state.SettingsLibraryPathBox.Text | Should -Be ''
                $state.LibraryFolderStatusLabel.Text | Should -Match 'No library folder is configured'
                $state.OpenLibraryFolderButton.IsEnabled | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'shows existing defaults without creating a settings file' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob } {
            param($Wait)
            $defaults = Get-EwSetting
            $settingsPath = Get-EwSettingsPath
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $defaults
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                $state.SettingsDownloadPathBox.Text | Should -Be $defaults.OutputPath
                $state.SettingsLibraryPathBox.Text | Should -Be $defaults.LibraryPath
                Test-Path -LiteralPath $settingsPath | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'rechecks a folder before opening it and does not open a removed folder' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $download = Join-Path -Path $Root -ChildPath 'Folder with spaces'
            $null = New-Item -Path $download -ItemType Directory -Force
            Set-EwSetting -Name OutputPath -Value $download
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-Process {}
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.OpenDownloadFolderButton.RaiseEvent($eventArgs)
                & $Wait -State $state -Kind 'Download'
                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                    $FilePath -eq 'explorer.exe' -and $ArgumentList -eq ('"{0}"' -f $download)
                }

                Remove-Item -LiteralPath $download -Force
                $state.OpenDownloadFolderButton.RaiseEvent($eventArgs)
                & $Wait -State $state -Kind 'Download'
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                $state.DownloadFolderStatusLabel.Text | Should -Match 'unavailable'
                Should -Invoke Start-Process -Exactly 1
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'checks and opens a long saved path without truncating it' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $download = Join-Path -Path $Root -ChildPath 'LongDownload'
            foreach ($index in 1..5) {
                $download = Join-Path -Path $download -ChildPath (('folder{0}' -f $index).PadRight(50, 'x'))
            }
            $extendedPath = '\\?\' + $download
            $null = [System.IO.Directory]::CreateDirectory($extendedPath)
            Set-EwSetting -Name OutputPath -Value $extendedPath
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-Process {}
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                $state.SettingsDownloadPathBox.Text | Should -Be $extendedPath
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeTrue
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.OpenDownloadFolderButton.RaiseEvent($eventArgs)
                & $Wait -State $state -Kind 'Download'
                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                    $FilePath -eq 'explorer.exe' -and $ArgumentList -eq ('"{0}"' -f $extendedPath)
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'replaces a slow folder check when the saved path changes or is cleared' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $window = Get-EwWorkbenchWindow
            $ready = [System.Threading.ManualResetEventSlim]::new($false)
            $probe = [System.Threading.Tasks.TaskCompletionSource[bool]]::new()
            $blockedCheck = {
                param($Ready, $Probe)
                $Ready.Set()
                while (-not $Probe.IsCompleted) {
                    Start-Sleep -Milliseconds 100
                }
                $Probe.GetAwaiter().GetResult()
            }
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $oldJob = Start-EwJob -NoModuleImport -ScriptBlock $blockedCheck -ArgumentList @($ready, $probe.Task)
                $ready.Wait([TimeSpan]::FromSeconds(15)) | Should -BeTrue
                $slot = $state.InfoJobs.Download
                $slot.Generation = 1
                $slot.ActiveId = $oldJob.Id
                $slot.ActiveRequest = @{ Generation = 1; Path = 'C:\OldFolder'; OpenAfterCheck = $false }
                $state.SettingsDownloadPathBox.Text = $Root
                $watch = [Diagnostics.Stopwatch]::StartNew()
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $watch.Stop()
                $watch.Elapsed.TotalSeconds | Should -BeLessThan 2
                $slot.ActiveId | Should -Not -Be $oldJob.Id
                { Get-EwJob -Id $oldJob.Id } | Should -Throw '*not found*'
                $probe.Task.IsCompleted | Should -BeFalse
                & $Wait -State $state -Kind 'Download'
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeTrue

                $ready.Reset()
                $oldJob = Start-EwJob -NoModuleImport -ScriptBlock $blockedCheck -ArgumentList @($ready, $probe.Task)
                $ready.Wait([TimeSpan]::FromSeconds(15)) | Should -BeTrue
                $slot.ActiveId = $oldJob.Id
                $slot.ActiveRequest = @{ Generation = $slot.Generation; Path = $Root; OpenAfterCheck = $false }
                $state.SettingsDownloadPathBox.Text = ''
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $slot.ActiveId | Should -BeNullOrEmpty
                { Get-EwJob -Id $oldJob.Id } | Should -Throw '*not found*'
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                $state.DownloadFolderStatusLabel.Text | Should -Match 'No download folder is configured'
            }
            finally {
                $null = $probe.TrySetResult($true)
                $window.Close()
                $ready.Dispose()
            }
        }
    }

    It 'reuses an unchanged folder check instead of starting another probe' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $jobId = [guid]::NewGuid()
                Mock Start-EwJob { [PSCustomObject]@{ Id = $jobId } }
                Mock Get-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Running' } }
                Mock Stop-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Stopped' } }
                Mock Remove-EwJob {}
                $state.SettingsDownloadPathBox.Text = 'C:\SameFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.InfoJobs.Download.ActiveId | Should -Be $jobId
                $state.InfoJobs.Download.Pending | Should -BeNullOrEmpty
                Should -Invoke Start-EwJob -Exactly 1
                Should -Invoke Stop-EwJob -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'rechecks an unchanged folder when its previous check has already completed' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $firstId = [guid]::NewGuid()
                $secondId = [guid]::NewGuid()
                $script:folderTestIds = [System.Collections.Generic.Queue[guid]]::new()
                $script:folderTestIds.Enqueue($firstId)
                $script:folderTestIds.Enqueue($secondId)
                Mock Start-EwJob { [PSCustomObject]@{ Id = $script:folderTestIds.Dequeue() } }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Available = $Id -eq $firstId
                                ResolvedPath = 'C:\SameFolder'
                                Error = 'The folder is unavailable.'
                            })
                    }
                }
                Mock Stop-EwJob {}
                Mock Remove-EwJob {}
                $state.SettingsDownloadPathBox.Text = 'C:\SameFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.InfoJobs.Download.ActiveId | Should -Be $secondId
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                $state.DownloadFolderStatusLabel.Text | Should -Match 'folder is unavailable'
                Should -Invoke Start-EwJob -Exactly 2
                Should -Invoke Stop-EwJob -Exactly 0
                Should -Invoke Remove-EwJob -Exactly 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reports a cancellation failure and retains the old job until it can be removed' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.StatusLabel.Text = 'Download in progress'
                $firstId = [guid]::NewGuid()
                $secondId = [guid]::NewGuid()
                $script:folderTestIds = [System.Collections.Generic.Queue[guid]]::new()
                $script:folderTestIds.Enqueue($firstId)
                $script:folderTestIds.Enqueue($secondId)
                $script:folderTestFirstState = 'Running'
                Mock Start-EwJob { [PSCustomObject]@{ Id = $script:folderTestIds.Dequeue() } }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id
                        State = if ($Id -eq $firstId) { $script:folderTestFirstState } else { 'Completed' }
                        Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Available = $true; ResolvedPath = 'C:\NewFolder'; Error = ''
                            })
                    }
                }
                Mock Stop-EwJob { throw 'synthetic cancellation failure' }
                Mock Remove-EwJob {}
                $state.SettingsDownloadPathBox.Text = 'C:\OldFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.SettingsDownloadPathBox.Text = 'C:\NewFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.InfoJobs.Download.ActiveId | Should -Be $firstId
                $state.InfoJobs.Download.Pending.Path | Should -Be 'C:\NewFolder'
                $state.DownloadFolderStatusLabel.Text | Should -Match 'synthetic cancellation failure'
                $state.ActivityLog.Text | Should -Match 'synthetic cancellation failure'
                $state.StatusLabel.Text | Should -Be 'Download in progress'

                $script:folderTestFirstState = 'Completed'
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.InfoJobs.Download.ActiveId | Should -Be $secondId
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeTrue
                $state.DownloadFolderStatusLabel.Text | Should -Be 'Folder is available.'
                Should -Invoke Start-EwJob -Exactly 2
                Should -Invoke Stop-EwJob -Exactly 1
                Should -Invoke Remove-EwJob -Exactly 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'discards a folder check when a path changes only by case' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $firstId = [guid]::NewGuid()
                $secondId = [guid]::NewGuid()
                $script:folderTestIds = [System.Collections.Generic.Queue[guid]]::new()
                $script:folderTestIds.Enqueue($firstId)
                $script:folderTestIds.Enqueue($secondId)
                Mock Start-EwJob { [PSCustomObject]@{ Id = $script:folderTestIds.Dequeue() } }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id
                        State = if ($Id -eq $firstId) { 'Running' } else { 'Completed' }
                        Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Available = $Id -eq $firstId
                                ResolvedPath = 'C:\Folder'
                                Error = 'The new folder is unavailable.'
                            })
                    }
                }
                Mock Stop-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Stopped' } }
                Mock Remove-EwJob {}
                $state.SettingsDownloadPathBox.Text = 'C:\Folder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.SettingsDownloadPathBox.Text = 'C:\folder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind 'Download'
                $state.InfoJobs.Download.ActiveId | Should -Be $secondId
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                $state.DownloadFolderStatusLabel.Text | Should -Match 'new folder is unavailable'
                Should -Invoke Start-EwJob -Exactly 2
                Should -Invoke Stop-EwJob -Exactly 1
                Should -Invoke Remove-EwJob -Exactly 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'quotes a folder ending in a backslash for Explorer' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-Process {}
                $result = [PSCustomObject]@{ Available = $true; ResolvedPath = 'C:\'; Error = '' }
                Invoke-EwWorkbenchInfoJobResult -State $state -Kind 'Download' `
                    -Request @{ OpenAfterCheck = $true } -Output @($result)
                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                    $FilePath -eq 'explorer.exe' -and $ArgumentList -eq '"C:\\"'
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reports a settings read failure without retaining enabled folder actions' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $jobId = [guid]::NewGuid()
                $state.InfoJobs.Download.ActiveId = $jobId
                $state.InfoJobs.Download.ActiveRequest = @{ Generation = 1; Path = 'C:\OldFolder' }
                Mock Get-EwSetting { throw 'settings are invalid' }
                Mock Get-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Running' } }
                Mock Stop-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Stopped' } }
                Mock Remove-EwJob {}
                $state.NavSettings.IsChecked = $true
                $state.OpenDownloadFolderButton.IsEnabled | Should -BeFalse
                $state.OpenLibraryFolderButton.IsEnabled | Should -BeFalse
                $state.DownloadFolderStatusLabel.Text | Should -Match 'settings are invalid'
                $state.LibraryFolderStatusLabel.Text | Should -Match 'settings are invalid'
                $state.InfoJobs.Download.ActiveId | Should -BeNullOrEmpty
                Should -Invoke Stop-EwJob -Exactly 1
                Should -Invoke Remove-EwJob -Exactly 1
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps About refresh separate from an active Job and uses the window runspace snapshot' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $primaryId = [guid]::NewGuid()
                $aboutId = [guid]::NewGuid()
                $state.ActiveJobId = $primaryId
                $state.ActiveJobKind = 'Downloads'
                $state.StatusLabel.Text = 'Download in progress'
                Mock Get-Module -ParameterFilter { $All } {
                    [PSCustomObject]@{ Name = 'Evergreen'; Version = [version]'1.0' }
                    [PSCustomObject]@{ Name = 'Evergreen'; Version = [version]'2.0' }
                }
                Mock Start-EwJob { [PSCustomObject]@{ Id = $aboutId } }
                $state.NavAbout.IsChecked = $true
                $state.ActiveJobId | Should -Be $primaryId
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $NoModuleImport }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id
                        State = 'Completed'
                        Errors = @()
                        TerminatingError = $null
                        Output = @(
                            [PSCustomObject]@{
                                Name = 'Evergreen'; Required = $true; MinimumVersion = '1.0'
                                InstalledVersion = '3.0'; Status = 'Installed'; Purpose = 'Catalog'
                            }
                            [PSCustomObject]@{
                                Name = 'Az.Storage'; Required = $false; MinimumVersion = ''
                                InstalledVersion = ''; Status = 'Not installed'; Purpose = 'Storage'
                            }
                        )
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $rows = @($state.AboutDependenciesListView.ItemsSource)
                $rows[0].InstalledVersion | Should -Be '3.0'
                $rows[0].LoadedVersions | Should -Be '1.0, 2.0'
                $rows[1].LoadedVersions | Should -Be 'Not loaded'
                $rows[1].Type | Should -Be 'Optional'
                $state.ActiveJobId | Should -Be $primaryId
                $state.StatusLabel.Text | Should -Be 'Download in progress'
                $state.RefreshAboutDependenciesButton.IsEnabled | Should -BeTrue
                Should -Invoke Remove-EwJob -Exactly 1 -ParameterFilter { $Id -eq $aboutId }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps prior dependency results marked stale when refresh fails' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.ActiveJobId = [guid]::NewGuid()
                $state.StatusLabel.Text = 'Download in progress'
                $old = [PSCustomObject]@{ Name = 'Previous result' }
                $state.AboutDependenciesListView.ItemsSource = [object[]]@($old)
                $aboutId = [guid]::NewGuid()
                Mock Start-EwJob { [PSCustomObject]@{ Id = $aboutId } }
                $state.NavAbout.IsChecked = $true
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Failed'; Output = @(); Errors = @()
                        TerminatingError = [PSCustomObject]@{ Exception = [Exception]::new('scan failed') }
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                @($state.AboutDependenciesListView.ItemsSource)[0].Name | Should -Be 'Previous result'
                $state.AboutDependencyStatusLabel.Text | Should -Match 'scan failed'
                $state.AboutDependencyStatusLabel.Text | Should -Match 'stale'
                $state.RefreshAboutDependenciesButton.IsEnabled | Should -BeTrue
                $state.StatusLabel.Text | Should -Be 'Download in progress'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reports an empty dependency scan as a failure' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.AboutDependenciesListView.ItemsSource = [object[]]@([PSCustomObject]@{ Name = 'Previous result' })
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                $state.NavAbout.IsChecked = $true
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Errors = @(); TerminatingError = $null; Output = @()
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.AboutDependencyStatusLabel.Text | Should -Match 'No dependency information was returned'
                $state.AboutDependencyStatusLabel.Text | Should -Match 'stale'
                @($state.AboutDependenciesListView.ItemsSource)[0].Name | Should -Be 'Previous result'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'coalesces repeated About refreshes without applying an outdated result' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $firstId = [guid]::NewGuid()
                $secondId = [guid]::NewGuid()
                $script:infoTestIds = [System.Collections.Generic.Queue[guid]]::new()
                $script:infoTestIds.Enqueue($firstId)
                $script:infoTestIds.Enqueue($secondId)
                $script:infoTestVersion = '1.0'
                Mock Get-Module -ParameterFilter { $All } {
                    [PSCustomObject]@{ Name = 'Evergreen'; Version = [version]$script:infoTestVersion }
                }
                Mock Start-EwJob { [PSCustomObject]@{ Id = $script:infoTestIds.Dequeue() } }
                $state.NavAbout.IsChecked = $true
                $script:infoTestVersion = '2.0'
                Invoke-EwWorkbenchAboutRefresh -State $state
                Mock Get-EwJob {
                    $version = if ($Id -eq $firstId) { '1.0' } else { '2.0' }
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Name = 'Evergreen'; Required = $true; MinimumVersion = '1.0'
                                InstalledVersion = $version; Status = 'Installed'; Purpose = 'Catalog'
                            })
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.InfoJobs.About.ActiveId | Should -Be $secondId
                $state.AboutDependenciesListView.ItemsSource | Should -BeNullOrEmpty
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $row = @($state.AboutDependenciesListView.ItemsSource)[0]
                $row.InstalledVersion | Should -Be '2.0'
                $row.LoadedVersions | Should -Be '2.0'
                Should -Invoke Start-EwJob -Exactly 2
                Should -Invoke Remove-EwJob -Exactly 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'refreshes real local dependency data without importing optional modules' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob } {
            param($Wait)
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $optional = 'IntuneWin32App', 'Microsoft.Graph.Authentication', 'Az.Accounts', 'Az.Resources', 'Az.Storage'
                $before = @(Get-Module -Name $optional -All | ForEach-Object { "$($_.Name):$($_.Version)" }) -join ','
                $evergreenVersion = [string](Get-Module -Name Evergreen -All | Select-Object -First 1).Version
                $state.NavAbout.IsChecked = $true
                & $Wait -State $state -Kind 'About'
                $rows = @($state.AboutDependenciesListView.ItemsSource)
                $rows.Count | Should -Be 6
                $evergreen = $rows | Where-Object Name -EQ 'Evergreen'
                $evergreen.Type | Should -Be 'Required'
                $evergreen.LoadedVersions | Should -Match ([regex]::Escape($evergreenVersion))
                $state.AboutDependencyStatusLabel.Text | Should -Match 'refreshed'
                $after = @(Get-Module -Name $optional -All | ForEach-Object { "$($_.Name):$($_.Version)" }) -join ','
                $after | Should -Be $before
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reports the window runspace versions while a different worker Job is active' {
        $paths = @{}
        foreach ($entry in @(
                @{ Name = 'Caller'; Version = '1.0' },
                @{ Name = 'Window'; Version = '2.0' },
                @{ Name = 'Worker'; Version = '3.0' }
            )) {
            $directory = Join-Path -Path $TestDrive -ChildPath $entry.Name
            $null = New-Item -Path $directory -ItemType Directory -Force
            $paths[$entry.Name] = Join-Path -Path $directory -ChildPath 'Az.Storage.psd1'
            $moduleFile = Join-Path -Path $directory -ChildPath 'Az.Storage.psm1'
            Set-Content -LiteralPath $moduleFile -Value '# Synthetic module for runspace isolation.'
            New-ModuleManifest -Path $paths[$entry.Name] -RootModule 'Az.Storage.psm1' `
                -ModuleVersion $entry.Version -Guid ([guid]::NewGuid())
        }
        $callerModule = Import-Module -Name $paths.Caller -PassThru -ErrorAction Stop
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
        $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $runspace.Open()
        $powerShell = [powershell]::Create()
        $powerShell.Runspace = $runspace
        try {
            $workbenchPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
            $scriptBlock = {
                param($WorkbenchPath, $WindowPath, $WorkerPath)
                Import-Module -Name $WorkbenchPath -ErrorAction Stop
                Import-Module -Name $WindowPath -Scope Global -ErrorAction Stop
                & (Get-Module -Name EvergreenUI) {
                    param($WorkerModulePath)
                    $window = Get-EwWorkbenchWindow
                    $ready = [System.Threading.ManualResetEventSlim]::new($false)
                    $release = [System.Threading.ManualResetEventSlim]::new($false)
                    $workerData = [hashtable]::Synchronized(@{ Version = '' })
                    $mainJob = $null
                    try {
                        $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                        $mainJob = Start-EwJob -NoModuleImport -ScriptBlock {
                            param($Path, $Ready, $Release, $Data)
                            Import-Module -Name $Path -Scope Global -ErrorAction Stop
                            $Data.Version = [string](Get-Module -Name Az.Storage).Version
                            $Ready.Set()
                            $null = $Release.Wait([TimeSpan]::FromSeconds(20))
                        } -ArgumentList @($WorkerModulePath, $ready, $release, $workerData)
                        if (-not $ready.Wait([TimeSpan]::FromSeconds(15))) {
                            throw 'The worker did not load its dependency.'
                        }
                        $state.ActiveJobId = $mainJob.Id
                        $state.ActiveJobKind = 'Downloads'
                        $state.StatusLabel.Text = 'Download in progress'
                        $state.NavAbout.IsChecked = $true
                        $deadline = [DateTime]::UtcNow.AddSeconds(15)
                        do {
                            Invoke-EwWorkbenchInfoJobMonitor -State $state
                            if ($null -eq $state.InfoJobs.About.ActiveId) { break }
                            Start-Sleep -Milliseconds 50
                        } while ([DateTime]::UtcNow -lt $deadline)
                        if ($null -ne $state.InfoJobs.About.ActiveId) {
                            throw 'The About refresh did not finish.'
                        }
                        $row = @($state.AboutDependenciesListView.ItemsSource) | Where-Object Name -EQ 'Az.Storage'
                        [PSCustomObject]@{
                            LoadedVersions = $row.LoadedVersions
                            WorkerVersion = $workerData.Version
                            WorkerState = (Get-EwJob -Id $mainJob.Id).State
                            ActiveId = $state.ActiveJobId
                            JobId = $mainJob.Id
                            Status = $state.StatusLabel.Text
                        }
                    }
                    finally {
                        $release.Set()
                        if ($null -ne $mainJob) {
                            $deadline = [DateTime]::UtcNow.AddSeconds(10)
                            do {
                                $current = Get-EwJob -Id $mainJob.Id
                                if ($current.State -notin @('NotStarted', 'Running', 'Stopping')) { break }
                                Start-Sleep -Milliseconds 50
                            } while ([DateTime]::UtcNow -lt $deadline)
                            Remove-EwJob -Id $mainJob.Id -Confirm:$false
                        }
                        $ready.Dispose()
                        $release.Dispose()
                        $window.Close()
                    }
                } $WorkerPath
            }
            $null = $powerShell.AddScript($scriptBlock.ToString()).AddArgument($workbenchPath).
                AddArgument($paths.Window).AddArgument($paths.Worker)
            $result = @($powerShell.Invoke())
            if ($powerShell.HadErrors) { throw $powerShell.Streams.Error[0] }
            $result.Count | Should -Be 1
            $callerModule.Version.ToString() | Should -Be '1.0'
            $result[0].LoadedVersions | Should -Be '2.0'
            $result[0].WorkerVersion | Should -Be '3.0'
            $result[0].WorkerState | Should -Be 'Running'
            $result[0].ActiveId | Should -Be $result[0].JobId
            $result[0].Status | Should -Be 'Download in progress'
        }
        finally {
            $powerShell.Dispose()
            $runspace.Dispose()
            Remove-Module -ModuleInfo $callerModule -Force -ErrorAction SilentlyContinue
        }
    }

    It 'surfaces an error from the local dependency scanner and retains stale results' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $scanRoot = Join-Path -Path $Root -ChildPath 'FailedDependencyScan'
            $dependencyDirectory = Join-Path -Path $scanRoot -ChildPath 'Public\Dependencies'
            $null = New-Item -Path $dependencyDirectory -ItemType Directory -Force
            $dependencyScript = Join-Path -Path $dependencyDirectory -ChildPath 'Get-EwDependency.ps1'
            Set-Content -LiteralPath $dependencyScript -Value 'function Get-EwDependency { throw "synthetic scanner failure" }'
            $originalModulePath = $script:ewModulePath
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.AboutDependenciesListView.ItemsSource = [object[]]@([PSCustomObject]@{ Name = 'Previous result' })
                $script:ewModulePath = Join-Path -Path $scanRoot -ChildPath 'EvergreenUI.psd1'
                $state.NavAbout.IsChecked = $true
                & $Wait -State $state -Kind 'About'
                $state.AboutDependencyStatusLabel.Text | Should -Match 'synthetic scanner failure'
                $state.AboutDependencyStatusLabel.Text | Should -Match 'stale'
                @($state.AboutDependenciesListView.ItemsSource)[0].Name | Should -Be 'Previous result'
            }
            finally {
                $script:ewModulePath = $originalModulePath
                $window.Close()
            }
        }
    }

    It 'closes promptly while local dependency discovery is blocked' {
        InModuleScope EvergreenUI -Parameters @{ Root = $TestDrive } {
            param($Root)
            $scanRoot = Join-Path -Path $Root -ChildPath 'SlowDependencyScan'
            $dependencyDirectory = Join-Path -Path $scanRoot -ChildPath 'Public\Dependencies'
            $null = New-Item -Path $dependencyDirectory -ItemType Directory -Force
            $startedPath = Join-Path -Path $scanRoot -ChildPath 'started'
            $finishedPath = Join-Path -Path $scanRoot -ChildPath 'finished'
            $dependencyScript = Join-Path -Path $dependencyDirectory -ChildPath 'Get-EwDependency.ps1'
            $fakeScan = @'
function Get-EwDependency {
    [System.IO.File]::WriteAllText('<STARTED>', 'started')
    [System.Threading.Thread]::Sleep(4000)
    [System.IO.File]::WriteAllText('<FINISHED>', 'finished')
    [PSCustomObject]@{ Name = 'Evergreen'; Required = $true; MinimumVersion = ''; InstalledVersion = '1.0'; Status = 'Installed'; Purpose = 'Catalog' }
}
'@
            $fakeScan = $fakeScan.Replace('<STARTED>', $startedPath.Replace("'", "''"))
            $fakeScan = $fakeScan.Replace('<FINISHED>', $finishedPath.Replace("'", "''"))
            Set-Content -LiteralPath $dependencyScript -Value $fakeScan
            $originalModulePath = $script:ewModulePath
            $window = Get-EwWorkbenchWindow
            $closed = $false
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $script:ewModulePath = Join-Path -Path $scanRoot -ChildPath 'EvergreenUI.psd1'
                $state.NavAbout.IsChecked = $true
                $deadline = [DateTime]::UtcNow.AddSeconds(15)
                while (-not (Test-Path -LiteralPath $startedPath) -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 25
                }
                Test-Path -LiteralPath $startedPath | Should -BeTrue
                $jobId = $state.InfoJobs.About.ActiveId
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $window.Close()
                $closed = $true
                $watch.Stop()
                $watch.Elapsed.TotalSeconds | Should -BeLessThan 2
                { Get-EwJob -Id $jobId } | Should -Throw '*not found*'
                $state.InfoClosed | Should -BeTrue
            }
            finally {
                if (-not $closed) { $window.Close() }
                $script:ewModulePath = $originalModulePath
                $deadline = [DateTime]::UtcNow.AddSeconds(6)
                while ((Test-Path -LiteralPath $startedPath) -and
                    -not (Test-Path -LiteralPath $finishedPath) -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 50
                }
            }
            Test-Path -LiteralPath $finishedPath | Should -BeTrue
        }
    }

    It 'opens the project and license links only when selected' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-Process {}
                $state.AboutNameValue.Text | Should -Match 'EvergreenUI'
                $state.AboutVersionValue.Text | Should -Match ([regex]::Escape([string]$ExecutionContext.SessionState.Module.Version))
                foreach ($name in 'AboutProjectLink', 'AboutLicenseLink') {
                    $link = $state[$name]
                    $link.NavigateUri.Scheme | Should -Be 'https'
                    $eventArgs = [System.Windows.Navigation.RequestNavigateEventArgs]::new($link.NavigateUri, $null)
                    $eventArgs.RoutedEvent = [System.Windows.Documents.Hyperlink]::RequestNavigateEvent
                    $link.RaiseEvent($eventArgs)
                    $eventArgs.Handled | Should -BeTrue
                }
                Should -Invoke Start-Process -Exactly 2
                { Open-EwWorkbenchLink -Uri ([uri]'file:///C:/test') } | Should -Throw '*HTTP and HTTPS*'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps About reachable above the theme selector at minimum window size' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Width = 960
                $window.Height = 660
                $window.Show()
                $scroll = $window.FindName('NavigationScrollViewer')
                $scroll.ScrollToEnd()
                $window.UpdateLayout()
                $about = $window.FindName('NavAbout')
                $theme = $window.FindName('ThemeCombo')
                $aboutTop = $about.TranslatePoint([System.Windows.Point]::new(0, 0), $window).Y
                $themeTop = $theme.TranslatePoint([System.Windows.Point]::new(0, 0), $window).Y
                $scrollTop = $scroll.TranslatePoint([System.Windows.Point]::new(0, 0), $window).Y
                $aboutTop | Should -BeGreaterOrEqual $scrollTop
                ($aboutTop + $about.ActualHeight) | Should -BeLessOrEqual ($scrollTop + $scroll.ActualHeight)
                ($aboutTop + $about.ActualHeight) | Should -BeLessOrEqual $themeTop
                $about.ActualHeight | Should -BeGreaterThan 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'wraps long loaded-version lists in the dependency grid' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Invoke-EwWorkbenchAboutRefresh {}
                $state.NavAbout.IsChecked = $true
                $row = [PSCustomObject]@{
                    Name = 'Evergreen'
                    Type = 'Required'
                    InstalledVersion = '3000.1000.0'
                    LoadedVersions = '3000.1000.0, 3001.2000.0, 3002.3000.0'
                    MinimumVersion = '2603.2832.0'
                    Status = 'Installed'
                    Purpose = 'Catalog'
                }
                $state.AboutDependenciesListView.ItemsSource = [object[]]@($row)
                $window.Width = 960
                $window.Height = 660
                $window.Show()
                $scroll = [System.Windows.Media.VisualTreeHelper]::GetChild($state.AboutPanel, 0)
                $scroll.ScrollToEnd()
                $window.UpdateLayout()
                $column = $state.AboutDependenciesListView.Columns | Where-Object Header -EQ 'Loaded (window)'
                $cell = $column.GetCellContent($row)
                $cell.Text | Should -Be $row.LoadedVersions
                $cell.ActualHeight | Should -BeGreaterThan 20
            }
            finally {
                $window.Close()
            }
        }
    }
}
