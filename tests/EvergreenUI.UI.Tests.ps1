#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'appdata'
    $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
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

    if (-not ('EvergreenUI.WorkbenchCaptionTestNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EvergreenUI {
    public static class WorkbenchCaptionTestNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct Rect {
            public int Left, Top, Right, Bottom;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MonitorInfo {
            public int Size;
            public Rect Monitor, Work;
            public uint Flags;
        }
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        public static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
        [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", SetLastError = true)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out Rect rect, int size);

        public static int[] GetMonitorWorkArea(IntPtr hwnd) {
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfo(MonitorFromWindow(hwnd, 2), ref info)) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
            return new[] { info.Work.Left, info.Work.Top, info.Work.Right, info.Work.Bottom };
        }
        public static int[] GetFrameBounds(IntPtr hwnd) {
            int result = DwmGetWindowAttribute(hwnd, 9, out Rect rect, Marshal.SizeOf<Rect>());
            if (result != 0) Marshal.ThrowExceptionForHR(result);
            return new[] { rect.Left, rect.Top, rect.Right, rect.Bottom };
        }
        public static void SetWindowBounds(IntPtr hwnd, int x, int y, int width, int height) {
            if (!SetWindowPos(hwnd, IntPtr.Zero, x, y, width, height, 0x214)) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
        }
    }
}
'@ -ErrorAction Stop
    }
}

