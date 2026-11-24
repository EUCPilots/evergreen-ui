#Requires -Version 7.6

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'appdata'
    $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}

AfterAll {
    $env:APPDATA = $script:originalAppData
}

Describe 'Packages tabs and local detection freshness' {
    BeforeEach {
        InModuleScope EvergreenUI {
            $script:packagesWindow = Get-EwWorkbenchWindow
            $settings = Get-EwSetting
            $settings.StartupView = 'Packages'
            $settings.IntuneDefinitionsPath = ''
            $script:packagesState = Get-EwWorkbenchState -Window $script:packagesWindow -Settings $settings
            $script:packagesState.IntuneDefinitionsPathBox.Text = 'C:\Definitions'
            $script:rows = @('Retained', 'Removed' | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_; DefinitionPath = "C:\Definitions\$_\App.json"; DefinitionValid = 'Yes'
                    LatestVersion = ''; ArtifactArchitecture = 'Not checked'; ArchitectureAssessment = 'Allowed'
                }
            })
            $script:jobOutput = @()
            $script:jobState = 'Completed'
            Mock Invoke-EwWorkbenchJob {
                $State.ActiveJobId = [guid]::NewGuid()
                $State.ActiveJobKind = $Kind
                Invoke-EwWorkbenchBusyState -State $State -IsBusy $true
            }
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = $Id; State = $script:jobState; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @(); Output = $script:jobOutput
                }
            }
            Mock Remove-EwJob {}
            Mock Set-EwSetting {}
            Mock Confirm-EwWorkbenchInstallBatch { throw 'Stale rows must not reach confirmation' }
        }
    }

    AfterEach {
        InModuleScope EvergreenUI { $script:packagesWindow.Close() }
    }

    It 'contains Definitions and Install under one sidebar destination and restores legacy startup' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $script:packagesWindow.FindName('NavInstall') | Should -BeNullOrEmpty
            @($state.PackagesTabControl.Items | ForEach-Object Header) | Should -Be @('Definitions', 'Install')
            $state.PackagesTabControl.SelectedIndex | Should -Be 0
            $state.DefinitionsTab.Content | Should -Be $state.PackageDefinitionsListView.Parent
            $state.InstallTab.Content | Should -Be $state.InstallDefinitionsListView.Parent
            $definitionsPathRow = $state.IntuneDefinitionsPathBox.Parent
            $state.BrowseIntuneDefinitionsButton.Parent | Should -Be $definitionsPathRow
            $state.SaveIntuneDefinitionsPathButton.Parent | Should -Be $definitionsPathRow
            $state.LoadPackageDefinitionsButton.Parent | Should -Be $definitionsPathRow
            $state.UpdatePackageDefinitionsButton.Parent | Should -Be $definitionsPathRow
            foreach ($button in @(
                    $state.BrowseIntuneDefinitionsButton,
                    $state.SaveIntuneDefinitionsPathButton,
                    $state.LoadPackageDefinitionsButton,
                    $state.UpdatePackageDefinitionsButton
                )) {
                [System.Windows.Controls.Grid]::GetRow($button) | Should -Be 0
            }
            [System.Windows.Controls.Grid]::GetColumn($state.BrowseIntuneDefinitionsButton) | Should -Be 1
            [System.Windows.Controls.Grid]::GetColumn($state.SaveIntuneDefinitionsPathButton) | Should -Be 2
            [System.Windows.Controls.Grid]::GetColumn($state.LoadPackageDefinitionsButton) | Should -Be 3
            [System.Windows.Controls.Grid]::GetColumn($state.UpdatePackageDefinitionsButton) | Should -Be 4
            $state.NavIntune | Should -Not -BeNullOrEmpty
            $state.NavNerdio | Should -Not -BeNullOrEmpty
            $state.UiStateReady = $false
            $state.Settings.StartupView = 'Install'
            Restore-EwWorkbenchStartupView -State $state
            $state.NavPackages.IsChecked | Should -BeTrue
            $state.InstallTab.IsSelected | Should -BeTrue
            $state.Settings.StartupView | Should -Be 'Packages'
            Should -Invoke Set-EwSetting -Exactly 0
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'InstallDefinitions' }
        }
    }

    It 'shows Application architecture after a <Kind> job' -ForEach @(
        @{ Kind = 'PackageDefinitions' }
        @{ Kind = 'DefinitionUpdate' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Kind = $Kind; Root = $TestDrive } {
            $root = Join-Path -Path $Root -ChildPath ([guid]::NewGuid().ToString())
            foreach ($name in 'Specified', 'Missing', 'Invalid') {
                $directory = Join-Path -Path $root -ChildPath $name
                $null = New-Item -Path $directory -ItemType Directory -Force
                $path = Join-Path -Path $directory -ChildPath 'App.json'
                if ($name -eq 'Invalid') {
                    Set-Content -LiteralPath $path -Value '{invalid json'
                    continue
                }
                $application = if ($name -eq 'Specified') { @{ Architecture = 'arm64' } } else { @{} }
                @{
                    Application = $application
                    RequirementRule = @{ Architecture = 'x64' }
                    Information = @{
                        DisplayName = $name
                        Publisher = 'Example'
                        PSPackageFactoryGuid = '9fddd581-f505-4760-9bb3-2365db204b38'
                    }
                    PackageInformation = @{ Version = '1.0' }
                } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
            }

            $state = $script:packagesState
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = $Kind
            $script:jobOutput = @([PSCustomObject]@{ Items = @(Get-EwDefinition -Path $root); Results = @() })
            Invoke-EwWorkbenchJobMonitor -State $state
            $window = $script:packagesWindow
            $window.WindowStartupLocation = 'Manual'
            $window.Left = -10000
            $window.Top = -10000
            $window.Show()
            $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
            $window.UpdateLayout()

            $grid = $state.PackageDefinitionsListView
            $column = @($grid.Columns | Where-Object Header -eq 'Architecture')
            $column.Count | Should -Be 1
            foreach ($case in @(
                    @{ Name = 'Specified'; Expected = 'arm64' }
                    @{ Name = 'Missing'; Expected = '' }
                    @{ Name = 'Invalid'; Expected = '' }
                )) {
                $row = $state.PackageDefinitions | Where-Object Name -eq $case.Name
                $row | Should -Not -BeNullOrEmpty
                $grid.ScrollIntoView($row, $column[0])
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $column[0].GetCellContent($row).Text | Should -Be $case.Expected
            }
        }
    }

    It 'keeps tab selections independent and refreshes matching paths without stale Artifact assessments' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $definition = [PSCustomObject]@{ Name = 'Other'; DefinitionPath = 'C:\Definitions\Other\App.json'; Status = 'Valid' }
            $state.PackageDefinitions.Add($definition)
            $state.PackageDefinitionsListView.SelectedItem = $definition
            foreach ($row in $script:rows) { $state.InstallDefinitions.Add($row) }
            $state.InstallDefinitionsStale = $false
            foreach ($row in $script:rows) { $null = $state.InstallDefinitionsListView.SelectedItems.Add($row) }
            $script:rows[0].LatestVersion = '9.0'
            $script:rows[0].ArtifactArchitecture = 'arm64'
            $state.InstallTab.IsSelected = $true
            $script:jobOutput = @($script:rows)
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.DefinitionsTab.IsSelected = $true
            $state.InstallDefinitionsListView.SelectedItems.Count | Should -Be 2
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1

            $state.IntuneDefinitionsPathBox.Text = 'C:\NewDefinitions'
            $state.InstallDefinitions.Count | Should -Be 0
            $state.InstallTab.IsSelected = $true
            $script:jobOutput = @([PSCustomObject]@{
                Name = 'Retained'; DefinitionPath = $script:rows[0].DefinitionPath; DefinitionValid = 'Yes'
                LatestVersion = ''; ArtifactArchitecture = 'Not checked'; ArchitectureAssessment = 'Allowed'
            })
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.InstallDefinitionsStale | Should -BeFalse
            @($state.InstallDefinitionsListView.SelectedItems | ForEach-Object DefinitionPath) |
                Should -Be @($script:rows[0].DefinitionPath)
            $state.PackageDefinitionsListView.SelectedItem | Should -Be $definition
            $state.InstallDefinitions[0].LatestVersion | Should -BeNullOrEmpty
            $state.InstallDefinitions[0].ArtifactArchitecture | Should -Be 'Not checked'
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeTrue
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeTrue
        }
    }

    It 'keeps the shared folder unsaved until Save path is selected' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.IntuneDefinitionsPathBox.Text = 'C:\Unsaved'
            $state.Settings.IntuneDefinitionsPath | Should -BeNullOrEmpty
            Should -Invoke Set-EwSetting -Exactly 0
            $state.SaveIntuneDefinitionsPathButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $state.Settings.IntuneDefinitionsPath | Should -Be 'C:\Unsaved'
            Should -Invoke Set-EwSetting -Exactly 1 -ParameterFilter {
                $Name -eq 'IntuneDefinitionsPath' -and $Value -eq 'C:\Unsaved'
            }
        }
    }

    It 'invalidates local rows after a <Kind> job even when Install is not selected' -ForEach @(
        @{ Kind = 'PackageDefinitions' }
        @{ Kind = 'DefinitionUpdate' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Kind = $Kind } {
            $state = $script:packagesState
            $state.InstallDefinitions.Add($script:rows[0])
            $state.InstallDefinitionsStale = $false
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = $Kind
            $script:jobOutput = @([PSCustomObject]@{ Items = @(); Results = @() })
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.InstallDefinitionsStale | Should -BeTrue
            $state.InstallDefinitions.Count | Should -Be 0
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
        }
    }

    It 'defers stale refresh until the active job finishes and prevents stale install confirmation' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = 'PackageDefinitions'
            $state.InstallTab.IsSelected = $true
            $state.InstallRefreshPending | Should -BeTrue
            $state.InstallActionStatusLabel.Text | Should -Match 'pending.*current operation'
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeFalse
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
            $state.InstallDefinitions.Add($script:rows[0])
            $state.InstallDefinitionsListView.SelectedItem = $script:rows[0]
            $state.InstallSelectedPackagesButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Confirm-EwWorkbenchInstallBatch -Exactly 0
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
            $script:jobOutput = @([PSCustomObject]@{ Items = @(); Results = @() })
            Invoke-EwWorkbenchJobMonitor -State $state
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'InstallDefinitions' }
            $state.ActiveJobKind | Should -Be 'InstallDefinitions'
            $state.InstallDefinitionsStale | Should -BeTrue
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
            $script:jobOutput = @($script:rows[0])
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.InstallDefinitionsStale | Should -BeFalse
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeTrue
        }
    }

    It 'retains the active job when its status is unavailable instead of starting deferred work' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = 'PackageDefinitions'
            $state.InstallTab.IsSelected = $true
            $activeId = $state.ActiveJobId
            Mock Get-EwJob { throw 'Job status unavailable' }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobId | Should -Be $activeId
            $state.InstallRefreshPending | Should -BeTrue
            $state.InstallActionStatusLabel.Text | Should -Match 'waiting for its status'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
            Should -Invoke Remove-EwJob -Exactly 0
        }
    }

    It 'discards detection results if the definitions folder changes during a refresh' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.InstallTab.IsSelected = $true
            $state.IntuneDefinitionsPathBox.Text = 'C:\Replacement'
            $script:jobOutput = @($script:rows[0])
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.InstallDefinitions.Count | Should -Be 0
            $state.InstallDefinitionsStale | Should -BeTrue
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 2 -ParameterFilter { $Kind -eq 'InstallDefinitions' }
            $script:jobOutput = @($script:rows[1])
            Invoke-EwWorkbenchJobMonitor -State $state
            @($state.InstallDefinitions | ForEach-Object Name) | Should -Be @('Removed')
            $state.InstallDefinitionsStale | Should -BeFalse
        }
    }

    It 'keeps failed detection stale without retrying automatically and permits explicit Reload' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.InstallTab.IsSelected = $true
            $script:jobState = 'Failed'
            Invoke-EwWorkbenchJobMonitor -State $state
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.InstallDefinitionsStale | Should -BeTrue
            $state.InstallActionStatusLabel.Text | Should -Match 'Reload definitions to retry'
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeFalse
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1
            $state.ReloadInstallDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 2
        }
    }
}
