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
                        'NavPackages', 'NavInstall',
                        'AppsPanel', 'DownloadPanel', 'LibraryPanel', 'PackagesPanel', 'InstallPanel',
                        'AppSearchBox', 'AppCountLabel', 'AppsListView', 'ArtifactsGrid',
                        'DownloadQueueListView', 'LibraryListView', 'LibraryVersionsListView',
                        'PackageDefinitionsListView', 'InstallDefinitionsListView',
                        'LoadPackageDefinitionsButton', 'UpdatePackageDefinitionsButton',
                        'ReloadInstallDefinitionsButton', 'ResolveInstallVersionsButton',
                        'InstallSelectedPackagesButton', 'ThemeCombo', 'ActivityLog'
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
                    foreach ($index in 1..8) {
                        [PSCustomObject]@{
                            Version = "$index.0"
                            Architecture = if ($index % 2 -eq 0) { 'x64' } else { 'x86' }
                            Channel = "channel$index"
                            URI = "https://example.test/app$index.msi"
                        }
                    }
                )
                Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
                $architectureFilter = $state.ArtifactFilterControls['Architecture']
                $architectureFilter.Type | Should -Be 'CheckBoxStrip'
                ($architectureFilter.ValueControls | Where-Object Tag -eq 'x86').IsChecked = $false
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 4
                $channelFilter = $state.ArtifactFilterControls['Channel']
                $channelFilter.Type | Should -Be 'MultiListBox'
                $null = $channelFilter.Control.SelectedItems.Remove('channel8')
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 3
                foreach ($value in @($channelFilter.Control.SelectedItems)) {
                    $null = $channelFilter.Control.SelectedItems.Remove($value)
                }
                @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 0
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