AfterAll {
    $env:APPDATA = $script:originalAppData
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
                        'NavApps', 'NavLibrary',
                        'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall', 'NavSettings', 'NavAbout',
                        'AppsPanel', 'DownloadTrayPanel', 'DownloadTrayContent', 'DownloadTrayGridSplitter',
                        'DownloadTrayToggleButton', 'DownloadTrayActionButton', 'DownloadNowButton',
                        'LibraryPanel', 'PackagesPanel', 'IntunePanel', 'NerdioPanel', 'InstallPanel',
                        'SettingsPanel', 'AboutPanel', 'SettingsDownloadPathBox', 'SettingsLibraryPathBox',
                        'BrowseDownloadFolderButton', 'BrowseLibraryFolderButton',
                        'OpenDownloadFolderButton', 'OpenLibraryFolderButton', 'AboutDependenciesListView',
                        'RefreshAboutDependenciesButton', 'AboutProjectLink', 'AboutLicenseLink',
                        'AppSearchBox', 'AppCountLabel', 'AppsListView', 'ArtifactsGrid',
                        'DownloadQueueListView', 'LibraryListView', 'LibraryVersionsListView',
                        'PackageDefinitionsListView', 'InstallDefinitionsListView',
                        'LoadPackageDefinitionsButton', 'UpdatePackageDefinitionsButton',
                        'ReloadInstallDefinitionsButton', 'ResolveInstallVersionsButton', 'HideIncompatibleInstallToggle',
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

    It 'switches views and filters artifacts using multi-select check box dropdowns' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavLibrary.IsChecked = $true
                $state.LibraryPanel.Visibility.ToString() | Should -Be 'Visible'
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
                $check = {
                    param([string]$Property, [string]$Value, [bool]$Checked = $true)
                    ($state.ArtifactFilterControls[$Property].CheckBoxes | Where-Object Tag -eq $Value).IsChecked = $Checked
                }
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                foreach ($filter in $state.ArtifactFilterControls.Values) {
                    $filter.Control | Should -BeOfType ([System.Windows.Controls.ComboBox])
                    $filter.Control.Parent.Children[0].Target | Should -Be $filter.Control
                    $filter.Control.Text | Should -Be 'All'
                    @($filter.CheckBoxes | Where-Object IsChecked).Count | Should -Be 0
                }
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                & $check -Property 'Architecture' -Value 'x64'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 12
                $state.ArtifactFilterControls['Architecture'].Control.Text | Should -Be 'x64'
                & $check -Property 'Architecture' -Value 'x86'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24 -Because 'values within a property are combined with OR'
                $state.ArtifactFilterControls['Architecture'].Control.Text | Should -Be '2 selected'
                & $check -Property 'Channel' -Value 'channel8'
                & $check -Property 'Channel' -Value 'channel7'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 6 -Because 'properties are combined with AND'
                & $check -Property 'Architecture' -Value 'x86' -Checked $false
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 3
                & $check -Property '_DerivedType' -Value 'msi'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 0
                foreach ($filter in $state.ArtifactFilterControls.Values) {
                    foreach ($box in $filter.CheckBoxes) { $box.IsChecked = $false }
                }
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                & $check -Property 'Category' -Value 'All'
                $state.ArtifactFilterControls['Category'].Control.Text | Should -Be 'All'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1 -Because "an actual 'All' value is distinct from no selection"
                & $check -Property 'Category' -Value 'All' -Checked $false

                $trackControl = $state.ArtifactFilterControls['Track'].Control
                $trackControl.SelectedItem = $state.ArtifactFilterControls['Track'].CheckBoxes[0]
                $state.ArtifactFilterControls['Track'].CheckBoxes[0].IsChecked | Should -BeTrue -Because 'keyboard selection toggles the value'
                $trackControl.SelectedIndex | Should -Be -1
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1
                $state.ArtifactFilterControls['Track'].CheckBoxes[0].IsChecked = $false

                & $check -Property 'Architecture' -Value 'x64'
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 24
                @($state.ArtifactFilterControls['Architecture'].CheckBoxes | Where-Object IsChecked).Count | Should -Be 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'pads and vertically centers data grid text in <Mode> mode at font size <FontSize>' -ForEach @(
        @{ Mode = 'Light'; FontSize = 12 }
        @{ Mode = 'Dark'; FontSize = 12 }
        @{ Mode = 'Light'; FontSize = 20 }
        @{ Mode = 'Dark'; FontSize = 20 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; FontSize = $FontSize } {
            param($Mode, $FontSize)

            foreach ($name in @(
                    'AppsListView', 'ArtifactsGrid', 'DownloadQueueListView',
                    'LibraryListView', 'LibraryVersionsListView', 'PackageDefinitionsListView',
                    'IntuneComparisonListView', 'IntunePublishResultsListView',
                    'NerdioComparisonListView', 'NerdioPublishResultsListView',
                    'InstallDefinitionsListView', 'AboutDependenciesListView'
                )) {
                $window = Get-EwWorkbenchWindow
                $hostWindow = [System.Windows.Window]::new()
                try {
                    $grid = $window.FindName($name)
                    $grid.Parent.Children.Remove($grid)
                    $hostWindow.ThemeMode = [System.Windows.ThemeMode]::$Mode
                    $hostWindow.Width = 1100
                    $hostWindow.Height = 200
                    $hostWindow.Left = -10000
                    $hostWindow.Top = -10000
                    $hostWindow.ShowInTaskbar = $false
                    $hostWindow.Content = $grid
                    $grid.FontSize = $FontSize
                    if ($FontSize -eq 20) {
                        $grid.MinRowHeight = 56
                    }
                    $values = @{ IsFavourite = $true }
                    foreach ($column in $grid.Columns) {
                        if ($column -is [System.Windows.Controls.DataGridTextColumn]) {
                            $values[$column.Binding.Path.Path] = "Example $($column.Header) value"
                        }
                    }
                    $item = [PSCustomObject]$values
                    $grid.ItemsSource = @($item)
                    $hostWindow.Show()
                    $hostWindow.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $hostWindow.UpdateLayout()
                    foreach ($column in $grid.Columns) {
                        if ($column -isnot [System.Windows.Controls.DataGridTextColumn]) {
                            continue
                        }
                        $grid.ScrollIntoView($item, $column)
                        $hostWindow.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        $hostWindow.UpdateLayout()
                        $text = $column.GetCellContent($item)
                        $text | Should -BeOfType ([System.Windows.Controls.TextBlock])
                        $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($text)
                        while ($null -ne $cell -and $cell -isnot [System.Windows.Controls.DataGridCell]) {
                            $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($cell)
                        }
                        $cell | Should -Not -BeNullOrEmpty
                        $origin = $text.TranslatePoint([System.Windows.Point]::new(0, 0), $cell)
                        $bottom = $cell.ActualHeight - $origin.Y - $text.ActualHeight
                        $reason = "$name/$($column.Header) must retain comfortable text spacing"
                        [Math]::Round($origin.X, 1) | Should -BeGreaterOrEqual 8 -Because $reason
                        [Math]::Round($origin.Y, 1) | Should -BeGreaterOrEqual 4 -Because $reason
                        [Math]::Round($bottom, 1) | Should -BeGreaterOrEqual 4 -Because $reason
                        [Math]::Round([Math]::Abs($origin.Y - $bottom), 1) |
                            Should -BeLessOrEqual 2 -Because $reason
                    }
                }
                finally {
                    $hostWindow.Close()
                    $window.Close()
                }
            }
        }
    }

    It 'offers URI actions in the artifact grid context menu instead of a detail pane' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                @($state.ArtifactsGrid.ContextMenu.Items | ForEach-Object Header) | Should -Be @('Copy URI', 'Open URI')
                $window.FindName('ArtifactUriTextBox') | Should -BeNullOrEmpty
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses theme-aware foreground and accent selection in the sidebar across light and dark modes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                foreach ($mode in 'Light', 'Dark', 'Light') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    foreach ($name in 'NavApps', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall', 'NavSettings', 'NavAbout') {
                        $window.FindName($name).Foreground.Color |
                            Should -Be $window.TryFindResource('TextFillColorPrimaryBrush').Color
                    }
                    $window.FindName('NavIntune').Content | Should -Be 'Intune'
                    $selectedIndicator = $window.FindName('NavApps').Template.FindName(
                        'SelectedIndicator',
                        $window.FindName('NavApps')
                    )
                    $selectedIndicator.Visibility | Should -Be 'Visible'
                    $selectedIndicator.Background.Color |
                        Should -Be $window.TryFindResource([System.Windows.SystemColors]::HighlightBrushKey).Color
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'adapts navigation to window width while keeping labels available to automation' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Width = 960
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $button = $window.FindName('NavApps')
                $label = $button.Template.FindName('NavigationLabel', $button)
                $window.FindName('NavigationColumn').ActualWidth | Should -Be 64
                $label.Visibility | Should -Be 'Collapsed'
                $button.ActualHeight | Should -BeGreaterOrEqual 40
                [System.Windows.Automation.AutomationProperties]::GetName($button) | Should -Be 'Apps view'

                $window.Width = 1200
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.FindName('NavigationColumn').ActualWidth | Should -Be 208
                $label.Visibility | Should -Be 'Visible'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'resizes the activity log without preventing it from collapsing' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $log = $window.FindName('ActivityLog')
                $expander = $log.Parent.Parent
                $expander.IsExpanded = $true
                $thumb = $window.FindName('ActivityLogResizeThumb')
                $thumb.RaiseEvent([System.Windows.Controls.Primitives.DragDeltaEventArgs]::new(0, -40))
                $log.Height | Should -Be 180
                $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                    [System.Windows.Input.Keyboard]::PrimaryDevice,
                    [System.Windows.PresentationSource]::FromVisual($window),
                    0,
                    [System.Windows.Input.Key]::Up
                )
                $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                $thumb.RaiseEvent($keyArgs)
                $log.Height | Should -Be 190
                $expander.IsExpanded = $false
                $expander.IsExpanded | Should -BeFalse
                $expander.IsExpanded = $true
                $log.Height | Should -Be 190
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'associates form labels with their controls and displays log severity' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.FindName('SettingsDownloadPathBox').IsReadOnly | Should -BeTrue
                $window.FindName('BrowseDownloadFolderButton') | Should -Not -BeNullOrEmpty
                $state.NavIntune.IsChecked = $true
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.FindName('IntuneM365CompanyLabel').Target | Should -Be $window.FindName('IntuneM365CompanyBox')
                Write-EwWorkbenchLog -State $state -Message 'Example failure' -Level Error
                $state.StatusLabel.Tag | Should -Be 'Error'
                $state.StatusLabel.Text | Should -Be 'Example failure'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'retains native chrome with a themed solid caption and Mica body across theme changes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
            Mock Set-EwSetting {}
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                if (-not (Test-EwWorkbenchMicaAvailable -Window $window)) {
                    Set-ItResult -Skipped -Because 'WPF Mica is unavailable under the current Windows policies.'
                }
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    $result = [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                    $result | Should -Be 0
                    return $result
                }
                $null = $window.Activate()
                foreach ($mode in 'Light', 'Dark', 'Light', 'System') {
                    $state.ThemeCombo.SelectedItem = $mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.FindName('WorkbenchTitleBar') | Should -BeNullOrEmpty
                    $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                    [System.Windows.Shell.WindowChrome]::GetWindowChrome($window) | Should -BeNullOrEmpty
                    $window.AllowsTransparency | Should -BeFalse
                    $window.Background.Color.A | Should -Be 0
                    $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                    $source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
                    $source.CompositionTarget.BackgroundColor.A | Should -Be 0
                    $backdrop = 0
                    [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute($handle, 38, [ref]$backdrop, 4) |
                        Should -Be 0
                    $backdrop | Should -Be 2
                    $renderingEnabled = -1
                    [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute($handle, 1, [ref]$renderingEnabled, 4) |
                        Should -Be 0
                    $renderingEnabled | Should -Be 1
                    foreach ($captionAttribute in 35, 36) {
                        $brush = if ($captionAttribute -eq 35) {
                            $window.TryFindResource('ApplicationBackgroundBrush')
                        }
                        else { $window.Foreground }
                        $color = $brush.Color
                        $expected = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
                        Should -Invoke Invoke-EwWorkbenchDwmAttribute -ParameterFilter {
                            $Attribute -eq $captionAttribute -and $Value -eq $expected
                        }
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses the native opaque fallback when Mica is unavailable and restores Mica afterwards' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                if (-not (Test-EwWorkbenchMicaAvailable -Window $window)) {
                    Set-ItResult -Skipped -Because 'WPF Mica is unavailable under the current Windows policies.'
                }
                Mock Test-EwWorkbenchMicaAvailable { $false }
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                }
                Set-EwWorkbenchTitleBar -Window $window
                $window.FindName('WorkbenchTitleBar') | Should -BeNullOrEmpty
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                [System.Windows.Shell.WindowChrome]::GetWindowChrome($window) | Should -BeNullOrEmpty
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $renderingEnabled = 0
                [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute($handle, 1, [ref]$renderingEnabled, 4) |
                    Should -Be 0
                $renderingEnabled | Should -Be 1
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    Set-EwWorkbenchTitleBar -Window $window
                    $window.Background.Color | Should -Be $window.TryFindResource('ApplicationBackgroundBrush').Color
                    $color = $window.Background.Color
                    $captionColor = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
                    $color = $window.Foreground.Color
                    $textColor = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
                    Should -Invoke Invoke-EwWorkbenchDwmAttribute -ParameterFilter {
                        $Attribute -eq 35 -and $Value -eq $captionColor
                    }
                    Should -Invoke Invoke-EwWorkbenchDwmAttribute -ParameterFilter {
                        $Attribute -eq 36 -and $Value -eq $textColor
                    }
                }

                Mock Test-EwWorkbenchMicaAvailable { $true }
                Set-EwWorkbenchTitleBar -Window $window
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                $window.Background.Color.A | Should -Be 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'refreshes native caption colours when the background resource changes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Mock Test-EwWorkbenchMicaAvailable { $false }
                Set-EwWorkbenchTitleBar -Window $window
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    $result = [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                    $result | Should -Be 0
                    return $result
                }
                $window.Resources['ApplicationBackgroundBrush'] = [System.Windows.Media.Brushes]::AliceBlue
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -ParameterFilter {
                    $Attribute -eq 35 -and $Value -eq 0x00FFF8F0
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'retains native chrome and the backdrop when caption attribute <Attribute> fails' -ForEach @(
        @{ Attribute = 35 }
        @{ Attribute = 36 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ FailureAttribute = $Attribute } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                if (-not (Test-EwWorkbenchMicaAvailable -Window $window)) {
                    Set-ItResult -Skipped -Because 'WPF Mica is unavailable under the current Windows policies.'
                }
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                }
                Mock Invoke-EwWorkbenchDwmAttribute { -1 } -ParameterFilter {
                    $Attribute -eq $FailureAttribute
                }

                Set-EwWorkbenchTitleBar -Window $window

                $window.FindName('WorkbenchTitleBar') | Should -BeNullOrEmpty
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                [System.Windows.Shell.WindowChrome]::GetWindowChrome($window) | Should -BeNullOrEmpty
                $window.Background.Color.A | Should -Be 0
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $renderingEnabled = 0
                [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute($handle, 1, [ref]$renderingEnabled, 4) |
                    Should -Be 0
                $renderingEnabled | Should -Be 1
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -Exactly 1 -ParameterFilter {
                    $Attribute -eq $FailureAttribute
                }
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -Exactly 0 -ParameterFilter {
                    $Attribute -in 2, 33, 38
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'resets an unresolved caption colour instead of retaining a stale override' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                }
                $window.Resources['ApplicationBackgroundBrush'] = [System.Windows.Media.LinearGradientBrush]::new()
                Set-EwWorkbenchTitleBar -Window $window
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -Exactly 1 -ParameterFilter {
                    $Attribute -eq 35 -and $Value -eq -1
                }
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'rejects unsupported Windows versions, high contrast and missing composition targets' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                Test-EwWorkbenchMicaAvailable -Window $window -WindowsBuild 22000 | Should -BeFalse
                Test-EwWorkbenchMicaAvailable -Window $window -WindowsBuild 22621 -HighContrast $true | Should -BeFalse
                Test-EwWorkbenchMicaAvailable -Window $window -WindowsBuild 22621 -HighContrast $false | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'returns caption colour control to Windows in high contrast' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Mock Invoke-EwWorkbenchDwmAttribute {
                    $nativeValue = $Value
                    [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$nativeValue, 4)
                }

                Set-EwWorkbenchTitleBar -Window $window -HighContrast $true

                $window.FindName('WorkbenchTitleBar') | Should -BeNullOrEmpty
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                $window.Background.Color | Should -Be $window.TryFindResource('ApplicationBackgroundBrush').Color
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -Exactly 1 -ParameterFilter {
                    $Attribute -eq 35 -and $Value -eq -1
                }
                Should -Invoke Invoke-EwWorkbenchDwmAttribute -Exactly 1 -ParameterFilter {
                    $Attribute -eq 36 -and $Value -eq -1
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'falls back when the WPF backdrop policy is disabled' {
        $modulePath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1')).Path
        $modulePath = $modulePath.Replace("'", "''")
        $command = @"
`$ErrorActionPreference = 'Stop'
[AppContext]::SetSwitch('Switch.System.Windows.Appearance.DisableFluentThemeWindowBackdrop', `$true)
Import-Module -Name '$modulePath' -Force
& (Get-Module EvergreenUI) {
    `$window = Get-EwWorkbenchWindow
    try {
        `$window.Show()
        `$window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        if (`$window.WindowStyle -ne 'SingleBorderWindow' -or
            `$window.Background.Color -ne `$window.TryFindResource('ApplicationBackgroundBrush').Color) {
            throw 'The disabled-backdrop policy did not retain the native opaque window.'
        }
    }
    finally {
        `$window.Close()
    }
}
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $output = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -STA -EncodedCommand $encoded 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }

    It 'retains native move resize and caption hit testing' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $style = [EvergreenUI.WorkbenchCaptionTestNative]::GetWindowLong($handle, -16)
                foreach ($requiredStyle in 0x00C00000, 0x00010000, 0x00020000, 0x00040000, 0x00080000) {
                    ($style -band $requiredStyle) | Should -Be $requiredStyle
                }
                $getHit = {
                    param([double]$X, [double]$Y)
                    $packed = ([long][int]$X -band 0xffff) -bor (([long][int]$Y -band 0xffff) -shl 16)
                    [EvergreenUI.WorkbenchCaptionTestNative]::SendMessage(
                        $handle, 0x84, [IntPtr]::Zero, [IntPtr]::new($packed)
                    ).ToInt64()
                }.GetNewClosure()
                $frame = [EvergreenUI.WorkbenchCaptionTestNative]::GetFrameBounds($handle)
                $contentTop = $window.FindName('WorkbenchRoot').PointToScreen([System.Windows.Point]::new(0, 0)).Y
                & $getHit -X ($frame[0] + 200) -Y (($frame[1] + $contentTop) / 2) | Should -Be 2
                & $getHit -X ($frame[0] + 200) -Y ($frame[1] + 1) | Should -Be 12
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'minimizes and maximizes or restores through native system commands' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                [System.Windows.SystemCommands]::MaximizeWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Maximized)
                $window.FindName('WorkbenchRoot').Margin.Left | Should -Be 0
                [System.Windows.SystemCommands]::RestoreWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Normal)
                $window.FindName('WorkbenchRoot').Margin.Left | Should -Be 0

                [System.Windows.SystemCommands]::MinimizeWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Minimized)
                $window.WindowState = [System.Windows.WindowState]::Normal
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'honours the closing guard and persists window size through native close' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.Width = 1050
                $window.Height = 720
                $window.Add_Closing({
                    $closingArgs = $args[1]
                    & $state.ModuleInvoker -Name 'Invoke-EwWorkbenchClosingGuard' -Parameters @{
                        State = $state
                        ClosingArgs = $closingArgs
                    }
                    if (-not $closingArgs.Cancel) {
                        & $state.ModuleInvoker -Name 'Save-EwWorkbenchWindowSize' -Parameters @{ State = $state }
                    }
                }.GetNewClosure())
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $state.ActiveJobKind = 'EvergreenUpdate'
                [System.Windows.SystemCommands]::CloseWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.IsVisible | Should -BeTrue
                $state.StatusLabel.Text | Should -Match 'maintenance'
                $state.ActiveJobKind = ''
                [System.Windows.SystemCommands]::CloseWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.IsVisible | Should -BeFalse
                $saved = Get-EwSetting
                $saved.WindowWidth | Should -Be 1050
                $saved.WindowHeight | Should -Be 720
            }
            finally {
                $state.ActiveJobKind = ''
                if ($window.IsVisible) { $window.Close() }
                $env:APPDATA = $originalAppData
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
                Mock Set-EwSetting {}
                Mock Invoke-EwWorkbenchFolderCheck {}
                Set-EwWorkbenchFolderPath -State $state -Kind Download -Path 'C:\Downloads'
                $state.PackageOutputPathBox.Text | Should -Be 'C:\Downloads'

                $state.PackageOutputPathBox.Text = 'C:\Packages'
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
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

    It 'starts an architecture review after an install batch is confirmed' {
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
                        Name = 'Review selected installations'
                    }
                }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.InstallSelectedPackagesButton.RaiseEvent($eventArgs)
                $state.ActiveJobKind | Should -Be 'InstallReview'
                Should -Invoke Confirm-EwWorkbenchInstallBatch -Exactly 1
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Review selected installations' }
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
                $state.InstallBatchActive = $true
                $state.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
                $state.InstallActiveItems = @(
                    [PSCustomObject]@{ Name = $successfulDefinition.Name; DefinitionPath = $successfulPath; Reconfirmations = 0 }
                    [PSCustomObject]@{ Name = $failedDefinition.Name; DefinitionPath = $failedPath; Reconfirmations = 0 }
                )
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
                                Status = 'Installed'
                                ReviewChanged = $false
                                DownloadedVersion = '2.0'
                                Error = ''
                            }
                            [PSCustomObject]@{
                                Name = 'Fabrikam App'
                                DefinitionPath = $failedPath
                                Succeeded = $false
                                Status = 'Failed'
                                ReviewChanged = $false
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
                $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent)
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

    It 'shows pending work in the navigation badge and hides an empty download tray' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.AppsQueueCountBadge.Visibility.ToString() | Should -Be 'Collapsed'
                $state.Queue.Add([PSCustomObject]@{ Id = 'pending'; Status = 'Pending'; Version = '1.0' })
                $state.DownloadTrayPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.DownloadTrayToggleButton.Content | Should -Match '1 pending'
                $state.AppsQueueCountText.Text | Should -Be '1'
                $state.DownloadTrayContent.Visibility.ToString() | Should -Be 'Collapsed'
                $state.DownloadTrayActionButton.IsEnabled | Should -BeTrue

                $state.DownloadTrayToggleButton.IsChecked = $true
                $state.DownloadTrayContent.Visibility.ToString() | Should -Be 'Visible'
                $state.DownloadTrayGridSplitter.Visibility.ToString() | Should -Be 'Visible'
                $state.Queue[0].Status = 'Downloading'
                $state.ActiveJobId = 'running'
                $state.ActiveJobKind = 'Downloads'
                Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
                $state.DownloadTrayActionButton.Content | Should -Be 'Stop'
                $state.DownloadTrayActionButton.IsEnabled | Should -BeTrue

                $state.ActiveJobId = $null
                $state.ActiveJobKind = ''
                $state.Queue[0].Status = 'Downloaded'
                Invoke-EwWorkbenchBusyState -State $state -IsBusy $false
                $state.AppsQueueCountBadge.Visibility.ToString() | Should -Be 'Collapsed'
                $state.DownloadTrayPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.ClearCompletedQueueButton.IsEnabled | Should -BeTrue
                $click = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
                $state.ClearCompletedQueueButton.RaiseEvent($click)
                $state.Queue.Count | Should -Be 0
                $state.DownloadTrayPanel.Visibility.ToString() | Should -Be 'Collapsed'
                $state.DownloadTrayGridSplitter.Visibility.ToString() | Should -Be 'Collapsed'
                $state.AppsQueueCountText.Text | Should -Be '0'
            }
            finally {
                $state.ActiveJobId = $null
                $state.ActiveJobKind = ''
                $window.Close()
            }
        }
    }

    It 'retains native chrome when earlier interop types are already loaded' {
        $modulePath = (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1').Replace("'", "''")
        $command = @"
`$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EvergreenUI {
    public static class WorkbenchChromeInterop {
        public const int NonClientRenderingEnabled = 1, NonClientRenderingPolicy = 2, UseWindowStyle = 0;
        public const int NonClientRenderingDisabled = 1, WindowCornerPreference = 33, RoundWindowCorners = 2;
        public const int CaptionColor = 35, TextColor = 36, SystemBackdropType = 38;
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
        [DllImport("dwmapi.dll")]
        public static extern int DwmIsCompositionEnabled(out int enabled);
    }
}
'@ -ErrorAction Stop
Import-Module -Name '$modulePath' -Force -ErrorAction Stop
& (Get-Module -Name EvergreenUI) {
    `$window = Get-EwWorkbenchWindow
    try {
        `$window.ShowActivated = `$false
        `$window.ShowInTaskbar = `$false
        `$window.Show()
        `$window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        if (`$window.WindowStyle -ne 'SingleBorderWindow' -or
            `$null -ne [System.Windows.Shell.WindowChrome]::GetWindowChrome(`$window)) {
            throw 'The reloaded window did not retain standard chrome.'
        }
        `$handle = [System.Windows.Interop.WindowInteropHelper]::new(`$window).Handle
        `$rendering = 0
        `$result = [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute(`$handle, 1, [ref]`$rendering, 4)
        if (`$result -ne 0 -or `$rendering -ne 1) {
            throw 'The reloaded window did not retain native non-client rendering.'
        }
        if ((Test-EwWorkbenchMicaAvailable -Window `$window) -and `$window.Background.Color.A -ne 0) {
            throw 'The reloaded window obscures the Mica backdrop.'
        }
    }
    finally {
        `$window.Close()
    }
}
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $stdout = Join-Path -Path $TestDrive -ChildPath 'caption-reload-out.txt'
        $stderr = Join-Path -Path $TestDrive -ChildPath 'caption-reload-error.txt'
        $process = Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
            -ArgumentList "-NoLogo -NoProfile -NonInteractive -STA -EncodedCommand $encodedCommand" `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        try {
            if (-not $process.WaitForExit(30000)) {
                throw 'The window dispatcher did not become idle after loading previous native types.'
            }
            $output = @(
                Get-Content -LiteralPath $stdout -Raw
                Get-Content -LiteralPath $stderr -Raw
            ) -join "`n"
            $process.ExitCode | Should -Be 0 -Because $output
        }
        finally {
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        }
    }

    It 'keeps the taskbar clear when the work area is smaller than the window minimum' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ShowActivated = $false
                $window.ShowInTaskbar = $false
                $minimumHeight = [System.Windows.SystemParameters]::WorkArea.Height + 100
                $window.MinHeight = $minimumHeight
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                [System.Windows.SystemCommands]::MaximizeWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $workArea = [EvergreenUI.WorkbenchCaptionTestNative]::GetMonitorWorkArea($handle)
                $frame = [EvergreenUI.WorkbenchCaptionTestNative]::GetFrameBounds($handle)
                foreach ($edge in 0..3) {
                    [Math]::Abs($frame[$edge] - $workArea[$edge]) | Should -BeLessOrEqual 1
                }
                $window.MinHeight | Should -Be $minimumHeight
                [System.Windows.SystemCommands]::RestoreWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.ActualHeight | Should -BeGreaterOrEqual $minimumHeight
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'retains native movement and resizing in the normal state' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ShowActivated = $false
                $window.ShowInTaskbar = $false
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $bounds = $window.RestoreBounds
                [EvergreenUI.WorkbenchCaptionTestNative]::SetWindowBounds(
                    $handle, 40, 60, 1100, 720
                )
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Normal)
                $window.RestoreBounds | Should -Not -Be $bounds
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps maximized bounds when switching backdrop availability' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ShowActivated = $false
                $window.ShowInTaskbar = $false
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                [System.Windows.SystemCommands]::MaximizeWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $workArea = [EvergreenUI.WorkbenchCaptionTestNative]::GetMonitorWorkArea($handle)

                Mock Test-EwWorkbenchMicaAvailable { $false }
                Set-EwWorkbenchTitleBar -Window $window
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                $nativeFrame = [EvergreenUI.WorkbenchCaptionTestNative]::GetFrameBounds($handle)
                foreach ($edge in 0..3) {
                    [Math]::Abs($nativeFrame[$edge] - $workArea[$edge]) | Should -BeLessOrEqual 1
                }

                Mock Test-EwWorkbenchMicaAvailable { $true }
                Set-EwWorkbenchTitleBar -Window $window
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowStyle | Should -Be ([System.Windows.WindowStyle]::SingleBorderWindow)
                $micaFrame = [EvergreenUI.WorkbenchCaptionTestNative]::GetFrameBounds($handle)
                foreach ($edge in 0..3) {
                    [Math]::Abs($micaFrame[$edge] - $workArea[$edge]) | Should -BeLessOrEqual 1
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps the <Trigger> window inside its monitor work area' -ForEach @(
        @{ Trigger = 'caption-maximized'; RestoreMaximized = $false }
        @{ Trigger = 'startup-maximized'; RestoreMaximized = $true }
    ) {
        InModuleScope EvergreenUI -Parameters @{ RestoreMaximized = $RestoreMaximized } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ShowActivated = $RestoreMaximized
                $window.ShowInTaskbar = $false
                Restore-EwWorkbenchWindowSize -Window $window -Settings @{
                    WindowWidth = 1100
                    WindowHeight = 700
                    WindowMaximized = $RestoreMaximized
                }
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                if (-not $RestoreMaximized) {
                    [System.Windows.SystemCommands]::MaximizeWindow($window)
                }
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Maximized)

                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $workArea = [EvergreenUI.WorkbenchCaptionTestNative]::GetMonitorWorkArea($handle)
                $frame = [EvergreenUI.WorkbenchCaptionTestNative]::GetFrameBounds($handle)
                foreach ($edge in 3, 0, 1, 2) {
                    [Math]::Abs($frame[$edge] - $workArea[$edge]) | Should -BeLessOrEqual 1 -Because (
                        "the window must fill only its monitor work area (frame: $($frame -join ', '); work area: $($workArea -join ', '))"
                    )
                }
                $root = $window.FindName('WorkbenchRoot')
                $topLeft = $root.PointToScreen([System.Windows.Point]::new(0, 0))
                $bottomRight = $root.PointToScreen([System.Windows.Point]::new($root.ActualWidth, $root.ActualHeight))
                $contentBounds = @(
                    [Math]::Max($topLeft.X, $frame[0])
                    [Math]::Max($topLeft.Y, $frame[1])
                    [Math]::Min($bottomRight.X, $frame[2])
                    [Math]::Min($bottomRight.Y, $frame[3])
                )
                foreach ($edge in 3, 0, 2) {
                    [Math]::Abs($contentBounds[$edge] - $workArea[$edge]) | Should -BeLessOrEqual 1 -Because (
                        "the content must fill the available work area (content: $($contentBounds -join ', '); work area: $($workArea -join ', '))"
                    )
                }
                $topLeft.Y | Should -BeGreaterThan $workArea[1] -Because 'the native caption occupies the top of the work area'
                [System.Windows.SystemCommands]::RestoreWindow($window)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Normal)
                $restoredWidth = [Math]::Max($window.MinWidth, [Math]::Min(1100, [System.Windows.SystemParameters]::WorkArea.Width))
                $restoredHeight = [Math]::Max($window.MinHeight, [Math]::Min(700, [System.Windows.SystemParameters]::WorkArea.Height))
                $window.ActualWidth | Should -Be $restoredWidth
                $window.ActualHeight | Should -Be $restoredHeight
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'restores and clamps saved window bounds to the work area' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $workArea = [System.Windows.Rect]::new(0, 0, 1000, 700)
                Restore-EwWorkbenchWindowSize -Window $window -WorkArea $workArea -Settings @{ WindowWidth = 5000; WindowHeight = 100; WindowMaximized = $true }
                $window.Width | Should -Be 1000
                $window.Height | Should -Be $window.MinHeight
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Maximized)
                $window.WindowState = [System.Windows.WindowState]::Normal
                $large = [System.Windows.Rect]::new(0, 0, 3000, 2000)
                Restore-EwWorkbenchWindowSize -Window $window -WorkArea $large -Settings @{ WindowWidth = 'wide'; WindowHeight = 900; WindowMaximized = 'maybe' }
                $window.Width | Should -Be 1200
                $window.Height | Should -Be 900
                $window.WindowState | Should -Be ([System.Windows.WindowState]::Normal)
                $small = [System.Windows.Rect]::new(0, 0, 800, 600)
                Restore-EwWorkbenchWindowSize -Window $window -WorkArea $small -Settings @{}
                $window.Width | Should -Be 800 -Because 'a work area smaller than the minimum keeps the window on screen'
                $window.Height | Should -Be 600
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'saves the normal window size and maximised state' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
                $window.Left = 0
                $window.Top = 0
                $window.Width = 1000
                $window.Height = 700
                $window.Show()
                $window.WindowState = [System.Windows.WindowState]::Maximized
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Save-EwWorkbenchWindowSize -State $state
                $saved = Get-EwSetting
                $saved.WindowWidth | Should -Be 1000
                $saved.WindowHeight | Should -Be 700
                $saved.WindowMaximized | Should -BeTrue
                $window.WindowState = [System.Windows.WindowState]::Normal
                $window.Width = 1100
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Save-EwWorkbenchWindowSize -State $state
                $saved = Get-EwSetting
                $saved.WindowWidth | Should -Be 1100
                $saved.WindowMaximized | Should -BeFalse
            }
            finally {
                $window.Close()
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'restores the startup view without saving it and saves later navigation' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $settingsPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\settings.json'
            Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = 'stub' } }
            $windows = [System.Collections.Generic.List[object]]::new()
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Bogus'
                $window = Get-EwWorkbenchWindow
                $windows.Add($window)
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.NavApps.IsChecked | Should -BeTrue
                Test-Path -Path $settingsPath | Should -BeFalse
                $state.ActiveJobId = $null
                $state.NavLibrary.IsChecked = $true
                (Get-EwSetting).StartupView | Should -Be 'Library'

                $window = Get-EwWorkbenchWindow
                $windows.Add($window)
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.LibraryPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Collapsed'
                $state.NavLibrary.IsChecked | Should -BeTrue
            }
            finally {
                foreach ($item in $windows) { $item.Close() }
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'restores a legacy Download startup view as Apps without persisting the migration' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $settings = Get-EwSetting
            $settings.StartupView = 'Download'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.NavApps.IsChecked | Should -BeTrue
                $state.Settings.StartupView | Should -Be 'Apps'
                Test-Path -Path (Get-EwSettingsPath) | Should -BeFalse
                { Set-EwSetting -Name StartupView -Value Download } | Should -Throw
            }
            finally {
                $window.Close()
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'reselects the last application once after the startup catalog load and saves new selections' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $window = Get-EwWorkbenchWindow
            try {
                Set-EwSetting -Name LastAppName -Value 'Beta'
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $alpha = [PSCustomObject]@{ Name = 'Alpha'; FriendlyName = 'Alpha'; IsFavourite = $false }
                $beta = [PSCustomObject]@{ Name = 'Beta'; FriendlyName = 'Beta'; IsFavourite = $false }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = [guid]::NewGuid(); State = 'Completed'; Output = @($alpha, $beta); TerminatingError = $null
                        Progress = @(); Information = @(); Errors = @()
                    }
                }
                Mock Remove-EwJob {}
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'Apps'
                $state.AppsLoading = $true
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.CurrentAppName | Should -Be 'Beta'
                $state.AppsListView.SelectedItem | Should -Be $beta
                $state.PendingLastAppName | Should -BeNullOrEmpty
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Load Beta artifacts' }

                $state.ActiveJobId = $null
                $state.ActiveJobKind = ''
                $state.AppsListView.SelectedItem = $alpha
                (Get-EwSetting).LastAppName | Should -Be 'Alpha'
            }
            finally {
                $state.ActiveJobId = $null
                $window.Close()
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'logs and skips a last application that is no longer in the catalog' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.LastAppName = 'Gone'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = [guid]::NewGuid(); State = 'Completed'; TerminatingError = $null; Progress = @(); Information = @(); Errors = @()
                        Output = @([PSCustomObject]@{ Name = 'Alpha'; FriendlyName = 'Alpha'; IsFavourite = $false })
                    }
                }
                Mock Remove-EwJob {}
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'Apps'
                $state.AppsLoading = $true
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.CurrentApp | Should -BeNullOrEmpty
                $state.ActivityLog.Text | Should -Match "Last application 'Gone' is no longer in the catalog"
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally {
                $state.ActiveJobId = $null
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
                foreach ($name in 'NavApps', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavInstall') {
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
                $state.LibraryPathBox.Text = 'C:\UnsavedLibrary'
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind 'Download'
                & $Wait -State $state -Kind 'Library'
                $state.SettingsDownloadPathBox.IsReadOnly | Should -BeTrue
                $state.SettingsLibraryPathBox.IsReadOnly | Should -BeTrue
                $state.BrowseDownloadFolderButton.IsEnabled | Should -BeTrue
                $state.BrowseLibraryFolderButton.IsEnabled | Should -BeTrue
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

    It 'shows existing defaults without persisting them' {
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
                # Navigation persists only the startup view; displayed defaults are not written.
                $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
                @($saved.Keys | Where-Object { $_ -notin 'SchemaVersion', 'StartupView' -and [string]$saved[$_] -ne [string]$defaults[$_] }) | Should -BeNullOrEmpty
                $saved.StartupView | Should -Be 'Settings'
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

    It 'keeps About reachable in the navigation at minimum window size' {
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
                $aboutTop = $about.TranslatePoint([System.Windows.Point]::new(0, 0), $window).Y
                $scrollTop = $scroll.TranslatePoint([System.Windows.Point]::new(0, 0), $window).Y
                $aboutTop | Should -BeGreaterOrEqual $scrollTop
                ($aboutTop + $about.ActualHeight) | Should -BeLessOrEqual ($scrollTop + $scroll.ActualHeight)
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
