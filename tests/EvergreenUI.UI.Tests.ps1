#Requires -Version 7.6

BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
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
                        'AppsPanel', 'DownloadPanel', 'LibraryPanel',
                        'AppSearchBox', 'AppCountLabel', 'AppsListView', 'ArtifactsGrid',
                        'DownloadQueueListView', 'LibraryListView', 'ThemeCombo', 'ActivityLog'
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

    It 'switches views and filters artifacts using generated property controls' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavDownload.IsChecked = $true
                $state.DownloadPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.AppsPanel.Visibility.ToString() | Should -Be 'Collapsed'

                $state.AllArtifacts = @(
                    [PSCustomObject]@{ Version = '1.0'; Architecture = 'x64'; Type = 'msi'; URI = 'https://example.test/a.msi' }
                    [PSCustomObject]@{ Version = '2.0'; Architecture = 'x86'; Type = 'msi'; URI = 'https://example.test/b.msi' }
                )
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                $state.ArtifactFilterControls['Architecture'].SelectedItem = 'x64'
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1
                $state.ArtifactsGrid.ItemsSource[0].Version | Should -Be '1.0'
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
