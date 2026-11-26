#Requires -Version 7.6

BeforeDiscovery {
    # Hosted GitHub runners do not provide a reliable interactive desktop for window sizing.
    $isGitHubRunner = $env:GITHUB_ACTIONS -eq 'true'
}

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
                        'NavPackages', 'NavIntune', 'NavNerdio', 'NavSettings', 'NavAbout',
                        'AppsPanel', 'DownloadTrayPanel', 'DownloadTrayContent', 'DownloadTrayGridSplitter',
                        'DownloadTrayToggleButton', 'DownloadTrayActionButton', 'DownloadNowButton',
                        'LibraryPanel', 'PackagesPanel', 'IntunePanel', 'NerdioPanel', 'InstallPanel',
                        'PackagesTabControl', 'DefinitionsTab', 'InstallTab',
                        'SettingsPanel', 'AboutPanel', 'SettingsDownloadPathBox', 'SettingsLibraryPathBox',
                        'BrowseDownloadFolderButton', 'BrowseLibraryFolderButton',
                        'OpenDownloadFolderButton', 'OpenLibraryFolderButton', 'AboutDependenciesListView',
                        'RefreshAboutDependenciesButton', 'AboutProjectLink', 'AboutLicenseLink',
                        'AppSearchBox', 'AppCountLabel', 'AppsListView', 'ArtifactsGrid', 'ExportArtifactsButton',
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

    It 'loads the Workbench window icon independently of the current directory' {
        InModuleScope EvergreenUI -Parameters @{ TestRoot = $TestDrive } {
            $originalLocation = Get-Location
            $window = $null
            try {
                Set-Location -LiteralPath $TestRoot
                $window = Get-EwWorkbenchWindow
                $expectedPath = Join-Path -Path (Split-Path -Path $script:ewModulePath -Parent) -ChildPath 'Resources\evergreenbulb.png'
                $window.Icon.UriSource.LocalPath | Should -Be $expectedPath
                $window.Icon.PixelWidth | Should -BeGreaterThan 0
                $window.Icon.PixelHeight | Should -BeGreaterThan 0
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                [EvergreenUI.WorkbenchCaptionTestNative]::SendMessage(
                    $handle, 0x007F, [IntPtr]::Zero, [IntPtr]::Zero
                ) | Should -Not -Be ([IntPtr]::Zero)
            }
            finally {
                Set-Location -LiteralPath $originalLocation.Path
                if ($null -ne $window) { $window.Close() }
            }
        }
    }

    It 'warns and opens the window when the icon resource is <Condition>' -ForEach @(
        @{ Condition = 'missing' }
        @{ Condition = 'invalid' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ TestRoot = $TestDrive; Condition = $Condition } {
            $originalModulePath = $script:ewModulePath
            $moduleRoot = Join-Path -Path $TestRoot -ChildPath $Condition
            $resources = Join-Path -Path $moduleRoot -ChildPath 'Resources'
            $null = New-Item -Path $resources -ItemType Directory -Force
            $sourceXaml = Join-Path -Path (Split-Path -Path $originalModulePath -Parent) -ChildPath 'Resources\EvergreenWorkbench.xaml'
            Copy-Item -LiteralPath $sourceXaml -Destination $resources
            if ($Condition -eq 'invalid') {
                Set-Content -LiteralPath (Join-Path -Path $resources -ChildPath 'evergreenbulb.png') -Value 'not a PNG'
            }
            $window = $null
            try {
                $script:ewModulePath = Join-Path -Path $moduleRoot -ChildPath 'EvergreenUI.psm1'
                $window = Get-EwWorkbenchWindow -WarningVariable iconWarnings -WarningAction Continue
                $window | Should -Not -BeNullOrEmpty
                $window.Icon | Should -BeNullOrEmpty
                @($iconWarnings).Count | Should -Be 1
                $iconWarnings[0].Message | Should -Match 'Could not load the Workbench window icon'
            }
            finally {
                $script:ewModulePath = $originalModulePath
                if ($null -ne $window) { $window.Close() }
            }
        }
    }

    It 'keeps the Intune connection toolbar usable at window width <Width>' -ForEach @(
        @{ Width = 960; Wraps = $true; Account = 'a-very-long-account-name-for-testing@example.contoso.com' }
        @{ Width = 1200; Wraps = $false; Account = 'person@example.com' }
        @{ Width = 1600; Wraps = $false; Account = 'a-very-long-account-name-for-testing@example.contoso.com' }
    ) -Skip:$isGitHubRunner {
        InModuleScope EvergreenUI -Parameters @{ Width = $Width; Wraps = $Wraps; Account = $Account } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Width = $Width
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.FindName('AppsPanel').Visibility = 'Collapsed'
                $window.FindName('IntunePanel').Visibility = 'Visible'
                $window.FindName('IntuneConnectionStatusLabel').Text = $Account
                $window.FindName('ConnectIntuneButton').Content = 'Disconnect'
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $toolbar = $window.FindName('IntuneConnectionToolbar')
                $status = $window.FindName('IntuneConnectionStatusLabel')
                $separator = $window.FindName('IntuneCompareActionsSeparator')
                $compare = $window.FindName('CompareIntuneButton')
                $separator.Parent | Should -Be $compare.Parent
                $separator.ActualHeight | Should -BeGreaterThan 0
                foreach ($name in @(
                        'IntuneConnectionStatusLabel', 'IntuneTenantIdBox', 'UseIntuneDeviceCodeToggle',
                        'ConnectIntuneButton', 'IntuneCompareActionsSeparator', 'CompareIntuneButton'
                    )) {
                    $control = $window.FindName($name)
                    $point = $control.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar)
                    $point.X | Should -BeGreaterOrEqual 0
                    ($point.X + $control.ActualWidth) | Should -BeLessOrEqual ($toolbar.ActualWidth + 0.5)
                    ($point.Y + $control.ActualHeight) | Should -BeLessOrEqual ($toolbar.ActualHeight + 0.5)
                }
                $statusPoint = $status.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar)
                $comparePoint = $compare.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar)
                $tenant = $window.FindName('IntuneTenantIdBox')
                $tenantPoint = $tenant.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar)
                $separatorPoint = $separator.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar)
                [Math]::Abs($statusPoint.X) | Should -BeLessOrEqual 0.5
                [Math]::Abs(($comparePoint.X + $compare.ActualWidth) - $toolbar.ActualWidth) |
                    Should -BeLessOrEqual 0.5
                ($separatorPoint.X + $separator.ActualWidth) | Should -BeLessThan $comparePoint.X
                if ($Wraps) {
                    $tenantPoint.Y | Should -BeGreaterThan $comparePoint.Y
                    [Math]::Abs(($tenantPoint.X + $tenant.ActualWidth) - $toolbar.ActualWidth) |
                        Should -BeLessOrEqual 0.5
                }
                else {
                    [Math]::Abs(($comparePoint.Y + $compare.ActualHeight / 2) -
                        ($statusPoint.Y + $status.ActualHeight / 2)) | Should -BeLessOrEqual 0.5
                    $tenantPoint.X | Should -BeLessThan $comparePoint.X
                    foreach ($action in 'Connect', 'Disconnect') {
                        $window.FindName('ConnectIntuneButton').Content = $action
                        $window.UpdateLayout()
                        $previous = $tenant.Parent.Children[0]
                        foreach ($name in 'IntuneTenantIdBox', 'UseIntuneDeviceCodeToggle', 'ConnectIntuneButton',
                            'IntuneCompareActionsSeparator', 'CompareIntuneButton') {
                            $control = $window.FindName($name)
                            $left = $control.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar).X
                            $right = $previous.TranslatePoint([System.Windows.Point]::new(0, 0), $toolbar).X +
                                $previous.ActualWidth
                            [Math]::Abs(($left - $right) - 12) | Should -BeLessOrEqual 0.5
                            $previous = $control
                        }
                    }
                }
                $null = $tenant.Focus()
                foreach ($name in 'UseIntuneDeviceCodeToggle', 'ConnectIntuneButton', 'CompareIntuneButton') {
                    $current = [System.Windows.Input.Keyboard]::FocusedElement
                    $current.MoveFocus([System.Windows.Input.TraversalRequest]::new(
                            [System.Windows.Input.FocusNavigationDirection]::Next
                        )) | Should -BeTrue
                    [System.Windows.Input.Keyboard]::FocusedElement | Should -Be $window.FindName($name)
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'left-aligns the Microsoft 365, Settings, and About forms at window width <Width>' -ForEach @(
        @{ Width = 960 }
        @{ Width = 1600 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Width = $Width } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.Width = $Width
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($pageName in 'IntunePanel', 'NerdioPanel', 'SettingsPanel', 'AboutPanel') {
                    foreach ($name in 'AppsPanel', 'IntunePanel', 'NerdioPanel', 'SettingsPanel', 'AboutPanel') {
                        $window.FindName($name).Visibility = 'Collapsed'
                    }
                    $page = $window.FindName($pageName)
                    $page.Visibility = 'Visible'
                    if ($pageName -eq 'SettingsPanel') {
                        $form = $window.FindName('ThemeCombo').Parent
                        $scrollViewer = $page.Children[0]
                    }
                    elseif ($pageName -eq 'AboutPanel') {
                        $form = $window.FindName('AboutNameValue').Parent
                        $scrollViewer = $page.Children[0]
                    }
                    else {
                        $page.Children[0].SelectedIndex = 1
                        $form = $window.FindName($pageName.Replace('Panel', 'M365Form'))
                        $scrollViewer = $page.Children[0].SelectedContent
                    }
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $presenter = $scrollViewer.Template.FindName('PART_ScrollContentPresenter', $scrollViewer)
                    $presenter.ActualWidth | Should -BeGreaterThan 0
                    $offset = $form.TranslatePoint([System.Windows.Point]::new(0, 0), $presenter).X
                    [Math]::Abs($offset - $form.Margin.Left) | Should -BeLessOrEqual 0.5
                    $expectedWidth = [Math]::Min($form.MaxWidth, $presenter.ActualWidth - $form.Margin.Left - $form.Margin.Right)
                    [Math]::Abs($form.ActualWidth - $expectedWidth) | Should -BeLessOrEqual 0.5
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'centres the Intune Update app check boxes in their cells' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $window.FindName('AppsPanel').Visibility = 'Collapsed'
                $window.FindName('IntunePanel').Visibility = 'Visible'
                $grid = $window.FindName('IntuneComparisonListView')
                $grid.ItemsSource = @([PSCustomObject]@{
                        DefinitionName = 'App'; DefinitionVersion = '1.0'; IntuneVersion = '1.0'
                        MatchStatus = 'Matched'; ImportAsUpdate = $false
                    })
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $column = $grid.Columns | Where-Object { $_.Header -eq 'Update app' }
                $cell = $column.GetCellContent($grid.Items[0]).Parent
                $checkBox = $column.GetCellContent($grid.Items[0])
                $checkBox | Should -BeOfType ([System.Windows.Controls.CheckBox])
                $point = $checkBox.TranslatePoint([System.Windows.Point]::new(0, 0), $cell)
                $left = $point.X
                $right = $cell.ActualWidth - $point.X - $checkBox.ActualWidth
                $top = $point.Y
                $bottom = $cell.ActualHeight - $point.Y - $checkBox.ActualHeight
                [Math]::Abs($left - $right) | Should -BeLessOrEqual 2
                [Math]::Abs($top - $bottom) | Should -BeLessOrEqual 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps provider tab headers equal and content usable in <Mode> mode at width <Width>' -ForEach @(
        @{ Mode = 'Light'; Width = 1200 }
        @{ Mode = 'Light'; Width = 960 }
        @{ Mode = 'Dark'; Width = 1200 }
        @{ Mode = 'Dark'; Width = 960 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; Width = $Width } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ThemeMode = [System.Windows.ThemeMode]::$Mode
                $window.Width = $Width
                $window.Height = $window.MinHeight
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $headerWidth = $null
                $expectedGlyphs = @{
                    PackagesPanel = @{ Definitions = 0xE8A5; Install = 0xE896 }
                    IntunePanel   = @{ 'Win32 apps' = 0xECAA; 'Microsoft 365 Apps' = 0xE71D }
                    NerdioPanel   = @{ 'Shell Apps' = 0xE756; 'Microsoft 365 Apps' = 0xE71D; Settings = 0xE713 }
                }
                foreach ($pageName in 'NerdioPanel', 'IntunePanel', 'PackagesPanel', 'NerdioPanel') {
                    $window.FindName('AppsPanel').Visibility = 'Collapsed'
                    $window.FindName('IntunePanel').Visibility = 'Collapsed'
                    $window.FindName('NerdioPanel').Visibility = 'Collapsed'
                    $window.FindName('PackagesPanel').Visibility = 'Collapsed'
                    $page = $window.FindName($pageName)
                    $page.Visibility = 'Visible'
                    $tabs = $page.Children[0]
                    foreach ($selectedIndex in @((0..($tabs.Items.Count - 1)) + 0)) {
                        $tabs.SelectedIndex = $selectedIndex
                        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        $window.UpdateLayout()
                        foreach ($tab in $tabs.Items) {
                            $tab.ActualWidth | Should -BeGreaterThan 0
                            if ($null -eq $headerWidth) { $headerWidth = $tab.ActualWidth }
                            [Math]::Abs($tab.ActualWidth - $headerWidth) | Should -BeLessOrEqual 0.5
                            $header = $tab.Template.FindName('HeaderContent', $tab)
                            $icon = $tab.Template.FindName('HeaderIcon', $tab)
                            $icon.Text | Should -Be ([string][char]($expectedGlyphs[$pageName][$tab.Header]))
                            $icon.IsVisible | Should -BeTrue
                            $icon.ActualWidth | Should -BeGreaterThan 0
                            $headerForeground = [System.Windows.Documents.TextElement]::GetForeground($header)
                            $icon.Foreground.Color | Should -Be $headerForeground.Color
                            $iconPoint = $icon.TranslatePoint([System.Windows.Point]::new(0, 0), $tab)
                            $headerPoint = $header.TranslatePoint([System.Windows.Point]::new(0, 0), $tab)
                            ($iconPoint.X + $icon.ActualWidth) | Should -BeLessOrEqual $headerPoint.X
                            $hitPoint = $icon.TranslatePoint(
                                [System.Windows.Point]::new($icon.ActualWidth / 2, $icon.ActualHeight / 2), $tab
                            )
                            $hit = $tab.InputHitTest($hitPoint)
                            $hit | Should -Not -BeNullOrEmpty
                            $tab.IsAncestorOf($hit) | Should -BeTrue
                            $header.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
                            $labelWidth = $header.DesiredSize.Width - $header.Margin.Left - $header.Margin.Right
                            ($header.ActualWidth + 0.5) | Should -BeGreaterOrEqual $labelWidth
                            $point = $tab.TranslatePoint([System.Windows.Point]::new(0, 0), $page)
                            ($point.X + $tab.ActualWidth) | Should -BeLessOrEqual $page.ActualWidth
                            $indicator = $tab.Template.FindName('SelectedIndicator', $tab)
                            $indicator.Visibility.ToString() | Should -Be $(if ($tab.IsSelected) { 'Visible' } else { 'Collapsed' })
                            $indicator.Background.Color | Should -Be $window.TryFindResource('AccentFillColorDefaultBrush').Color
                        }
                        $host1 = $tabs.Template.FindName('PART_SelectedContentHost', $tabs)
                        $host1.Content | Should -Be $tabs.SelectedItem.Content
                        $host1.ActualHeight | Should -BeGreaterThan 100
                        $host1.Content.IsVisible | Should -BeTrue
                        foreach ($tab in $tabs.Items) {
                            $tab.Content.IsVisible | Should -Be $tab.IsSelected
                            [System.Windows.Documents.TextElement]::GetFontSize($tab.Content) | Should -Be $tabs.FontSize
                            [System.Windows.Documents.TextElement]::GetFontWeight($tab.Content) | Should -Be $tabs.FontWeight
                        }
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'exposes provider tab labels without decorative icon announcements' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($pageName in 'PackagesPanel', 'IntunePanel', 'NerdioPanel') {
                    foreach ($name in 'AppsPanel', 'PackagesPanel', 'IntunePanel', 'NerdioPanel') {
                        $window.FindName($name).Visibility = 'Collapsed'
                    }
                    $page = $window.FindName($pageName)
                    $page.Visibility = 'Visible'
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    foreach ($tab in $page.Children[0].Items) {
                        $icon = $tab.Template.FindName('HeaderIcon', $tab)
                        $tabPeer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($tab)
                        $iconPeer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($icon)
                        $tabPeer.GetName() | Should -Be $tab.Header
                        $iconPeer.IsControlElement() | Should -BeFalse
                        $iconPeer.IsContentElement() | Should -BeFalse
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps disabled provider tab icons in sync with their labels' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.FindName('AppsPanel').Visibility = 'Collapsed'
                $window.FindName('PackagesPanel').Visibility = 'Visible'
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $tab = $window.FindName('PackagesTabControl').Items[1]
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $tab.IsEnabled = $false
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $icon = $tab.Template.FindName('HeaderIcon', $tab)
                    $header = $tab.Template.FindName('HeaderContent', $tab)
                    $headerForeground = [System.Windows.Documents.TextElement]::GetForeground($header)
                    $icon.Foreground.Color | Should -Be $headerForeground.Color
                    if (-not [System.Windows.SystemParameters]::HighContrast) {
                        $icon.Foreground.Color | Should -Be $window.TryFindResource('TextFillColorDisabledBrush').Color
                    }
                    $tab.IsEnabled = $true
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'omits the provider icon when a tab has no glyph' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $tab = [System.Windows.Controls.TabItem]::new()
                $tab.Header = 'Plain tab'
                $tab.Style = $window.FindResource('ProviderTabItemStyle')
                $null = $tab.ApplyTemplate()
                $icon = $tab.Template.FindName('HeaderIcon', $tab)
                $icon.Visibility.ToString() | Should -Be 'Collapsed'
                $tab.Tag = ''
                $icon.Visibility.ToString() | Should -Be 'Collapsed'
                $tab.Tag = [string][char]0xE8A5
                $icon.Visibility.ToString() | Should -Be 'Visible'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses the Windows 10 icon font fallback for provider tab glyphs' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.FindName('AppsPanel').Visibility = 'Collapsed'
                $window.FindName('PackagesPanel').Visibility = 'Visible'
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $tab = $window.FindName('DefinitionsTab')
                $icon = $tab.Template.FindName('HeaderIcon', $tab)
                $icon.FontFamily.Source | Should -Be 'Segoe Fluent Icons, Segoe MDL2 Assets'

                $installed = [System.Windows.Media.Fonts]::SystemFontFamilies |
                    Where-Object { $_.Source -eq 'Segoe MDL2 Assets' }
                if (-not $installed) {
                    Set-ItResult -Skipped -Because 'Segoe MDL2 Assets is not installed on this system'
                }
                $typeface = [System.Windows.Media.Typeface]::new('Evergreen Workbench Missing Test Font, Segoe MDL2 Assets')
                $fallback = $null
                $typeface.TryGetGlyphTypeface([ref]$fallback) | Should -BeTrue
                $fallback.Win32FamilyNames.Values | Should -Contain 'Segoe MDL2 Assets'
                foreach ($pageName in 'PackagesPanel', 'IntunePanel', 'NerdioPanel') {
                    foreach ($item in $window.FindName($pageName).Children[0].Items) {
                        $fallback.CharacterToGlyphMap.ContainsKey([int][char]$item.Tag) | Should -BeTrue
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'preserves provider tab keyboard navigation and focus feedback across theme changes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    foreach ($pageName in 'IntunePanel', 'NerdioPanel') {
                        $window.FindName('AppsPanel').Visibility = 'Collapsed'
                        $window.FindName('IntunePanel').Visibility = 'Collapsed'
                        $window.FindName('NerdioPanel').Visibility = 'Collapsed'
                        $page = $window.FindName($pageName)
                        $page.Visibility = 'Visible'
                        $tabs = $page.Children[0]
                        $tabs.SelectedIndex = 0
                        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        $null = $tabs.Items[0].Focus()
                        foreach ($key in 'Right', 'Home', 'End', 'Left') {
                            $focusedTab = $tabs.SelectedItem
                            $focusedTab.IsKeyboardFocused | Should -BeTrue
                            $border = $focusedTab.Template.FindName('HeaderBorder', $focusedTab)
                            $border.BorderBrush.Color | Should -Be $window.TryFindResource('TextFillColorPrimaryBrush').Color
                            if ($key -in 'Right', 'Left') {
                                $null = $focusedTab.MoveFocus([System.Windows.Input.TraversalRequest]::new(
                                    [System.Windows.Input.FocusNavigationDirection]::$key
                                ))
                            }
                            else {
                                $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                                    [System.Windows.Input.Keyboard]::PrimaryDevice,
                                    [System.Windows.PresentationSource]::FromVisual($window),
                                    0,
                                    [System.Windows.Input.Key]::$key
                                )
                                $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                                $focusedTab.RaiseEvent($keyArgs)
                            }
                            $expectedIndex = switch ($key) {
                                'Right' { 1 }
                                'Home' { 0 }
                                'End' { $tabs.Items.Count - 1 }
                                'Left' { $tabs.Items.Count - 2 }
                            }
                            $tabs.SelectedIndex | Should -Be $expectedIndex
                            $tabs.SelectedItem.IsKeyboardFocused | Should -BeTrue
                        }
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps Library path actions on one line at default and minimum window widths' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Library'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $elements = @(
                    $state.LibraryPathBox
                    $state.BrowseLibraryPathButton
                    $state.SetLibraryPathButton
                    $state.LoadLibraryButton
                    $state.UpdateLibraryButton
                )

                foreach ($width in 1200, 960) {
                    $window.Width = $width
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $previousRight = 0
                    $center = $null
                    foreach ($element in $elements) {
                        $element.IsVisible | Should -BeTrue -Because "the Library controls are visible at width $width"
                        $element.ActualWidth | Should -BeGreaterThan 0
                        $position = $element.TranslatePoint([System.Windows.Point]::new(0, 0), $state.LibraryPanel)
                        [Math]::Round($position.X - $previousRight, 1) | Should -BeGreaterOrEqual 0
                        $previousRight = $position.X + $element.ActualWidth
                        [Math]::Round($previousRight - $state.LibraryPanel.ActualWidth, 1) | Should -BeLessOrEqual 0
                        $elementCenter = $position.Y + ($element.ActualHeight / 2)
                        if ($null -eq $center) {
                            $center = $elementCenter
                        }
                        [Math]::Abs($elementCenter - $center) | Should -BeLessOrEqual 1
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'scrolls the expanded download queue when it has more rows than fit' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Apps'
                $settings.DownloadTrayHeight = 180
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($index in 1..40) {
                    $state.Queue.Add([PSCustomObject]@{
                            Id = "item$index"
                            AppName = "Example $index"
                            Version = '1.0'
                            Architecture = 'x64'
                            Status = 'Pending'
                            URI = "https://example.test/app$index.exe"
                            SavedPath = ''
                        })
                }
                $state.DownloadTrayToggleButton.IsChecked = $true
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()

                $grid = $state.DownloadQueueListView
                $grid.IsVisible | Should -BeTrue
                $grid.ActualHeight | Should -BeLessOrEqual ($state.AppsPanel.RowDefinitions[3].ActualHeight + 1)
                $border = [System.Windows.Media.VisualTreeHelper]::GetChild($grid, 0)
                $scroll = [System.Windows.Media.VisualTreeHelper]::GetChild($border, 0)
                $scroll | Should -BeOfType ([System.Windows.Controls.ScrollViewer])
                $scroll.ScrollableHeight | Should -BeGreaterThan 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'right-aligns the download queue path and toggle with space above the table' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Apps'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                foreach ($status in 'Pending', 'Downloading', 'Downloaded') {
                    $state.Queue.Add([PSCustomObject]@{
                            Id = $status
                            AppName = 'Example'
                            Version = '1.0'
                            Architecture = 'x64'
                            Status = $status
                            URI = 'https://example.test/app.exe'
                            SavedPath = ''
                        })
                }
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($fontSize in 12, 20) {
                    $window.FontSize = $fontSize
                    foreach ($width in 1200, 960) {
                        $window.Width = $width
                        foreach ($path in @('C:\Downloads', ('C:\' + ('Long folder name\' * 80)))) {
                            $state.Settings.OutputPath = $path
                            Show-EwWorkbenchDownloadTray -State $state
                            $collapsedTopGap = $null
                            foreach ($expanded in $false, $true) {
                                $state.DownloadTrayToggleButton.IsChecked = $expanded
                                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                                $window.UpdateLayout()
                                $panel = $state.DownloadTrayPanel
                                $toggle = $state.DownloadTrayToggleButton
                                $destination = $state.DownloadDestinationText
                                $togglePosition = $toggle.TranslatePoint([System.Windows.Point]::new(0, 0), $panel)
                                $pathPosition = $destination.TranslatePoint([System.Windows.Point]::new(0, 0), $panel)
                                $toggle.IsVisible | Should -BeTrue
                                $destination.IsVisible | Should -BeTrue
                                $pathPosition.X | Should -BeGreaterOrEqual -0.5
                                $destination.ActualWidth | Should -BeGreaterThan 0
                                [Math]::Abs(($togglePosition.X + $toggle.ActualWidth) - $panel.ActualWidth) | Should -BeLessOrEqual 1
                                [Math]::Abs(($pathPosition.X + $destination.ActualWidth + 12) - $togglePosition.X) | Should -BeLessOrEqual 1
                                [Math]::Abs(($pathPosition.Y + $destination.ActualHeight / 2) - ($togglePosition.Y + $toggle.ActualHeight / 2)) | Should -BeLessOrEqual 1
                                $destination.Text | Should -BeExactly $path
                                $destination.ToolTip | Should -BeExactly $path
                                $destination.TextTrimming.ToString() | Should -Be 'CharacterEllipsis'
                                $toggle.Content | Should -Match $(if ($expanded) { '^Hide queue' } else { '^Show queue' })
                                $mainArea = $state.AppsListView.Parent
                                $mainBottom = $mainArea.TranslatePoint([System.Windows.Point]::new(0, $mainArea.ActualHeight), $state.AppsPanel).Y
                                $toggleTop = $toggle.TranslatePoint([System.Windows.Point]::new(0, 0), $state.AppsPanel).Y
                                $topGap = $toggleTop - $mainBottom
                                if (-not $expanded) {
                                    $collapsedTopGap = $topGap
                                }
                                else {
                                    [Math]::Abs($topGap - $collapsedTopGap) | Should -BeLessOrEqual 1
                                }
                                $topGap | Should -BeGreaterOrEqual 4
                                if ($expanded) {
                                    $state.DownloadQueueListView.IsVisible | Should -BeTrue
                                    $tableTop = $state.DownloadQueueListView.TranslatePoint([System.Windows.Point]::new(0, 0), $panel).Y
                                    $gap = $tableTop - ($togglePosition.Y + $toggle.ActualHeight)
                                    $gap | Should -BeGreaterOrEqual 15
                                    $gap | Should -BeLessOrEqual 17
                                }
                                else {
                                    $state.DownloadTrayContent.Visibility.ToString() | Should -Be 'Collapsed'
                                }
                            }
                        }
                    }
                }
            }
            finally { $window.Close() }
        }
    }

    It 'places the Packages output folder at the bottom of the view without a large gap' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Packages'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Height = 1000
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()

                $panel = $state.PackagesPanel
                $box = $state.PackageOutputPathBox
                $panel.IsVisible | Should -BeTrue
                $boxBottom = $box.TranslatePoint([System.Windows.Point]::new(0, $box.ActualHeight), $panel).Y
                ($panel.ActualHeight - $boxBottom) | Should -BeLessOrEqual 16
                $state.PackageDefinitionsListView.ActualHeight | Should -BeGreaterThan 260
            }
            finally {
                $window.Close()
            }
        }
    }

    Context 'Artifact column visibility' {
        BeforeEach {
            $columnTestAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
        }

        AfterEach {
            $env:APPDATA = $columnTestAppData
        }

        It 'offers an accessible Columns menu even with no artifacts and locks required columns' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $button = $state.ShowArtifactColumnsButton
                    $button.IsEnabled | Should -BeTrue
                    [System.Windows.Automation.AutomationProperties]::GetName($button) |
                        Should -Be 'Show or hide artifact columns'
                    @($state.ArtifactsGrid.Items).Count | Should -Be 0
                    $menu = $button.ContextMenu
                    $menu.Items.Count | Should -Be 0
                    $state.AllArtifacts = @([PSCustomObject]@{
                        Version = '1'; Architecture = 'x64'; Channel = 'Stable'; Release = 'Current'
                        Type = 'exe'; Language = 'en'; Date = '2026-11-25'; URI = 'https://example.test/a.exe'
                    })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    @($menu.Items | ForEach-Object Header) |
                        Should -Be @('Version', 'Architecture', 'Channel', 'Release', 'Type', 'Language', 'Date', 'URI')
                    $button.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                    ))
                    $menu.IsOpen | Should -BeTrue
                    $menu.PlacementTarget | Should -Be $button
                    foreach ($item in $menu.Items) {
                        $item.IsChecked | Should -BeTrue
                        $item.IsCheckable | Should -BeTrue
                        if ($item.Header -in @('Version', 'URI')) {
                            $item.IsEnabled | Should -BeFalse
                            $item.ToolTip | Should -Match 'must remain visible'
                        }
                        else { $item.IsEnabled | Should -BeTrue }
                    }
                }
                finally {
                    $window.FindName('ShowArtifactColumnsButton').ContextMenu.IsOpen = $false
                    $window.Close()
                }
            }
        }

        It 'shows the union of returned properties with real values and blank missing cells' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $first = [PSCustomObject]@{
                        Size = 0; URI = 'https://example.test/a.exe'; Version = '1'
                        Architecture = 'x64'; IsLatest = $false
                    }
                    $second = [PSCustomObject]@{
                        Version = '2'; Architecture = 'x86'; SIZE = 42; Sha256 = 'abc123'
                        Date = $null; URI = 'https://example.test/b.exe'
                    }
                    $state.AllArtifacts = @($first, $second)
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    @($state.ArtifactsGrid.Columns | ForEach-Object Header) |
                        Should -Be @('Version', 'Architecture', 'Date', 'Size', 'IsLatest', 'Sha256', 'URI')
                    @($state.ShowArtifactColumnsButton.ContextMenu.Items | ForEach-Object Header) |
                        Should -Be @('Version', 'Architecture', 'Date', 'Size', 'IsLatest', 'Sha256', 'URI')
                    [object]::ReferenceEquals($state.ArtifactsGrid.ItemsSource[0], $first) | Should -BeTrue
                    $window.WindowStartupLocation = 'Manual'
                    $window.Left = -10000
                    $window.Top = -10000
                    $window.Show()
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $size = $state.ArtifactsGrid.Columns | Where-Object Header -eq 'Size'
                    $hash = $state.ArtifactsGrid.Columns | Where-Object Header -eq 'Sha256'
                    $date = $state.ArtifactsGrid.Columns | Where-Object Header -eq 'Date'
                    $flag = $state.ArtifactsGrid.Columns | Where-Object Header -eq 'IsLatest'
                    $size.GetCellContent($first).Text | Should -Be '0'
                    $size.GetCellContent($second).Text | Should -Be '42'
                    $hash.GetCellContent($first).Text | Should -Be ''
                    $hash.GetCellContent($second).Text | Should -Be 'abc123'
                    $date.GetCellContent($second).Text | Should -Be ''
                    $flag.GetCellContent($first).Text | Should -Be 'False'

                    ($state.ArtifactFilterControls['Architecture'].CheckBoxes | Where-Object Tag -eq 'x86').IsChecked = $true
                    ($state.ArtifactFilterControls['IsLatest'].CheckBoxes | Where-Object Tag -eq 'False').IsChecked = $true
                    $state.ArtifactsGrid.Items.Count | Should -Be 0
                    [object]::ReferenceEquals(($state.ArtifactsGrid.Columns | Where-Object Header -eq 'Sha256'), $hash) |
                        Should -BeTrue
                }
                finally { $window.Close() }
            }
        }

        It 'refreshes app schemas and remembers app-specific choices across apps reloads and sessions' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '1'; Size = 42; URI = 'https://example.test/a.exe' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Size'
                    $item.IsChecked = $false
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Size'
                    Mock Invoke-EwWorkbenchJob {}
                    $state.AppsListView.ItemsSource = @([PSCustomObject]@{ Name = 'Other'; FriendlyName = 'Other app' })
                    $state.AppsListView.SelectedIndex = 0
                    $state.ArtifactsGrid.Columns.Count | Should -Be 0
                    $state.ShowArtifactColumnsButton.ContextMenu.Items.Count | Should -Be 0
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '2'; Publisher = 'Example' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    @($state.ArtifactsGrid.Columns | ForEach-Object Header) | Should -Be @('Version', 'Publisher')
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Publisher'
                    $item.IsChecked = $false
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Size,Publisher'
                    $window.Close()

                    $window = Get-EwWorkbenchWindow
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '3'; Size = 84; URI = 'https://example.test/a.exe' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    ($state.ArtifactsGrid.Columns | Where-Object Header -eq 'Size').Visibility.ToString() | Should -Be 'Collapsed'
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '4'; Size = 85; Sha256 = 'new' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    @($state.ArtifactsGrid.Columns | ForEach-Object Header) | Should -Be @('Version', 'Size', 'Sha256')
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Size'
                    $item.IsChecked = $true
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Publisher'
                    $state.AllArtifacts = @()
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $state.ArtifactsGrid.Columns.Count | Should -Be 0
                    $state.ShowArtifactColumnsButton.ContextMenu.Items.Count | Should -Be 0
                }
                finally { $window.Close() }
            }
        }

        It 'places export and Columns buttons to the right of filters at default and minimum widths' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = @(
                        [PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Channel = 'Stable'; Language = 'en'; Type = 'exe'; URI = 'https://example.test/a.exe' }
                        [PSCustomObject]@{ Version = '2'; Architecture = 'x86'; Channel = 'Preview'; Language = 'fr'; Type = 'msi'; URI = 'https://example.test/b.msi' }
                    )
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $window.WindowStartupLocation = 'Manual'
                    $window.Left = -10000
                    $window.Top = -10000
                    $window.Show()
                    foreach ($width in 1200, 960) {
                        $window.Width = $width
                        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        $window.UpdateLayout()
                        $button = $state.ShowArtifactColumnsButton
                        $exportButton = $state.ExportArtifactsButton
                        $row = $state.ArtifactFiltersPanel.Parent
                        $button.IsVisible | Should -BeTrue
                        $exportButton.IsVisible | Should -BeTrue
                        $buttonPosition = $button.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        $exportPosition = $exportButton.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        $filterPosition = $state.ArtifactFiltersPanel.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        ($exportPosition.X + 0.5) | Should -BeGreaterOrEqual ($filterPosition.X + $state.ArtifactFiltersPanel.ActualWidth)
                        ($buttonPosition.X + 0.5) | Should -BeGreaterOrEqual ($exportPosition.X + $exportButton.ActualWidth)
                        ($buttonPosition.X + $button.ActualWidth) | Should -BeLessOrEqual ($row.ActualWidth + 0.5)
                        $lastFilter = $state.ArtifactFiltersPanel.Children[$state.ArtifactFiltersPanel.Children.Count - 1]
                        $filterBottom = $lastFilter.TranslatePoint([System.Windows.Point]::new(0, $lastFilter.ActualHeight), $row).Y
                        [Math]::Abs(($buttonPosition.Y + $button.ActualHeight) - $filterBottom) | Should -BeLessOrEqual 1
                        [Math]::Abs(($exportPosition.Y + $exportButton.ActualHeight) - $filterBottom) | Should -BeLessOrEqual 1
                    }
                    $state.AllArtifacts = @()
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $state.ShowArtifactColumnsButton.IsVisible | Should -BeTrue
                }
                finally { $window.Close() }
            }
        }

        It 'keeps filters and artifact actions usable when the pane is narrow or text is enlarged' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = @(
                        [PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Channel = 'Stable'; Language = 'en'; URI = 'https://example.test/a.exe' }
                        [PSCustomObject]@{ Version = '2'; Architecture = 'x86'; Channel = 'Preview'; Language = 'fr'; URI = 'https://example.test/b.exe' }
                    )
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $window.WindowStartupLocation = 'Manual'
                    $window.Left = -10000
                    $window.Top = -10000
                    $window.Show()
                    $state.AppsListColumn.Width = [System.Windows.GridLength]::new(700)
                    foreach ($fontSize in 12, 20) {
                        $window.FontSize = $fontSize
                        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        $window.UpdateLayout()
                        $row = $state.ArtifactControlsGrid
                        [System.Windows.Controls.Grid]::GetRow($state.ArtifactActionsPanel) | Should -Be 1
                        $actionPosition = $state.ArtifactActionsPanel.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        foreach ($group in $state.ArtifactFiltersPanel.Children) {
                            $filter = $group.Children[1]
                            $position = $filter.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                            $filter.ActualWidth | Should -BeGreaterOrEqual 120
                            ($position.X + $filter.ActualWidth) | Should -BeLessOrEqual ($row.ActualWidth + 0.5)
                            ($position.Y + $filter.ActualHeight) | Should -BeLessOrEqual ($actionPosition.Y + 0.5)
                        }
                        $exportPosition = $state.ExportArtifactsButton.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        $columnsPosition = $state.ShowArtifactColumnsButton.TranslatePoint([System.Windows.Point]::new(0, 0), $row)
                        ($exportPosition.X + $state.ExportArtifactsButton.ActualWidth) | Should -BeLessOrEqual ($columnsPosition.X + 0.5)
                        ($columnsPosition.X + $state.ShowArtifactColumnsButton.ActualWidth) | Should -BeLessOrEqual ($row.ActualWidth + 0.5)
                    }
                    $window.FontSize = 12
                    $state.AppsListColumn.Width = [System.Windows.GridLength]::new(220)
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    [System.Windows.Controls.Grid]::GetRow($state.ArtifactActionsPanel) | Should -Be 0
                }
                finally { $window.Close() }
            }
        }

        It 'hides and shows each optional column and restores the choices after reopening' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $artifacts = @([PSCustomObject]@{
                        Version = '1'; Architecture = 'x64'; Channel = 'Stable'; Release = 'Current'
                        Type = 'exe'; Language = 'en'; Date = '2026-11-25'; URI = 'https://example.test/a.exe'
                    })
                    $state.AllArtifacts = $artifacts
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $optional = @($state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object IsEnabled)
                    foreach ($item in $optional) {
                        $item.IsChecked = $false
                        $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                        $item.Tag.Visibility.ToString() | Should -Be 'Collapsed'
                    }
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Architecture,Channel,Release,Type,Language,Date'
                    $window.Close()
                    $window = Get-EwWorkbenchWindow
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = $artifacts
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    foreach ($item in $state.ShowArtifactColumnsButton.ContextMenu.Items) {
                        if ($item.IsEnabled) {
                            $item.IsChecked | Should -BeFalse
                            $item.Tag.Visibility.ToString() | Should -Be 'Collapsed'
                            $item.IsChecked = $true
                            $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                        }
                        $item.Tag.Visibility.ToString() | Should -Be 'Visible'
                    }
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be ''
                    $state.Settings.ArtifactHiddenColumns | Should -Be ''
                }
                finally { $window.Close() }
            }
        }

        It 'preserves hidden columns, artifact data and selection when filtering and changing applications' {
            InModuleScope EvergreenUI {
                Set-EwSetting -Name ArtifactHiddenColumns -Value 'Architecture,Channel'
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $artifact = [PSCustomObject]@{ Version = '1.0'; Architecture = 'x64'; Channel = 'Stable'; Date = $null; URI = 'https://example.test/app.exe' }
                    $state.AllArtifacts = @($artifact)
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $state.ArtifactsGrid.SelectedItem = $artifact
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Date'
                    $item.IsChecked = $false
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    $state.ArtifactsGrid.SelectedItem | Should -Be $artifact
                    $state.ArtifactsGrid.ItemsSource[0] | Should -Be $artifact
                    ($state.ArtifactFilterControls['Architecture'].CheckBoxes | Where-Object Tag -eq 'x64').IsChecked = $true
                    $state.ArtifactsGrid.ItemsSource[0] | Should -Be $artifact
                    Mock Invoke-EwWorkbenchJob {}
                    $app = [PSCustomObject]@{ Name = 'OtherApp'; FriendlyName = 'Other application' }
                    $state.AppsListView.ItemsSource = @($app)
                    $state.AppsListView.SelectedItem = $app
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '2.0'; Architecture = 'x86'; URI = 'https://example.test/other.exe' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    foreach ($column in $state.ArtifactsGrid.Columns) {
                        $column.Visibility.ToString() | Should -Be $(if ($column.Header -in @('Architecture', 'Channel', 'Date')) { 'Collapsed' } else { 'Visible' })
                    }
                    @($state.ArtifactsGrid.Columns | ForEach-Object Header) | Should -Be @('Version', 'Architecture', 'URI')
                    (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Architecture,Channel,Date'
                }
                finally { $window.Close() }
            }
        }

        It 'reports invalid saved columns without allowing required columns to disappear' {
            InModuleScope EvergreenUI {
                $settings = Get-EwSetting
                $settings.ArtifactHiddenColumns = 'Version,uri,Unknown,architecture'
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings $settings
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '1'; Architecture = 'x64'; URI = 'https://example.test/a.exe' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    foreach ($column in $state.ArtifactsGrid.Columns) {
                        $column.Visibility.ToString() | Should -Be $(if ($column.Header -eq 'Architecture') { 'Collapsed' } else { 'Visible' })
                    }
                    $state.ActivityLog.Text | Should -Match 'Ignoring invalid saved hidden artifact columns'
                    $settings.ArtifactHiddenColumns | Should -Be 'Version,uri,Unknown,architecture'
                }
                finally { $window.Close() }
                $settings.ArtifactHiddenColumns = @('Version', 'Date')
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings $settings
                    @($state.ArtifactsGrid.Columns | Where-Object { $_.Visibility -ne [System.Windows.Visibility]::Visible }).Count | Should -Be 0
                    $state.ActivityLog.Text | Should -Match 'expected a comma-separated string'
                }
                finally { $window.Close() }
            }
        }

        It 'reports a failed save and includes earlier live choices in the next save' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.AllArtifacts = @([PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Channel = 'Stable'; URI = 'https://example.test/a.exe' })
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    Mock Write-EwSetting { throw 'settings write failed' }
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Architecture'
                    $item.IsChecked = $false
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    $item.Tag.Visibility.ToString() | Should -Be 'Collapsed'
                    $state.ActivityLog.Text | Should -Match 'Could not save ArtifactHiddenColumns.*settings write failed'
                    Mock Write-EwSetting {}
                    Mock Set-EwSetting {}
                    $item = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Channel'
                    $item.IsChecked = $false
                    $item.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                    Should -Invoke Set-EwSetting -Exactly 1 -ParameterFilter {
                        $Name -eq 'ArtifactHiddenColumns' -and $Value -eq 'Architecture,Channel'
                    }
                    $state.Settings.ArtifactHiddenColumns | Should -Be 'Architecture,Channel'
                }
                finally { $window.Close() }
            }
        }
    }

    Context 'Artifact CSV export' {
        BeforeEach {
            $exportTestAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
        }

        AfterEach {
            $env:APPDATA = $exportTestAppData
        }

        It 'enables export only while the grid contains artifacts' {
            InModuleScope EvergreenUI {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $window.WindowStartupLocation = 'Manual'
                    $window.Left = -10000
                    $window.Top = -10000
                    $window.Show()
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $state.ExportArtifactsButton.IsEnabled | Should -BeFalse
                    [System.Windows.Automation.AutomationProperties]::GetName($state.ExportArtifactsButton) |
                        Should -Be 'Export artifacts to CSV'
                    Mock New-EwWorkbenchArtifactExportDialog {}
                    Invoke-EwWorkbenchArtifactExport -State $state
                    Should -Invoke New-EwWorkbenchArtifactExportDialog -Exactly 0
                    $state.ActivityLog.Text | Should -Match 'There are no artifacts to export'

                    $state.AllArtifacts = @(
                        [PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Channel = 'Stable'; URI = 'https://example.test/a.exe' }
                        [PSCustomObject]@{ Version = '2'; Architecture = 'x86'; Channel = 'Preview'; URI = 'https://example.test/b.exe' }
                    )
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    $state.ExportArtifactsButton.IsEnabled | Should -BeTrue
                    ($state.ArtifactFilterControls['Architecture'].CheckBoxes | Where-Object Tag -eq 'x64').IsChecked = $true
                    ($state.ArtifactFilterControls['Channel'].CheckBoxes | Where-Object Tag -eq 'Preview').IsChecked = $true
                    $state.ArtifactsGrid.Items.Count | Should -Be 0
                    $state.ExportArtifactsButton.IsEnabled | Should -BeFalse
                    ($state.ArtifactFilterControls['Channel'].CheckBoxes | Where-Object Tag -eq 'Preview').IsChecked = $false
                    $state.ExportArtifactsButton.IsEnabled | Should -BeTrue
                    $state.ArtifactsGrid.ItemsSource = @()
                    $state.ExportArtifactsButton.IsEnabled | Should -BeFalse
                }
                finally { $window.Close() }
            }
        }

        It 'exports the filtered sorted grid snapshot with visible columns in display order' {
            InModuleScope EvergreenUI -Parameters @{ CsvPath = (Join-Path -Path $TestDrive -ChildPath 'artifacts [test].csv') } {
                param($CsvPath)

                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $richValue = "caf$([char]0x00e9), `"quoted`"`nnext line"
                    $state.AllArtifacts = @(
                        [PSCustomObject]@{ Version = '2'; Architecture = 'x64'; Channel = 'Stable'; Release = $richValue; Size = 12345; URI = 'https://example.test/two.exe' }
                        [PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Channel = 'Preview'; Release = $null; URI = 'https://example.test/one.exe' }
                        [PSCustomObject]@{ Version = '3'; Architecture = 'x86'; Channel = 'Stable'; Release = $null; URI = 'https://example.test/three.exe' }
                    )
                    Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                    ($state.ArtifactFilterControls['Architecture'].CheckBoxes | Where-Object Tag -eq 'x64').IsChecked = $true
                    $state.ArtifactsGrid.Items.SortDescriptions.Add([System.ComponentModel.SortDescription]::new(
                        'Version', [System.ComponentModel.ListSortDirection]::Ascending
                    ))
                    $state.ArtifactsGrid.SelectedIndex = 0
                    ($state.ArtifactsGrid.Columns | Where-Object Header -eq 'URI').DisplayIndex = 0
                    $channelItem = $state.ShowArtifactColumnsButton.ContextMenu.Items | Where-Object Header -eq 'Channel'
                    $channelItem.IsChecked = $false
                    $channelItem.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))

                    $script:artifactExportDialog = [PSCustomObject]@{
                        FileName = $CsvPath
                        Owner = $null
                        Grid = $state.ArtifactsGrid
                    }
                    $script:artifactExportDialog | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value {
                        param($Owner)
                        $this.Owner = $Owner
                        $this.Grid.ItemsSource = @([PSCustomObject]@{ Version = '999'; URI = 'https://example.test/new.exe' })
                        return $true
                    }
                    Mock New-EwWorkbenchArtifactExportDialog { $script:artifactExportDialog }
                    Set-Content -LiteralPath $CsvPath -Value 'previous contents'
                    $state.ExportArtifactsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                    ))

                    $script:artifactExportDialog.Owner | Should -Be $window
                    [BitConverter]::ToString((Get-Content -LiteralPath $CsvPath -AsByteStream -TotalCount 3)) | Should -Be 'EF-BB-BF'
                    $csv = @(Import-Csv -LiteralPath $CsvPath)
                    $csv.Count | Should -Be 2
                    @($csv[0].PSObject.Properties.Name) |
                        Should -Be @('URI', 'Version', 'Architecture', 'Release', 'Size')
                    @($csv.Version) | Should -Be @('1', '2')
                    $csv[0].URI | Should -Be 'https://example.test/one.exe'
                    $csv[0].Release | Should -Be ''
                    $csv[1].URI | Should -Be 'https://example.test/two.exe'
                    $csv[1].Release | Should -BeExactly $richValue
                    $csv[0].Size | Should -Be ''
                    $csv[1].Size | Should -Be '12345'
                    $state.ActivityLog.Text | Should -Match 'Exported 2 artifacts'
                }
                finally {
                    $script:artifactExportDialog = $null
                    $window.Close()
                }
            }
        }

        It 'offers a CSV save dialog with overwrite confirmation and honours cancellation' {
            InModuleScope EvergreenUI -Parameters @{ CsvPath = (Join-Path -Path $TestDrive -ChildPath 'cancelled-export.csv') } {
                param($CsvPath)

                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $dialog = New-EwWorkbenchArtifactExportDialog
                    $dialog.Filter | Should -Be 'CSV files (*.csv)|*.csv'
                    $dialog.DefaultExt | Should -Be 'csv'
                    $dialog.AddExtension | Should -BeTrue
                    $dialog.OverwritePrompt | Should -BeTrue
                    $state.ArtifactsGrid.ItemsSource = @([PSCustomObject]@{ Version = '1'; URI = 'https://example.test/a.exe' })
                    $script:artifactExportDialog = [PSCustomObject]@{ FileName = $CsvPath }
                    $script:artifactExportDialog | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value { param($Owner) return $false }
                    Mock New-EwWorkbenchArtifactExportDialog { $script:artifactExportDialog }
                    Set-Content -LiteralPath $CsvPath -Value 'previous contents'
                    $state.ExportArtifactsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                    ))
                    Should -Invoke New-EwWorkbenchArtifactExportDialog -Exactly 1
                    (Get-Content -LiteralPath $CsvPath -Raw).Trim() | Should -BeExactly 'previous contents'
                    $state.ActivityLog.Text | Should -Not -Match 'Exported .* artifacts'
                }
                finally {
                    $script:artifactExportDialog = $null
                    $window.Close()
                }
            }
        }

        It 'reports file and dialog errors without claiming a successful export' {
            InModuleScope EvergreenUI -Parameters @{ CsvPath = (Join-Path -Path $TestDrive -ChildPath 'missing-folder\export.csv') } {
                param($CsvPath)

                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.ArtifactsGrid.ItemsSource = @([PSCustomObject]@{ Version = '1'; URI = 'https://example.test/a.exe' })
                    $script:artifactExportDialog = [PSCustomObject]@{ FileName = $CsvPath }
                    $script:artifactExportDialog | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value { param($Owner) return $true }
                    Mock New-EwWorkbenchArtifactExportDialog { $script:artifactExportDialog }
                    $click = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
                    $state.ExportArtifactsButton.RaiseEvent($click)
                    $state.ActivityLog.Text | Should -Match 'Could not export artifacts:'
                    $state.ActivityLog.Text | Should -Not -Match 'Exported .* artifacts'
                    $state.StatusLabel.Tag | Should -Be 'Error'
                    Test-Path -LiteralPath $CsvPath | Should -BeFalse

                    Mock New-EwWorkbenchArtifactExportDialog { throw 'save dialog failed' }
                    $state.ExportArtifactsButton.RaiseEvent($click)
                    $state.ActivityLog.Text | Should -Match 'Could not export artifacts: save dialog failed'
                }
                finally {
                    $script:artifactExportDialog = $null
                    $window.Close()
                }
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

    It 'keeps Apps actions aligned at <Width>x<Height>, font <FontSize>, <Theme>, tray <TrayHeight>' -ForEach @(
        @{ Width = 960; Height = 820; FontSize = 12; TrayHeight = 180; Theme = 'Light' }
        @{ Width = 1200; Height = 820; FontSize = 12; TrayHeight = 180; Theme = 'Dark' }
        @{ Width = 960; Height = 820; FontSize = 20; TrayHeight = 180; Theme = 'Light' }
        @{ Width = 960; Height = 660; FontSize = 12; TrayHeight = 600; Theme = 'Dark' }
    ) {
        InModuleScope EvergreenUI -Parameters @{
            WindowWidth = $Width; WindowHeight = $Height; FontSize = $FontSize
            TrayHeight = $TrayHeight; Theme = $Theme
        } {
            param($WindowWidth, $WindowHeight, $FontSize, $TrayHeight, $Theme)

            $window = Get-EwWorkbenchWindow
            $state = $null
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Apps'
                $settings.DownloadTrayHeight = $TrayHeight
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $window.Width = $WindowWidth
                $window.Height = $WindowHeight
                $window.ThemeMode = [System.Windows.ThemeMode]::$Theme
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $buttons = @(
                    $state.ClearCompletedQueueButton
                    $state.ChangeDownloadPathButton
                    $state.DownloadTrayActionButton
                    $state.QueueDownloadButton
                    $state.DownloadNowButton
                )
                foreach ($button in $buttons) {
                    $button.FontSize = $FontSize
                }
                $state.ArtifactCountLabel.Text = 'Showing 25 of 500 artifacts'
                $artifact = [PSCustomObject]@{
                    Version = '1.0'
                    Architecture = 'x64'
                    URI = 'https://example.test/installer.exe'
                }
                $state.ArtifactsGrid.ItemsSource = @($artifact)
                $state.ArtifactsGrid.SelectedItem = $artifact
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                $queueSeparator = $window.FindName('QueueActionsSeparator')
                $artifactSeparator = $window.FindName('ArtifactActionsSeparator')
                $queueSeparator | Should -BeOfType ([System.Windows.Controls.Border])
                $artifactSeparator | Should -BeOfType ([System.Windows.Controls.Border])
                $queueSeparator.Background | Should -Not -BeNullOrEmpty
                $artifactSeparator.Background | Should -Not -BeNullOrEmpty
                $elements = @(
                    $buttons[0]
                    $queueSeparator
                    $buttons[1]
                    $buttons[2]
                    $artifactSeparator
                    $buttons[3]
                    $buttons[4]
                )

                foreach ($phase in 'Empty', 'Collapsed', 'Expanded', 'Downloading') {
                    switch ($phase) {
                        'Empty' {
                            $state.DownloadTrayPanel.Visibility.ToString() | Should -Be 'Collapsed'
                            $state.ClearCompletedQueueButton.IsEnabled | Should -BeFalse
                            $state.DownloadTrayActionButton.IsEnabled | Should -BeFalse
                            $state.QueueDownloadButton.IsEnabled | Should -BeTrue
                            $state.DownloadNowButton.IsEnabled | Should -BeTrue
                        }
                        'Collapsed' {
                            foreach ($status in 'Pending', 'Downloaded') {
                                $state.Queue.Add([PSCustomObject]@{
                                        Id = $status
                                        AppName = 'Example'
                                        Version = '1.0'
                                        Architecture = 'x64'
                                        Status = $status
                                        URI = 'https://example.test/installer.exe'
                                        SavedPath = ''
                                    })
                            }
                            $state.DownloadTrayContent.Visibility.ToString() | Should -Be 'Collapsed'
                            $state.ClearCompletedQueueButton.IsEnabled | Should -BeTrue
                            $state.DownloadTrayActionButton.IsEnabled | Should -BeTrue
                        }
                        'Expanded' {
                            $state.DownloadTrayToggleButton.IsChecked = $true
                            $state.DownloadTrayContent.Visibility.ToString() | Should -Be 'Visible'
                        }
                        'Downloading' {
                            $state.ActiveJobId = 'running'
                            $state.ActiveJobKind = 'Downloads'
                            Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
                            $state.DownloadTrayActionButton.Content | Should -Be 'Stop'
                            $state.DownloadTrayActionButton.IsEnabled | Should -BeTrue
                            $state.QueueDownloadButton.IsEnabled | Should -BeFalse
                            $state.DownloadNowButton.IsEnabled | Should -BeFalse
                        }
                    }
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $previousRight = 0
                    $center = $null
                    foreach ($element in $elements) {
                        $element.IsVisible | Should -BeTrue -Because "the action row is visible when the queue is $phase"
                        $element.ActualWidth | Should -BeGreaterThan 0
                        $position = $element.TranslatePoint([System.Windows.Point]::new(0, 0), $state.AppsPanel)
                        [Math]::Round($position.X - $previousRight, 1) | Should -BeGreaterOrEqual 0
                        $previousRight = $position.X + $element.ActualWidth
                        [Math]::Round($previousRight - $state.AppsPanel.ActualWidth, 1) | Should -BeLessOrEqual 0
                        [Math]::Round($position.Y, 1) | Should -BeGreaterOrEqual 0
                        [Math]::Round($position.Y + $element.ActualHeight - $state.AppsPanel.ActualHeight, 1) |
                            Should -BeLessOrEqual 0
                        $elementCenter = $position.Y + ($element.ActualHeight / 2)
                        if ($null -eq $center) {
                            $center = $elementCenter
                        }
                        [Math]::Abs($elementCenter - $center) | Should -BeLessOrEqual 1
                    }

                    if ($phase -eq 'Collapsed') {
                        $click = [System.Windows.RoutedEventArgs]::new(
                            [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                        )
                        $state.ClearCompletedQueueButton.RaiseEvent($click)
                        $state.Queue.Count | Should -Be 1
                        $state.Queue[0].Status | Should -Be 'Pending'
                    }
                }
            }
            finally {
                if ($null -ne $state) {
                    $state.ActiveJobId = $null
                    $state.ActiveJobKind = ''
                }
                $window.Close()
            }
        }
    }

    It 'opens download folder settings from the action row when the queue is empty' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Apps'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $state.UiStateReady = $false
                Mock Invoke-EwWorkbenchSettingsRefresh {}
                $opened = @{ Value = $false }
                $browseButton = [System.Windows.Controls.Button]::new()
                $browseButton.Add_Click({ $opened.Value = $true }.GetNewClosure())
                $state.BrowseDownloadFolderButton = $browseButton
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.ChangeDownloadPathButton.RaiseEvent($click)
                $state.NavSettings.IsChecked | Should -BeTrue
                $opened.Value | Should -BeTrue
            }
            finally {
                $window.Close()
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

    It 'shows the application catalog without column headers' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $grid = $window.FindName('AppsListView')
                $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::None)
                $grid.CanUserSortColumns | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'centres both favourite stars in the column when resized' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $grid = $window.FindName('AppsListView')
                $grid.ItemsSource = @(
                    [PSCustomObject]@{ Name = 'Example'; FriendlyName = 'Example'; IsFavourite = $false }
                    [PSCustomObject]@{ Name = 'Favourite'; FriendlyName = 'Favourite'; IsFavourite = $true }
                )
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($width in 72, 100) {
                    $grid.Columns[1].Width = [System.Windows.Controls.DataGridLength]::new($width)
                    $window.UpdateLayout()
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    foreach ($index in 0, 1) {
                        $row = $grid.ItemContainerGenerator.ContainerFromIndex($index)
                        $content = $grid.Columns[1].GetCellContent($row)
                        $button = [System.Windows.Media.VisualTreeHelper]::GetChild($content, 0)
                        $glyph = $button.Template.FindName('ContentPresenter', $button)
                        $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($content)
                        while ($cell -isnot [System.Windows.Controls.DataGridCell]) {
                            $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($cell)
                        }
                        $glyph | Should -Not -BeNullOrEmpty
                        $position = $glyph.TranslatePoint([System.Windows.Point]::new(0, 0), $cell)
                        $offset = $position.X + ($glyph.ActualWidth / 2) - ($cell.ActualWidth / 2)
                        [Math]::Abs($offset) | Should -BeLessOrEqual 1 -Because "the star is centred in a $width pixel column"
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps favourite <BrushProperty> colours native across themes and loading transitions' -ForEach @(
        @{ BrushProperty = 'Foreground' }
        @{ BrushProperty = 'Background' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ BrushProperty = $BrushProperty } {
            param($BrushProperty)

            function Find-TestVisual {
                param([System.Windows.DependencyObject]$Parent, [type]$Type)

                if ($Type.IsInstanceOfType($Parent)) { return $Parent }
                for ($index = 0; $index -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent); $index++) {
                    $match = Find-TestVisual -Parent ([System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $index)) -Type $Type
                    if ($null -ne $match) { return $match }
                }
            }

            $window = Get-EwWorkbenchWindow
            try {
                $settings = Get-EwSetting
                $settings.StartupView = 'Apps'
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $state.SuppressAppSelection = $true
                $state.AppsListView.ItemsSource = @(
                    [PSCustomObject]@{ Name = 'Example'; FriendlyName = 'Example'; IsFavourite = $false }
                    [PSCustomObject]@{ Name = 'Favourite'; FriendlyName = 'Favourite'; IsFavourite = $true }
                )
                $reference = [System.Windows.Controls.Button]::new()
                $reference.Content = [string][char]0xE734
                $reference.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe Fluent Icons')
                $reference.FontSize = 16
                $reference.Padding = [System.Windows.Thickness]::new(4, 0, 4, 0)
                $reference.Background = [System.Windows.Media.Brushes]::Transparent
                $reference.BorderThickness = [System.Windows.Thickness]::new(0)
                $reference.HorizontalAlignment = 'Right'
                $reference.VerticalAlignment = 'Bottom'
                $null = $window.Content.Children.Add($reference)
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()

                foreach ($mode in 'Light', 'Dark', 'Light') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    foreach ($selected in $false, $true) {
                        foreach ($busy in $false, $true, $false) {
                            $state.ActiveJobKind = if ($busy) { 'Artifacts' } else { '' }
                            Invoke-EwWorkbenchBusyState -State $state -IsBusy $busy
                            $reference.IsEnabled = -not $busy
                            foreach ($index in 0, 1) {
                                $state.AppsListView.SelectedIndex = if ($selected) { $index } else { -1 }
                                $window.UpdateLayout()
                                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                                $row = $state.AppsListView.ItemContainerGenerator.ContainerFromIndex($index)
                                $content = $state.AppsListView.Columns[1].GetCellContent($row)
                                $button = Find-TestVisual -Parent $content -Type ([System.Windows.Controls.Button])
                                $button | Should -Not -BeNullOrEmpty
                                $button.IsEnabled | Should -Be (-not $busy)
                                [int][char]$button.Content | Should -Be $(if ($index -eq 1) { 0xE735 } else { 0xE734 })
                                $visualType = if ($BrushProperty -eq 'Foreground') {
                                    [System.Windows.Controls.TextBlock]
                                }
                                else {
                                    [System.Windows.Controls.Border]
                                }
                                $actual = Find-TestVisual -Parent $button -Type $visualType
                                $expected = Find-TestVisual -Parent $reference -Type $visualType
                                $actual | Should -Not -BeNullOrEmpty
                                $expected | Should -Not -BeNullOrEmpty
                                $actual.$BrushProperty.Color | Should -Be $expected.$BrushProperty.Color -Because (
                                    "favourite $BrushProperty follows Fluent in $mode mode, busy=$busy, selected=$selected"
                                )
                            }
                        }
                    }
                }
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
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $navigationNames = 'NavApps', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavSettings', 'NavAbout'
                foreach ($mode in 'Light', 'Dark', 'Light') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $expected = if ([System.Windows.SystemParameters]::HighContrast) {
                        $window.TryFindResource([System.Windows.SystemColors]::HighlightBrushKey)
                    }
                    else {
                        $window.TryFindResource('AccentFillColorDefaultBrush')
                    }
                    foreach ($name in $navigationNames) {
                        $button = $window.FindName($name)
                        $button.Foreground.Color |
                            Should -Be $window.TryFindResource('TextFillColorPrimaryBrush').Color
                        $button.IsChecked = $true
                        $indicator = $button.Template.FindName('SelectedIndicator', $button)
                        $indicator.Visibility | Should -Be 'Visible'
                        $indicator.Background.Color | Should -Be $expected.Color
                    }
                    $window.FindName('NavIntune').Content | Should -Be 'Intune'
                }
                foreach ($accent in [System.Windows.Media.Brushes]::Coral, [System.Windows.Media.Brushes]::CornflowerBlue) {
                    $window.Resources['AccentFillColorDefaultBrush'] = $accent
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $expected = if ([System.Windows.SystemParameters]::HighContrast) {
                        $window.TryFindResource([System.Windows.SystemColors]::HighlightBrushKey)
                    }
                    else {
                        $accent
                    }
                    foreach ($name in $navigationNames) {
                        $button = $window.FindName($name)
                        $indicator = $button.Template.FindName('SelectedIndicator', $button)
                        $indicator.Background.Color | Should -Be $expected.Color
                    }
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses the system highlight for navigation in high contrast' {
        InModuleScope EvergreenUI {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            $xamlPath = Join-Path -Path (Split-Path -Path $script:ewModulePath -Parent) -ChildPath 'Resources\EvergreenWorkbench.xaml'
            [xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
            $namespaces = [System.Xml.XmlNamespaceManager]::new($xaml.NameTable)
            $namespaces.AddNamespace('wpf', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
            $namespaces.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
            $trigger = $xaml.SelectSingleNode(
                "//wpf:Style[@x:Key='NavigationButtonStyle']//wpf:DataTrigger[@Binding='{Binding Path=(SystemParameters.HighContrast)}']",
                $namespaces
            )
            $trigger | Should -Not -BeNullOrEmpty
            $trigger.SetAttribute('Binding', '{Binding TestHighContrast}')
            $window = [System.Windows.Markup.XamlReader]::Parse($xaml.OuterXml)
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Resources['AccentFillColorDefaultBrush'] = [System.Windows.Media.Brushes]::Coral
                $window.Show()
                foreach ($highContrast in $true, $false, $true) {
                    $window.DataContext = [PSCustomObject]@{ TestHighContrast = $highContrast }
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $button = $window.FindName('NavApps')
                    $indicator = $button.Template.FindName('SelectedIndicator', $button)
                    $expected = if ($highContrast) {
                        $window.TryFindResource([System.Windows.SystemColors]::HighlightBrushKey)
                    }
                    else {
                        $window.TryFindResource('AccentFillColorDefaultBrush')
                    }
                    $indicator.Background.Color | Should -Be $expected.Color
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'adapts navigation to window width while keeping labels available to automation' -Skip:$isGitHubRunner {
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

    It 'limits status messages to two lines in <Theme> mode at width <Width>' -ForEach @(
        @{ Theme = 'Light'; Width = 1200 }
        @{ Theme = 'Light'; Width = 960 }
        @{ Theme = 'Dark'; Width = 1200 }
        @{ Theme = 'Dark'; Width = 960 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Theme = $Theme; Width = $Width } {
            param($Theme, $Width)

            $window = Get-EwWorkbenchWindow
            try {
                $window.ThemeMode = [System.Windows.ThemeMode]::$Theme
                $window.Width = $Width
                $window.Show()
                $status = $window.FindName('StatusLabel')
                foreach ($message in @(
                    ('A long status message that must not expand the header. ' * 50)
                    "First line`nSecond line`nThird line`nFourth line"
                    ('x' * 2000)
                )) {
                    $status.Text = $message
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()

                    $status.ActualHeight | Should -BeGreaterThan $status.LineHeight
                    $status.ActualHeight | Should -BeLessOrEqual ($status.LineHeight * 2)
                    $status.TextTrimming | Should -Be ([System.Windows.TextTrimming]::CharacterEllipsis)
                    $status.Text | Should -BeExactly $message
                    $status.ToolTip | Should -BeExactly $message
                }

                $status.Text = 'Ready'
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $status.ActualHeight | Should -BeGreaterThan 0
                $status.ActualHeight | Should -BeLessOrEqual $status.LineHeight
                $status.ToolTip | Should -BeExactly 'Ready'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'preserves the full logged status message when its display is trimmed' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.Show()
                $message = 'A complete failure message that remains available in Activity. ' * 50
                Write-EwWorkbenchLog -State $state -Message $message -Level Error
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()

                $state.StatusLabel.ActualHeight | Should -BeLessOrEqual ($state.StatusLabel.LineHeight * 2)
                $state.StatusLabel.Text | Should -BeExactly $message
                $state.StatusLabel.ToolTip | Should -BeExactly $message
                $state.StatusLabel.Tag | Should -Be 'Error'
                $state.ActivityLog.Text | Should -BeLike "*$message*"
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

    It 'honours the closing guard and persists window size through native close' -Skip:$isGitHubRunner {
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
                                Path = 'C:\Library\Contoso App\contoso.msi'
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
                $version.Location | Should -Be 'C:\Library\Contoso App\contoso.msi'
            }
            finally {
                $window.Close()
            }
        }
    }

    Context 'Library removal' {
        BeforeEach {
            $script:removalRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $appPath = Join-Path -Path $removalRoot -ChildPath 'Example'
            $null = New-Item -Path $appPath -ItemType Directory -Force
            @{ Applications = @(@{ Name = 'Example' }) } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'EvergreenLibrary.json')
            $entries = @(
                @{ Version = '1'; Architecture = 'x64'; Type = 'msi'; Path = 'a.msi' }
                @{ Version = '1'; Architecture = 'x86'; Type = 'msi'; Path = 'b.msi' }
                @{ Version = '2'; Architecture = 'x64'; Type = 'exe'; Path = 'c.exe' }
            )
            ConvertTo-Json -InputObject $entries -Depth 10 |
                Set-Content -LiteralPath (Join-Path -Path $appPath -ChildPath 'Example.json')
            foreach ($file in 'a.msi', 'b.msi', 'c.exe') {
                Set-Content -LiteralPath (Join-Path -Path $appPath -ChildPath $file) -Value 'test content'
            }
        }

        It 'shows local file locations for library versions' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $manifestPath = Join-Path -Path $Root -ChildPath 'Example\Example.json'
                $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $entries[0].Path = @('a.msi', 'nested\extra.msi')
                $entries[1].Path = Join-Path -Path $Root -ChildPath 'Example\b.msi'
                $entries[2].PSObject.Properties.Remove('Path')
                ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath

                Push-Location -LiteralPath $Root
                try { $application = Get-EwLibrary -Path '.' }
                finally { Pop-Location }
                $window = Get-EwWorkbenchWindow
                try {
                    $settings = Get-EwSetting
                    $settings.StartupView = 'Library'
                    $state = Get-EwWorkbenchState -Window $window -Settings $settings
                    $state.LibraryListView.ItemsSource = @($application)
                    $state.LibraryListView.SelectedItem = $application
                    $versions = @($state.LibraryVersionsListView.ItemsSource)
                    $expected = @(
                        (Join-Path -Path $Root -ChildPath 'Example\a.msi'),
                        (Join-Path -Path $Root -ChildPath 'Example\nested\extra.msi')
                    ) -join '; '
                    $versions[0].Location | Should -Be $expected
                    $versions[1].Location | Should -Be (Join-Path -Path $Root -ChildPath 'Example\b.msi')
                    $versions[2].Location | Should -Be 'Not recorded'

                    $column = $state.LibraryVersionsListView.Columns | Where-Object { $_.Header -eq 'Location' }
                    $column | Should -Not -BeNullOrEmpty
                    $window.Show()
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $cell = $column.GetCellContent($versions[0])
                    $cell.Text | Should -Be $expected
                    $cell.ToolTip | Should -Be $expected
                    $cell.ActualWidth | Should -BeGreaterThan 0
                }
                finally { $window.Close() }
            }
        }

        It 'opens the library folder from the application and version context menus' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $manifestPath = Join-Path -Path $Root -ChildPath 'Example\Example.json'
                $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $entries[1].Path = 'nested\b.msi'
                $entries[2].PSObject.Properties.Remove('Path')
                ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath
                $null = New-Item -Path (Join-Path -Path $Root -ChildPath 'Example\nested') -ItemType Directory -Force
                $application = Get-EwLibrary -Path $Root
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    Mock Start-Process {}
                    $state.LibraryListView.ItemsSource = @($application)
                    $state.LibraryListView.SelectedItem = $application
                    $openingArgs = {
                        $eventArgs = [System.Windows.Controls.ContextMenuEventArgs].GetConstructor(
                            [Reflection.BindingFlags]'NonPublic, Instance', $null, @([object], [bool]), $null
                        ).Invoke(@($null, $false))
                        $eventArgs.RoutedEvent = [System.Windows.FrameworkElement]::ContextMenuOpeningEvent
                        $eventArgs
                    }
                    $click = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent)

                    $appMenuItem = $state.LibraryListView.ContextMenu.Items[0]
                    $appMenuItem.Header | Should -Be 'Open folder'
                    $state.LibraryListView.RaiseEvent((& $openingArgs))
                    $appMenuItem.IsEnabled | Should -BeTrue
                    $appMenuItem.RaiseEvent($click)
                    $appFolder = Join-Path -Path $Root -ChildPath 'Example'
                    Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                        $FilePath -eq 'explorer.exe' -and $ArgumentList -eq ('"{0}"' -f $appFolder)
                    }

                    $versionMenuItem = $state.LibraryVersionsListView.ContextMenu.Items[0]
                    $versionMenuItem.Header | Should -Be 'Open folder'
                    $versions = @($state.LibraryVersionsListView.ItemsSource)
                    $state.LibraryVersionsListView.SelectedItem = $versions[1]
                    $state.LibraryVersionsListView.RaiseEvent((& $openingArgs))
                    $versionMenuItem.IsEnabled | Should -BeTrue
                    $versionMenuItem.RaiseEvent($click)
                    $nestedFolder = Join-Path -Path $appFolder -ChildPath 'nested'
                    Should -Invoke Start-Process -Exactly 1 -ParameterFilter { $ArgumentList -eq ('"{0}"' -f $nestedFolder) }

                    $state.LibraryVersionsListView.SelectedItem = $versions[2]
                    $state.LibraryVersionsListView.RaiseEvent((& $openingArgs))
                    $versionMenuItem.IsEnabled | Should -BeFalse

                    Remove-Item -LiteralPath $nestedFolder -Recurse -Force
                    $state.LibraryVersionsListView.SelectedItem = $versions[1]
                    $state.LibraryVersionsListView.RaiseEvent((& $openingArgs))
                    $versionMenuItem.RaiseEvent($click)
                    Should -Invoke Start-Process -Exactly 2
                    $state.ActivityLog.Text | Should -Match 'Could not open the library folder: .*does not exist'
                }
                finally { $window.Close() }
            }
        }

        It 'reports an invalid library location without hiding other versions' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $manifestPath = Join-Path -Path $Root -ChildPath 'Example\Example.json'
                $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $entries[0].Path = "invalid$([char]0)path"
                ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath
                $application = Get-EwLibrary -Path $Root
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.LibraryListView.ItemsSource = @($application)
                    $state.LibraryListView.SelectedItem = $application
                    $versions = @($state.LibraryVersionsListView.ItemsSource)
                    $versions | Should -HaveCount 3
                    $versions[0].Location | Should -Be 'Invalid path'
                    $versions[1].Location | Should -Be (Join-Path -Path $Root -ChildPath 'Example\b.msi')
                    $state.ActivityLog.Text | Should -Match 'Could not resolve a library location'
                }
                finally { $window.Close() }
            }
        }

        It 'shows the removal confirmation using the owner Fluent <Mode> theme' -ForEach @(
            @{ Mode = 'Light' }, @{ Mode = 'Dark' }, @{ Mode = 'System' }
        ) {
            InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; Root = $removalRoot } {
                $owner = Get-EwWorkbenchWindow
                $dialog = $null
                try {
                    $owner.ThemeMode = [System.Windows.ThemeMode]::$Mode
                    $owner.Show()
                    $rows = @(
                        [PSCustomObject]@{ Version = '1.0'; Architecture = 'x64'; Type = 'msi'; URI = 'https://example.test/a.msi' }
                        [PSCustomObject]@{ Version = '1.0'; Architecture = 'x86'; Type = 'exe'; URI = 'https://example.test/b.exe' }
                    )
                    $dialog = New-EwWorkbenchLibraryRemovalDialog -Owner $owner -Path $Root -Name 'Example & Co' -Row $rows -EntireApplication $false
                    $dialog.Show()
                    $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $dialog.UpdateLayout()

                    $dialog.Owner | Should -Be $owner
                    $dialog.ThemeMode | Should -Be $owner.ThemeMode
                    $dialog.WindowStartupLocation | Should -Be ([System.Windows.WindowStartupLocation]::CenterOwner)
                    $dialog.ShowInTaskbar | Should -BeFalse
                    $dialog.ResizeMode | Should -Be ([System.Windows.ResizeMode]::NoResize)
                    $dialog.SizeToContent | Should -Be ([System.Windows.SizeToContent]::WidthAndHeight)
                    $dialog.ActualWidth | Should -BeLessOrEqual $dialog.MaxWidth
                    $dialog.ActualHeight | Should -BeLessThan $dialog.MaxHeight
                    $dialog.TryFindResource('ApplicationBackgroundBrush').Color |
                        Should -Be $owner.TryFindResource('ApplicationBackgroundBrush').Color
                    $dialog.Foreground.Color | Should -Be $dialog.TryFindResource('TextFillColorPrimaryBrush').Color
                    $cancel = $dialog.FindName('CancelLibraryRemovalButton')
                    $cancel.Style | Should -Be $dialog.TryFindResource('AccentButtonStyle')
                    $cancel.IsDefault | Should -BeTrue
                    $cancel.IsCancel | Should -BeTrue
                    $dialog.FindName('ConfirmLibraryRemovalButton').IsDefault | Should -BeFalse
                    $dialog.FindName('LibraryRemovalApplicationText').Text | Should -Be 'Application: Example & Co'
                    $dialog.FindName('LibraryRemovalPathText').Text | Should -Be "Library: $Root"
                    $dialog.FindName('LibraryRemovalArtifactsHeadingText').Text | Should -Be 'Artifacts to remove: 2'
                    $items = @($dialog.FindName('LibraryRemovalArtifactsList').ItemsSource)
                    $items.Summary | Should -Be @('1.0 | x64 | msi', '1.0 | x86 | exe')
                    $items.URI | Should -Be @('https://example.test/a.msi', 'https://example.test/b.exe')
                }
                finally {
                    if ($null -ne $dialog) { $dialog.Close() }
                    $owner.Close()
                }
            }
        }

        It 'keeps long removal previews scrollable with the actions visible' -Skip:$isGitHubRunner {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $owner = Get-EwWorkbenchWindow
                $dialog = $null
                try {
                    $owner.Height = 660
                    $owner.FontSize = 20
                    $owner.Show()
                    $rows = @(1..80 | ForEach-Object {
                            [PSCustomObject]@{
                                Version = "2.0.$_"; Architecture = 'x64'; Type = 'msi'
                                URI = "https://example.test/$('longsegment' * 8)/$_.msi"
                            }
                        })
                    $longPath = Join-Path -Path $Root -ChildPath ('LongDirectory\' * 15)
                    $dialog = New-EwWorkbenchLibraryRemovalDialog -Owner $owner -Path $longPath -Name ('Long name ' * 8) -Row $rows -EntireApplication $false
                    $dialog.Show()
                    $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $dialog.UpdateLayout()

                    $dialog.FontSize | Should -Be 20
                    $dialog.ActualWidth | Should -BeLessOrEqual $dialog.MaxWidth
                    $dialog.ActualHeight | Should -BeLessOrEqual $dialog.MaxHeight
                    $dialog.FindName('LibraryRemovalPathText').Text | Should -Be "Library: $longPath"
                    $dialog.FindName('LibraryRemovalPathText').TextWrapping | Should -Be ([System.Windows.TextWrapping]::Wrap)
                    $items = @($dialog.FindName('LibraryRemovalArtifactsList').ItemsSource)
                    $items | Should -HaveCount 80
                    $items[-1].URI | Should -Be $rows[-1].URI
                    $scroll = $dialog.FindName('LibraryRemovalDetailsScrollViewer')
                    $scroll.ScrollableHeight | Should -BeGreaterThan 0
                    $scroll.ScrollToEnd()
                    $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $scroll.VerticalOffset | Should -Be $scroll.ScrollableHeight
                    $confirm = $dialog.FindName('ConfirmLibraryRemovalButton')
                    $position = $confirm.TranslatePoint([System.Windows.Point]::new(0, 0), $dialog)
                    ($position.Y + $confirm.ActualHeight) | Should -BeLessOrEqual $dialog.ActualHeight
                }
                finally {
                    if ($null -ne $dialog) { $dialog.Close() }
                    $owner.Close()
                }
            }
        }

        It 'shows whole-application wording even when there are no recorded artifacts' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $owner = Get-EwWorkbenchWindow
                $dialog = $null
                try {
                    $owner.Show()
                    $dialog = New-EwWorkbenchLibraryRemovalDialog -Owner $owner -Path $Root -Name Example -Row @() -EntireApplication $true
                    $dialog.FindName('LibraryRemovalHeadingText').Text | Should -Be 'Remove application from the library?'
                    $dialog.FindName('LibraryRemovalArtifactsHeadingText').Text | Should -Be 'No recorded artifacts'
                    $dialog.FindName('ConfirmLibraryRemovalButton').Content | Should -Be 'Remove application'
                    @($dialog.FindName('LibraryRemovalArtifactsList').ItemsSource) | Should -HaveCount 0
                }
                finally {
                    if ($null -ne $dialog) { $dialog.Close() }
                    $owner.Close()
                }
            }
        }

        It 'returns <Accepted> for <Action> in the modal confirmation' -ForEach @(
            @{ Action = 'Return'; Accepted = $false }
            @{ Action = 'Escape'; Accepted = $false }
            @{ Action = 'Cancel'; Accepted = $false }
            @{ Action = 'Close'; Accepted = $false }
            @{ Action = 'Remove'; Accepted = $true }
        ) {
            if ($env:GITHUB_ACTIONS -eq 'true' -and $Action -in 'Return', 'Escape') {
                Set-ItResult -Skipped -Because 'Keyboard focus requires an interactive desktop.'
                return
            }
            InModuleScope EvergreenUI -Parameters @{ Action = $Action; Accepted = $Accepted; Root = $removalRoot } {
                $owner = Get-EwWorkbenchWindow
                $observed = @{ Action = $Action; InitiallyFocused = $false; VisibleAfter = $null }
                try {
                    $owner.Show()
                    $owner.Dispatcher.BeginInvoke([action]{
                        $dialog = @($owner.OwnedWindows)[0]
                        $cancel = $dialog.FindName('CancelLibraryRemovalButton')
                        $observed.InitiallyFocused = $cancel.IsKeyboardFocused
                        if ($observed.Action -in 'Return', 'Escape') {
                            $key = [System.Windows.Input.Key]::Parse([System.Windows.Input.Key], $observed.Action)
                            $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                                [System.Windows.Input.Keyboard]::PrimaryDevice,
                                [System.Windows.PresentationSource]::FromVisual($dialog), 0, $key
                            )
                            $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                            $null = [System.Windows.Input.InputManager]::Current.ProcessInput($keyArgs)
                        }
                        elseif ($observed.Action -in 'Cancel', 'Remove') {
                            $button = if ($observed.Action -eq 'Cancel') { $cancel } else { $dialog.FindName('ConfirmLibraryRemovalButton') }
                            $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                            $provider = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
                            $provider.Invoke()
                            $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        }
                        else {
                            $dialog.Close()
                        }
                        $observed.VisibleAfter = $dialog.IsVisible
                        if ($dialog.IsVisible) { $dialog.Close() }
                    }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
                    $rows = @([PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Type = 'msi'; URI = 'https://example.test/a.msi' })
                    $result = Confirm-EwWorkbenchLibraryRemoval -Window $owner -Path $Root -Name Example -Row $rows -EntireApplication $false
                    $result | Should -Be $Accepted
                    if ($env:GITHUB_ACTIONS -ne 'true') { $observed.InitiallyFocused | Should -BeTrue }
                    $observed.VisibleAfter | Should -BeFalse
                }
                finally { $owner.Close() }
            }
        }

        It 'requires confirmation for both actions and starts no job when declined' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.LibraryPathBox.Text = $Root
                    Invoke-EwWorkbenchLibraryInventory -State $state -Item @(Get-EwLibrary -Path $Root) -Path $Root -SelectedName Example
                    $state.LibraryVersionsListView.SelectedItem = $state.LibraryVersionsListView.ItemsSource[0]
                    Mock Confirm-EwWorkbenchLibraryRemoval { $false }
                    Mock Start-EwJob { throw 'Unexpected destructive job' }
                    $click = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
                    $state.RemoveLibraryAppButton.RaiseEvent($click)
                    $state.RemoveLibraryVersionsButton.RaiseEvent($click)
                    Should -Invoke Confirm-EwWorkbenchLibraryRemoval -Exactly 1 -ParameterFilter { $EntireApplication -and $Row.Count -eq 3 -and $Path -eq $Root }
                    Should -Invoke Confirm-EwWorkbenchLibraryRemoval -Exactly 1 -ParameterFilter { -not $EntireApplication -and $Row.Count -eq 1 -and $Row[0].Architecture -eq 'x64' }
                    Should -Invoke Start-EwJob -Exactly 0
                    (Get-EwLibrary -Path $Root).VersionCount | Should -Be 3
                }
                finally { $window.Close() }
            }
        }

        It 'supports row multi-selection, bottom-right placement and path and busy guards' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $window = Get-EwWorkbenchWindow
                try {
                    $settings = Get-EwSetting
                    $settings.StartupView = 'Library'
                    $state = Get-EwWorkbenchState -Window $window -Settings $settings
                    $state.LibraryPathBox.Text = $Root
                    Invoke-EwWorkbenchLibraryInventory -State $state -Item @(Get-EwLibrary -Path $Root) -Path $Root -SelectedName Example
                    $state.LibraryVersionsListView.SelectionMode.ToString() | Should -Be 'Extended'
                    $state.LibraryVersionsListView.SelectionUnit.ToString() | Should -Be 'FullRow'
                    $null = $state.LibraryVersionsListView.SelectedItems.Add($state.LibraryVersionsListView.ItemsSource[0])
                    $null = $state.LibraryVersionsListView.SelectedItems.Add($state.LibraryVersionsListView.ItemsSource[2])
                    $state.RemoveLibraryVersionsButton.IsEnabled | Should -BeTrue
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeTrue
                    $window.Show()
                    $window.UpdateLayout()
                    $buttonPosition = $state.RemoveLibraryVersionsButton.TranslatePoint([System.Windows.Point]::new(0, 0), $state.LibraryPanel)
                    $tablePosition = $state.LibraryVersionsListView.TranslatePoint([System.Windows.Point]::new(0, 0), $state.LibraryPanel)
                    $buttonPosition.Y | Should -BeGreaterOrEqual ($tablePosition.Y + $state.LibraryVersionsListView.ActualHeight)
                    [Math]::Abs($buttonPosition.X + $state.RemoveLibraryVersionsButton.ActualWidth - $state.LibraryPanel.ActualWidth) | Should -BeLessThan 1
                    Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeFalse
                    $state.RemoveLibraryVersionsButton.IsEnabled | Should -BeFalse
                    Invoke-EwWorkbenchBusyState -State $state -IsBusy $false
                    $state.LibraryPathBox.Text = "$Root\Other"
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeFalse
                    $state.RemoveLibraryVersionsButton.IsEnabled | Should -BeFalse
                    $state.LibraryPathBox.Text = $Root
                    $state.LibraryListView.SelectedItem = $null
                    $state.LibraryVersionsListView.ItemsSource | Should -BeNullOrEmpty
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeFalse
                }
                finally { $window.Close() }
            }
        }

        It 'removes <Mode> through the shared Job and refreshes or clears selection' -ForEach @(
            @{ Mode = 'selected rows'; EntireApplication = $false },
            @{ Mode = 'the application'; EntireApplication = $true }
        ) {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot; All = $EntireApplication } {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.LibraryPathBox.Text = $Root
                    Invoke-EwWorkbenchLibraryInventory -State $state -Item @(Get-EwLibrary -Path $Root) -Path $Root -SelectedName Example
                    $null = $state.LibraryVersionsListView.SelectedItems.Add($state.LibraryVersionsListView.ItemsSource[0])
                    $null = $state.LibraryVersionsListView.SelectedItems.Add($state.LibraryVersionsListView.ItemsSource[2])
                    Mock Confirm-EwWorkbenchLibraryRemoval { $true }
                    Invoke-EwWorkbenchLibraryRemoval -State $state -EntireApplication $All
                    $state.ActiveJobKind | Should -Be 'LibraryRemoval'
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeFalse
                    $deadline = [DateTime]::UtcNow.AddSeconds(30)
                    while ($null -ne $state.ActiveJobId -and [DateTime]::UtcNow -lt $deadline) {
                        Invoke-EwWorkbenchJobMonitor -State $state
                        Start-Sleep -Milliseconds 50
                    }
                    $state.ActiveJobId | Should -BeNullOrEmpty
                    $state.LoadedLibraryPath | Should -Be $Root
                    if ($All) {
                        $state.LibraryListView.ItemsSource | Should -BeNullOrEmpty
                        $state.LibraryVersionsListView.ItemsSource | Should -BeNullOrEmpty
                        $state.LibraryListView.SelectedItem | Should -BeNullOrEmpty
                    }
                    else {
                        $state.LibraryListView.SelectedItem.Name | Should -Be 'Example'
                        $state.LibraryVersionsListView.ItemsSource | Should -HaveCount 1
                        $state.LibraryVersionsListView.ItemsSource[0].Architecture | Should -Be 'x86'
                        $state.LibraryVersionsListView.ItemsSource[0].Location | Should -Be (Join-Path -Path $Root -ChildPath 'Example\b.msi')
                        $state.LibraryVersionsListView.SelectedItems.Count | Should -Be 0
                        Join-Path -Path $Root -ChildPath 'Example\b.msi' | Should -Exist
                    }
                    Join-Path -Path $Root -ChildPath 'Example\a.msi' | Should -Not -Exist
                    Join-Path -Path $Root -ChildPath 'Example\c.exe' | Should -Not -Exist
                }
                finally { $window.Close() }
            }
        }

        It 'reports partial outcomes and keeps stale actions disabled after a refresh failure' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                $window = Get-EwWorkbenchWindow
                try {
                    $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                    $state.LibraryPathBox.Text = $Root
                    Invoke-EwWorkbenchLibraryInventory -State $state -Item @(Get-EwLibrary -Path $Root) -Path $Root -SelectedName Example
                    $state.LibraryRemovalContext = @{ Path = $Root; Name = 'Example' }
                    $state.LoadedLibraryPath = ''
                    Mock Write-EwWorkbenchLog {}
                    $job = [PSCustomObject]@{
                        State = 'Completed'; TerminatingError = $null
                        Output = @([PSCustomObject]@{
                            Result = [PSCustomObject]@{
                                Succeeded = $false; RemovedCount = 0; RemovedFiles = @('a.msi')
                                Error = 'locked'; FailedFile = 'b.msi'; UnattemptedFiles = @('c.exe')
                            }
                            Items = @(); RefreshError = 'manifest unavailable'
                        })
                    }
                    Invoke-EwWorkbenchLibraryJobResult -State $state -Job $job
                    Invoke-EwWorkbenchLibraryActionState -State $state
                    $state.RemoveLibraryAppButton.IsEnabled | Should -BeFalse
                    $state.RemoveLibraryVersionsButton.IsEnabled | Should -BeFalse
                    Should -Invoke Write-EwWorkbenchLog -Exactly 1 -ParameterFilter { $Message -like '*refresh failed*manifest unavailable*' -and $Level -eq 'Error' }
                    Should -Invoke Write-EwWorkbenchLog -Exactly 1 -ParameterFilter { $Message -eq 'Removed: a.msi' }
                    Should -Invoke Write-EwWorkbenchLog -Exactly 1 -ParameterFilter { $Message -eq 'Not attempted: c.exe' }
                }
                finally { $window.Close() }
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
                $state.InstallDefinitionsStale = $false
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
                $state.InstallDefinitionsStale = $false
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

    It 'saves and restores the Apps list width after drag and keyboard resizing' {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $windows = [System.Collections.Generic.List[object]]::new()
            try {
                $window = Get-EwWorkbenchWindow
                $windows.Add($window)
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Width = 1200
                $window.ShowInTaskbar = $false
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                $splitter = $state.AppsListGridSplitter
                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragStartedEventArgs]::new(0, 0))
                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragDeltaEventArgs]::new(110, 0))
                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragCompletedEventArgs]::new(110, 0, $false))
                (Get-EwSetting).AppsListWidth | Should -Be 330
                $state.Settings.AppsListWidth | Should -Be 330
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragStartedEventArgs]::new(0, 0))
                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragDeltaEventArgs]::new(-50, 0))
                $source = [System.Windows.PresentationSource]::FromVisual($splitter)
                $cancelArgs = [System.Windows.Input.KeyEventArgs]::new(
                    [System.Windows.Input.Keyboard]::PrimaryDevice, $source, 0, [System.Windows.Input.Key]::Escape
                )
                $cancelArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                $splitter.RaiseEvent($cancelArgs)
                $splitter.RaiseEvent([System.Windows.Controls.Primitives.DragCompletedEventArgs]::new(-50, 0, $true))
                (Get-EwSetting).AppsListWidth | Should -Be 330
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                foreach ($routedEvent in @(
                        [System.Windows.Input.Keyboard]::KeyDownEvent,
                        [System.Windows.Input.Keyboard]::KeyUpEvent
                    )) {
                    $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                        [System.Windows.Input.Keyboard]::PrimaryDevice, $source, 0, [System.Windows.Input.Key]::Right
                    )
                    $keyArgs.RoutedEvent = $routedEvent
                    $splitter.RaiseEvent($keyArgs)
                }
                (Get-EwSetting).AppsListWidth | Should -Be 340
                $window.Close()

                $window = Get-EwWorkbenchWindow
                $windows.Add($window)
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Width = 1200
                $window.ShowInTaskbar = $false
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                [Math]::Abs($state.AppsListColumn.ActualWidth - 340) | Should -BeLessOrEqual 1
            }
            finally {
                foreach ($item in $windows) { $item.Close() }
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'fits a saved Apps list width to a narrower window without losing the preference' -Skip:$isGitHubRunner {
        InModuleScope EvergreenUI {
            $originalAppData = $env:APPDATA
            $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
            $window = $null
            try {
                Set-EwSetting -Name AppsListWidth -Value '700'
                Set-EwSetting -Name StartupView -Value 'Library'
                $window = Get-EwWorkbenchWindow
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Width = 960
                $window.ShowInTaskbar = $false
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $state.NavApps.IsChecked = $true
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

                $state.AppsListColumn.ActualWidth | Should -BeLessThan 700
                $state.ArtifactsColumn.ActualWidth | Should -BeGreaterOrEqual 300
                ($state.AppsListView.Parent.ActualWidth - $state.AppsPanel.ActualWidth) | Should -BeLessOrEqual 1
                (Get-EwSetting).AppsListWidth | Should -Be 700

                $window.Width = 1600
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                [Math]::Abs($state.AppsListColumn.ActualWidth - 700) | Should -BeLessOrEqual 1
                (Get-EwSetting).AppsListWidth | Should -Be 700

                $state.NavLibrary.IsChecked = $true
                $window.Width = 960
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $state.NavApps.IsChecked = $true
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $state.AppsListColumn.ActualWidth | Should -BeLessThan 700
                $state.ArtifactsColumn.ActualWidth | Should -BeGreaterOrEqual 300
                ($state.AppsListView.Parent.ActualWidth - $state.AppsPanel.ActualWidth) | Should -BeLessOrEqual 1
                (Get-EwSetting).AppsListWidth | Should -Be 700
            }
            finally {
                if ($null -ne $window) { $window.Close() }
                $env:APPDATA = $originalAppData
            }
        }
    }

    It 'reports an invalid saved Apps list width and uses the default' {
        InModuleScope EvergreenUI {
            $settings = Get-EwSetting
            $settings.StartupView = 'Apps'
            $settings.AppsListWidth = 'wide'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $state.AppsListColumn.Width.Value | Should -Be 220
                $state.ActivityLog.Text | Should -Match 'Invalid saved application list width'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'saves the download tray height when the splitter drag completes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.AppsPanel.RowDefinitions[3].Height = [System.Windows.GridLength]::new(1000)
                $dragArgs = [System.Windows.Controls.Primitives.DragCompletedEventArgs]::new(0, 0, $false)
                $state.DownloadTrayGridSplitter.RaiseEvent($dragArgs)
                $state.AppsPanel.RowDefinitions[3].Height.Value | Should -BeIn @(120, 600)
                (Get-EwSetting).DownloadTrayHeight | Should -BeIn @(120, 600)
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'routes private helper calls in UI event closures through the module invoker' {
        $uiRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI'
        $privateNames = Get-ChildItem -Path (Join-Path -Path $uiRoot -ChildPath 'Private') -Recurse -Filter '*.ps1' |
            ForEach-Object -Process { $_.BaseName }
        $violations = foreach ($file in Get-ChildItem -Path $uiRoot -Recurse -Filter '*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $closures = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $node.Member.Value -eq 'GetNewClosure' -and
                    $node.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
                }, $true)
            foreach ($closure in $closures) {
                $body = $closure.Expression.ScriptBlock
                $commands = $body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($command in $commands) {
                    $owner = $command.Parent
                    while ($owner -isnot [System.Management.Automation.Language.ScriptBlockAst]) {
                        $owner = $owner.Parent
                    }
                    # Nested blocks run as job workers or through '& $module', which restore module scope.
                    if ($owner -eq $body -and $command.GetCommandName() -in $privateNames) {
                        '{0}:{1} {2}' -f $file.Name, $command.Extent.StartLineNumber, $command.GetCommandName()
                    }
                }
            }
        }
        $violations | Should -BeNullOrEmpty
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

    It 'saves the normal window size and maximised state' -Skip:$isGitHubRunner {
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
                foreach ($name in 'NavApps', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio') {
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

    It 'shows the three saved workflow folders without replacing unsaved edits on navigation' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $available = Join-Path -Path $Root -ChildPath 'Definitions'
            $missing = Join-Path -Path $Root -ChildPath 'Missing configurations'
            $null = New-Item -Path $available -ItemType Directory -Force
            Set-EwSetting -Name IntuneDefinitionsPath -Value $available
            Set-EwSetting -Name M365DefinitionsPath -Value $missing
            Set-EwSetting -Name NerdioDefinitionsPath -Value ''
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneDefinitionsPathBox.Text = 'C:\UnsavedPackages'
                $state.IntuneM365PathBox.Text = 'C:\UnsavedM365'
                $state.NerdioDefinitionsPathBox.Text = 'C:\UnsavedNerdio'
                $state.NavSettings.IsChecked = $true
                foreach ($kind in 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions') {
                    & $Wait -State $state -Kind $kind
                    $state["Settings${kind}PathBox"].IsReadOnly | Should -BeTrue
                    $state["Browse${kind}FolderButton"].IsEnabled | Should -BeTrue
                }
                $state.SettingsPackageDefinitionsPathBox.Text | Should -Be $available
                $state.SettingsM365ConfigurationsPathBox.Text | Should -Be $missing
                $state.SettingsNerdioDefinitionsPathBox.Text | Should -Be ''
                $state.OpenPackageDefinitionsFolderButton.IsEnabled | Should -BeTrue
                $state.OpenM365ConfigurationsFolderButton.IsEnabled | Should -BeFalse
                $state.M365ConfigurationsFolderStatusLabel.Text | Should -Match 'unavailable'
                $state.NerdioDefinitionsFolderStatusLabel.Text | Should -Match 'No nerdio definitions folder is configured'
                $state.IntuneDefinitionsPathBox.Text | Should -Be 'C:\UnsavedPackages'
                $state.IntuneM365PathBox.Text | Should -Be 'C:\UnsavedM365'
                $state.NerdioDefinitionsPathBox.Text | Should -Be 'C:\UnsavedNerdio'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps the added folder controls reachable at minimum window size' -Skip:$isGitHubRunner {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $window.Width = $window.MinWidth
                $window.Height = $window.MinHeight
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $state.NavSettings.IsChecked = $true
                $window.UpdateLayout()
                $scroll = $state.SettingsPanel.Children[0]
                $scroll.ScrollableHeight | Should -BeGreaterThan 0
                $scroll.ScrollToEnd()
                $window.UpdateLayout()
                $button = $state.OpenNerdioDefinitionsFolderButton
                $position = $button.TranslatePoint([System.Windows.Point]::new(0, 0), $scroll)
                $position.X | Should -BeGreaterOrEqual 0
                ($position.X + $button.ActualWidth) | Should -BeLessOrEqual $scroll.ActualWidth
                $position.Y | Should -BeGreaterOrEqual 0
                ($position.Y + $button.ActualHeight) | Should -BeLessOrEqual $scroll.ActualHeight
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'saves the <Kind> folder and replaces the corresponding workflow drafts' -ForEach @(
        @{ Kind = 'PackageDefinitions'; Setting = 'IntuneDefinitionsPath' }
        @{ Kind = 'M365Configurations'; Setting = 'M365DefinitionsPath' }
        @{ Kind = 'NerdioDefinitions'; Setting = 'NerdioDefinitionsPath' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Kind = $Kind; Setting = $Setting; Root = $TestDrive } {
            param($Kind, $Setting, $Root)
            $path = Join-Path -Path $Root -ChildPath $Kind
            Set-EwSetting -Name $Setting -Value 'C:\OldSaved'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Invoke-EwWorkbenchFolderCheck {}
                switch ($Kind) {
                    'PackageDefinitions' {
                        $state.IntuneDefinitionsPathBox.Text = 'C:\Unsaved'
                        $state.PackageDefinitions.Add([PSCustomObject]@{ Status = 'Valid' })
                        $state.InstallDefinitionsStale = $false
                        $state.IntuneComparisonRoot = 'C:\OldSaved'
                        $state.IntuneComparisonListView.ItemsSource = [object[]]@([PSCustomObject]@{ Name = 'Old' })
                    }
                    'M365Configurations' {
                        $state.IntuneM365PathBox.Text = 'C:\UnsavedIntune'
                        $state.NerdioM365PathBox.Text = 'C:\UnsavedNerdio'
                        $state.IntuneM365CompanyBox.Text = 'Unsaved company'
                        foreach ($provider in 'Intune', 'Nerdio') {
                            $view = $state.M365Views[$provider]
                            $view.ConfigurationCombo.ItemsSource = [object[]]@([PSCustomObject]@{ FileName = 'old.xml' })
                            $view.BuildPlan = [PSCustomObject]@{ Name = 'Old' }
                            $view.PublishPlan = [PSCustomObject]@{ Name = 'Old' }
                        }
                    }
                    'NerdioDefinitions' {
                        $state.NerdioDefinitionsPathBox.Text = 'C:\Unsaved'
                        $state.NmeHostBox.Text = 'unsaved-host'
                        $state.NerdioDestination = [PSCustomObject]@{ ApiOnly = $false }
                        $state.NerdioPlan = [PSCustomObject]@{ Name = 'Old' }
                    }
                }
                Set-EwWorkbenchFolderPath -State $state -Kind $Kind -Path $path -Confirm:$false
                (Get-EwSetting)[$Setting] | Should -Be $path
                $state.Settings[$Setting] | Should -Be $path
                $state["Settings${Kind}PathBox"].Text | Should -Be $path
                switch ($Kind) {
                    'PackageDefinitions' {
                        $state.IntuneDefinitionsPathBox.Text | Should -Be $path
                        $state.InstallDefinitionsStale | Should -BeTrue
                        $state.PackageDefinitions.Count | Should -Be 0
                        $state.UpdatePackageDefinitionsButton.IsEnabled | Should -BeFalse
                        $state.IntuneComparisonRoot | Should -Be ''
                        @($state.IntuneComparisonListView.ItemsSource).Count | Should -Be 0
                    }
                    'M365Configurations' {
                        foreach ($provider in 'Intune', 'Nerdio') {
                            $view = $state.M365Views[$provider]
                            $view.PathBox.Text | Should -Be $path
                            @($view.ConfigurationCombo.ItemsSource).Count | Should -Be 0
                            $view.BuildPlan | Should -BeNullOrEmpty
                            $view.PublishPlan | Should -BeNullOrEmpty
                        }
                        $state.IntuneM365CompanyBox.Text | Should -Be 'Unsaved company'
                    }
                    'NerdioDefinitions' {
                        $state.NerdioDefinitionsPathBox.Text | Should -Be $path
                        $state.NerdioPlan | Should -BeNullOrEmpty
                        $state.NerdioDestination | Should -Not -BeNullOrEmpty
                        $state.NmeHostBox.Text | Should -Be 'unsaved-host'
                    }
                }
                Should -Invoke Invoke-EwWorkbenchFolderCheck -Exactly 1
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reflects workflow view saves when Settings is reopened' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Invoke-EwWorkbenchFolderCheck {}
                $state.IntuneDefinitionsPathBox.Text = 'C:\Packages'
                $state.SaveIntuneDefinitionsPathButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                    ))
                $state.IntuneM365PathBox.Text = 'C:\M365'
                Invoke-EwWorkbenchM365Action -State $state -Provider Intune -Action Save
                $state.NerdioDefinitionsPathBox.Text = 'C:\Nerdio'
                Invoke-EwWorkbenchNerdioAction -State $state -Action Save
                $state.NavSettings.IsChecked = $true
                $state.SettingsPackageDefinitionsPathBox.Text | Should -Be 'C:\Packages'
                $state.SettingsM365ConfigurationsPathBox.Text | Should -Be 'C:\M365'
                $state.SettingsNerdioDefinitionsPathBox.Text | Should -Be 'C:\Nerdio'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'does not replace <Kind> workflow drafts when saving fails or a job is active' -ForEach @(
        @{ Kind = 'PackageDefinitions'; Control = 'IntuneDefinitionsPathBox'; Setting = 'IntuneDefinitionsPath' }
        @{ Kind = 'M365Configurations'; Control = 'IntuneM365PathBox'; Setting = 'M365DefinitionsPath' }
        @{ Kind = 'NerdioDefinitions'; Control = 'NerdioDefinitionsPathBox'; Setting = 'NerdioDefinitionsPath' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Kind = $Kind; Control = $Control; Setting = $Setting } {
            param($Kind, $Control, $Setting)
            Set-EwSetting -Name $Setting -Value 'C:\OldSaved'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state[$Control].Text = 'C:\Unsaved'
                $state["Settings${Kind}PathBox"].Text = 'C:\OldSaved'
                Mock Set-EwSetting { throw 'save failed' }
                { Set-EwWorkbenchFolderPath -State $state -Kind $Kind -Path 'C:\New' -Confirm:$false } |
                    Should -Throw '*save failed*'
                $state["Settings${Kind}PathBox"].Text | Should -Be 'C:\OldSaved'
                $state.Settings[$Setting] | Should -Be 'C:\OldSaved'
                $state[$Control].Text | Should -Be 'C:\Unsaved'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'Downloads'
                Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
                $state["Browse${Kind}FolderButton"].IsEnabled | Should -BeFalse
                { Set-EwWorkbenchFolderPath -State $state -Kind $Kind -Path 'C:\New' -Confirm:$false } |
                    Should -Throw '*current operation*'
                Should -Invoke Set-EwSetting -Exactly 1
            }
            finally {
                $state.ActiveJobId = $null
                $window.Close()
            }
        }
    }

    It 'discards a superseded Microsoft 365 folder check after cancellation fails' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
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
                                Available = $Id -eq $firstId
                                ResolvedPath = 'C:\OldFolder'
                                Error = 'The new folder is unavailable.'
                            })
                    }
                }
                Mock Stop-EwJob { throw 'synthetic cancellation failure' }
                Mock Remove-EwJob {}
                $state.SettingsM365ConfigurationsPathBox.Text = 'C:\OldFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind M365Configurations
                $state.SettingsM365ConfigurationsPathBox.Text = 'C:\NewFolder'
                Invoke-EwWorkbenchFolderCheck -State $state -Kind M365Configurations
                $script:folderTestFirstState = 'Completed'
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.OpenM365ConfigurationsFolderButton.IsEnabled | Should -BeFalse
                $state.InfoJobs.M365Configurations.ActiveId | Should -Be $secondId
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.OpenM365ConfigurationsFolderButton.IsEnabled | Should -BeFalse
                $state.M365ConfigurationsFolderStatusLabel.Text | Should -Match 'new folder is unavailable'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'rechecks a saved Nerdio folder before opening it' {
        InModuleScope EvergreenUI -Parameters @{ Wait = $waitForInfoJob; Root = $TestDrive } {
            param($Wait, $Root)
            $path = Join-Path -Path $Root -ChildPath 'Nerdio folder'
            $null = New-Item -Path $path -ItemType Directory -Force
            Set-EwSetting -Name NerdioDefinitionsPath -Value $path
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-Process {}
                $state.NavSettings.IsChecked = $true
                & $Wait -State $state -Kind NerdioDefinitions
                $state.OpenNerdioDefinitionsFolderButton.IsEnabled | Should -BeTrue
                Remove-Item -LiteralPath $path -Force
                $state.OpenNerdioDefinitionsFolderButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                    ))
                & $Wait -State $state -Kind NerdioDefinitions
                $state.OpenNerdioDefinitionsFolderButton.IsEnabled | Should -BeFalse
                $state.NerdioDefinitionsFolderStatusLabel.Text | Should -Match 'unavailable'
                Should -Invoke Start-Process -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'limits simultaneous folder checks and starts a pending check when a slot is freed' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                Mock Remove-EwJob {}
                Mock Stop-EwJob { [PSCustomObject]@{ Id = $Id; State = 'Stopped' } }
                foreach ($kind in 'Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions') {
                    $state["Settings${kind}PathBox"].Text = "C:\$kind"
                    Invoke-EwWorkbenchFolderCheck -State $state -Kind $kind
                }
                $firstId = $state.InfoJobs.Download.ActiveId
                $state.InfoJobs.Library.ActiveId | Should -Not -BeNullOrEmpty
                $state.InfoJobs.PackageDefinitions.Pending | Should -Not -BeNullOrEmpty
                Should -Invoke Start-EwJob -Exactly 2
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id
                        State = if ($Id -eq $firstId) { 'Completed' } else { 'Running' }
                        Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{ Available = $true; ResolvedPath = 'C:\Download'; Error = '' })
                    }
                }
                Invoke-EwWorkbenchInfoJobMonitor -State $state
                $state.InfoJobs.PackageDefinitions.ActiveId | Should -Not -BeNullOrEmpty
                $state.InfoJobs.M365Configurations.Pending | Should -Not -BeNullOrEmpty
                Should -Invoke Start-EwJob -Exactly 3
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'offers saved library locations as a dropdown and records newly saved ones' {
        InModuleScope EvergreenUI -Parameters @{ Root = $TestDrive } {
            param($Root)
            $first = Join-Path -Path $Root -ChildPath 'Library one'
            $second = Join-Path -Path $Root -ChildPath 'Library two'
            $third = Join-Path -Path $Root -ChildPath 'Library three'
            Set-EwSetting -Name LibraryPath -Value $first
            Set-EwSetting -Name LibraryPath -Value $second
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.LibraryPathBox.IsEditable | Should -BeTrue
                $state.LibraryPathBox.Text | Should -Be $second
                @($state.LibraryPathBox.ItemsSource) | Should -Be @($second, $first)

                $state.LibraryPathBox.SelectedItem = $first
                $state.LibraryPathBox.Text | Should -Be $first

                $state.LibraryPathBox.Text = $third
                $state.SetLibraryPathButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                (Get-EwSetting).LibraryPath | Should -Be $third
                @($state.LibraryPathBox.ItemsSource) | Should -Be @($third, $second, $first)
                $state.LibraryPathBox.Text | Should -Be $third
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
