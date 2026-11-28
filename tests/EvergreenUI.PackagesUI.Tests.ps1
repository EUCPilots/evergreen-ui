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

    It 'loads the configured Definitions folder on first entry and reloads only when requested' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.LoadPackageDefinitionsButton.Content | Should -Be 'Reload definitions'
            Show-EwWorkbenchView -State $state -View 'Packages'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\Definitions'
            }
            $script:jobOutput = @([PSCustomObject]@{ Items = @() })
            Invoke-EwWorkbenchJobMonitor -State $state
            Show-EwWorkbenchView -State $state -View 'Apps'
            Show-EwWorkbenchView -State $state -View 'Packages'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'PackageDefinitions' }
            $state.LoadPackageDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 2 -ParameterFilter { $Kind -eq 'PackageDefinitions' }
        }
    }

    It 'loads the configured folder when Packages is restored at startup' {
        InModuleScope EvergreenUI {
            $settings = Get-EwSetting
            $settings.StartupView = 'Packages'
            $settings.IntuneDefinitionsPath = 'C:\StartupDefinitions'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                    $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\StartupDefinitions'
                }
                $state.DefinitionsTab.IsSelected | Should -BeTrue
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'waits for the initial application catalog job before loading Definitions' {
        InModuleScope EvergreenUI {
            $settings = Get-EwSetting
            $settings.StartupView = 'Packages'
            $settings.IntuneDefinitionsPath = 'C:\StartupDefinitions'
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $settings -DeferPackageDefinitionsStartup
                $state.PackageDefinitionsLoadPending | Should -BeTrue
                Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
                Invoke-EwWorkbenchJob -State $state -Kind 'Apps' -Name 'Load application catalog' -ScriptBlock {}
                $state.PackageDefinitionsStartupDeferred = $false
                Mock Invoke-EwWorkbenchAppList {}
                $script:jobOutput = @()
                Invoke-EwWorkbenchJobMonitor -State $state
                Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'Apps' }
                Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                    $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\StartupDefinitions'
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'defers the first Definitions load until the active job finishes' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = 'DefinitionUpdate'
            Show-EwWorkbenchView -State $state -View 'Packages'
            $state.PackageDefinitionsLoadPending | Should -BeTrue
            $state.StatusLabel.Text | Should -Match 'pending.*current operation'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
            $script:jobOutput = @([PSCustomObject]@{ Items = @(); Results = @() })
            Invoke-EwWorkbenchJobMonitor -State $state
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'PackageDefinitions' }
            $state.ActiveJobKind | Should -Be 'PackageDefinitions'
        }
    }

    It 'keeps waiting when the active job status cannot be read' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.ActiveJobId = [guid]::NewGuid()
            $state.ActiveJobKind = 'Apps'
            $activeId = $state.ActiveJobId
            Show-EwWorkbenchView -State $state -View 'Packages'
            Mock Get-EwJob { throw 'Job status unavailable' }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobId | Should -Be $activeId
            $state.PackageDefinitionsLoadPending | Should -BeTrue
            $state.StatusLabel.Text | Should -Match 'Definitions load pending.*waiting'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
        }
    }

    It 'discards a Definitions result when the folder changes while loading' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            Show-EwWorkbenchView -State $state -View 'Packages'
            $state.IntuneDefinitionsPathBox.Text = 'C:\Replacement'
            $script:jobOutput = @([PSCustomObject]@{
                Items = @([PSCustomObject]@{ Name = 'Old'; Status = 'Valid' })
            })
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.PackageDefinitions.Count | Should -Be 0
            $state.UpdatePackageDefinitionsButton.IsEnabled | Should -BeFalse
            $state.StatusLabel.Text | Should -Match 'folder changed.*Reload definitions'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1
        }
    }

    It 'loads on first selection of Definitions after starting on Install' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.Settings.StartupView = 'Install'
            Restore-EwWorkbenchStartupView -State $state
            $script:jobOutput = @()
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.DefinitionsTab.IsSelected = $true
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'PackageDefinitions' }
        }
    }

    It 'waits for a folder, then loads after editing is complete; later changes require reload' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.IntuneDefinitionsPathBox.Text = ''
            Show-EwWorkbenchView -State $state -View 'Packages'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
            $state.IntuneDefinitionsPathBox.Text = 'C:\First'
            $focusArgs = [System.Windows.Input.KeyboardFocusChangedEventArgs]::new(
                [System.Windows.Input.Keyboard]::PrimaryDevice, 0, $null, $null)
            $focusArgs.RoutedEvent = [System.Windows.Input.Keyboard]::LostKeyboardFocusEvent
            $state.IntuneDefinitionsPathBox.RaiseEvent($focusArgs)
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\First'
            }
            $script:jobOutput = @([PSCustomObject]@{
                Items = @([PSCustomObject]@{ Name = 'Old'; Status = 'Valid' })
            })
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.IntuneDefinitionsPathBox.Text = 'C:\Second'
            $state.PackageDefinitions.Count | Should -Be 0
            $state.UpdatePackageDefinitionsButton.IsEnabled | Should -BeFalse
            $focusArgs = [System.Windows.Input.KeyboardFocusChangedEventArgs]::new(
                [System.Windows.Input.Keyboard]::PrimaryDevice, 0, $null, $null)
            $focusArgs.RoutedEvent = [System.Windows.Input.Keyboard]::LostKeyboardFocusEvent
            $state.IntuneDefinitionsPathBox.RaiseEvent($focusArgs)
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1
            $state.LoadPackageDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\Second'
            }
        }
    }

    It 'saves a newly entered folder before starting its initial load' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.IntuneDefinitionsPathBox.Text = ''
            Show-EwWorkbenchView -State $state -View 'Packages'
            $state.IntuneDefinitionsPathBox.Text = 'C:\Saved'
            $focusArgs = [System.Windows.Input.KeyboardFocusChangedEventArgs]::new(
                [System.Windows.Input.Keyboard]::PrimaryDevice, 0,
                $state.IntuneDefinitionsPathBox, $state.SaveIntuneDefinitionsPathButton)
            $focusArgs.RoutedEvent = [System.Windows.Input.Keyboard]::LostKeyboardFocusEvent
            $state.IntuneDefinitionsPathBox.RaiseEvent($focusArgs)
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
            $state.SaveIntuneDefinitionsPathButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $state.Settings.IntuneDefinitionsPath | Should -Be 'C:\Saved'
            Should -Invoke Set-EwSetting -Exactly 1 -ParameterFilter {
                $Name -eq 'IntuneDefinitionsPath' -and $Value -eq 'C:\Saved'
            }
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                $Kind -eq 'PackageDefinitions' -and $ArgumentList[0] -eq 'C:\Saved'
            }
        }
    }

    It 'does not automatically retry a failed Definitions load' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            Show-EwWorkbenchView -State $state -View 'Packages'
            $script:jobState = 'Failed'
            Invoke-EwWorkbenchJobMonitor -State $state
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.StatusLabel.Text | Should -Match 'Reload definitions to retry'
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1
            $state.LoadPackageDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 2
        }
    }

    It 'contains Definitions and Install under one sidebar destination and restores legacy startup' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $script:packagesWindow.FindName('NavInstall') | Should -BeNullOrEmpty
            @($state.PackagesTabControl.Items | ForEach-Object Header) | Should -Be @('Definitions', 'Install')
            $state.PackagesTabControl.SelectedIndex | Should -Be 0
            $state.DefinitionsTab.Content | Should -Be $state.PackageDefinitionsListView.Parent.Parent
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

    It 'updates read-only definition details for selections and clears them when the list is cleared' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $details = $state.PackageDefinitionDetailsText
            $details.IsReadOnly | Should -BeTrue
            $getText = { [System.Windows.Documents.TextRange]::new($details.Document.ContentStart, $details.Document.ContentEnd).Text }
            (& $getText).Trim() | Should -Be 'Select a definition to view its details.'
            $details.Document.Blocks.FirstBlock.Inlines.FirstInline.FontFamily.Source | Should -Be $state.IntuneDefinitionsPathBox.FontFamily.Source
            $definition = [PSCustomObject]@{
                Name = 'Example'; Publisher = 'Publisher'; Version = '1.0'; Status = 'Valid'
                DefinitionPath = 'C:\Definitions\Example\App.json'; Error = ''
                DefinitionObject = [PSCustomObject]@{
                    Application = [PSCustomObject]@{ Architecture = 'arm64'; Filter = 'Get-EvergreenApp -Name Example' }
                    Information = [PSCustomObject]@{ Description = 'Example description' }
                    PackageInformation = [PSCustomObject]@{ SetupType = 'EXE'; SetupFile = 'setup.exe' }
                }
            }
            $state.PackageDefinitions.Add($definition)
            $state.PackageDefinitionsListView.SelectedItem = $definition
            foreach ($value in @('Example', 'Publisher', '1.0', 'arm64', 'Example description', 'Get-EvergreenApp -Name Example', 'EXE', 'setup.exe', 'Valid', 'C:\Definitions\Example\App.json')) {
                (& $getText) | Should -Match ([regex]::Escape($value))
            }
            (& $getText) | Should -Not -Match 'Error:'
            $runs = @($details.Document.Blocks.FirstBlock.Inlines)
            $filterRun = $runs | Where-Object Text -eq 'Get-EvergreenApp -Name Example'
            $filterRun.FontFamily.Source | Should -Be 'Consolas'
            $descriptionRun = $runs | Where-Object Text -eq 'Example description'
            $descriptionRun.FontFamily.Source | Should -Be $state.IntuneDefinitionsPathBox.FontFamily.Source
            $descriptionRun.FontSize | Should -Be $state.IntuneDefinitionsPathBox.FontSize
            $details.FontSize = 15
            $descriptionRun.FontSize | Should -Be 15
            $filterRun.FontFamily.Source | Should -Be 'Consolas'

            $invalid = [PSCustomObject]@{
                Name = 'Broken'; DefinitionPath = 'C:\Definitions\Broken\App.json'
                Status = 'Invalid JSON'; Error = 'Unexpected token'; DefinitionObject = $null
            }
            $state.PackageDefinitions.Add($invalid)
            $state.PackageDefinitionsListView.SelectedItem = $invalid
            (& $getText) | Should -Match 'Invalid JSON'
            (& $getText) | Should -Match 'Unexpected token'
            (& $getText) | Should -Not -Match 'Example description|Architecture:'
            $state.PackageDefinitions.Clear()
            (& $getText).Trim() | Should -Be 'Select a definition to view its details.'
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
            $state.PackageDefinitionsLoadAttempted = $true
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
            $state.PackageDefinitionsListView.SelectedItem | Should -Be $definition
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
            $state.PackageDefinitionsListView.SelectedItem | Should -BeNullOrEmpty
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
            $state.StatusLabel.Text | Should -Match 'pending.*current operation'
            $state.ActivityLog.Text | Should -Match 'pending.*current operation'
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
            $state.StatusLabel.Text | Should -Match 'Checked local installation status.*Find latest versions separately'
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
            $state.StatusLabel.Text | Should -Match 'Job status unavailable.*waiting for its status'
            $state.StatusLabel.Tag | Should -Be 'Error'
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
            $state.StatusLabel.Text | Should -Match 'Reload definitions to retry'
            $state.StatusLabel.Tag | Should -Be 'Error'
            $state.ActivityLog.Text | Should -Match 'Reload definitions to retry'
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeFalse
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1
            $state.ReloadInstallDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 2
        }
    }

    It 'shows setup guidance in the shared status when the definitions folder is missing' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.IntuneDefinitionsPathBox.Text = ''
            $state.InstallTab.IsSelected = $true
            $state.StatusLabel.Text | Should -Be 'Set the definitions folder on the Definitions tab, then reload.'
            $state.ActivityLog.Text | Should -Match 'Set the definitions folder'
            $state.ResolveInstallVersionsButton.IsEnabled | Should -BeFalse
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
        }
    }

    It 'reports a refresh startup failure with retry guidance in the shared status' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            Mock Invoke-EwWorkbenchJob { throw 'Job startup failed.' }
            $state.InstallTab.IsSelected = $true
            $state.StatusLabel.Text | Should -Match 'Job startup failed.*Reload definitions to retry'
            $state.StatusLabel.Tag | Should -Be 'Error'
            $state.ActivityLog.Text | Should -Match 'Job startup failed.*Reload definitions to retry'
            $state.InstallDefinitionsStale | Should -BeTrue
            $state.InstallSelectedPackagesButton.IsEnabled | Should -BeFalse
        }
    }

    It 'does not replace the shared status when install data is invalidated offscreen' {
        InModuleScope EvergreenUI {
            $state = $script:packagesState
            $state.StatusLabel.Text = 'Another operation finished.'
            Invoke-EwWorkbenchInstallStale -State $state
            $state.StatusLabel.Text | Should -Be 'Another operation finished.'
            $state.InstallDefinitionsStale | Should -BeTrue
        }
    }
}

Describe 'Definitions loading with a real background job' {
    It 'loads the configured folder automatically and reads changes on reload' {
        $root = Join-Path -Path $TestDrive -ChildPath 'Definitions'
        $null = New-Item -Path $root -ItemType Directory -Force
        $first = Join-Path -Path $root -ChildPath 'First'
        $null = New-Item -Path $first -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $first -ChildPath 'App.json') -Value '{invalid json'
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            $settings = Get-EwSetting
            $settings.StartupView = 'Packages'
            $settings.IntuneDefinitionsPath = $Root
            $window = Get-EwWorkbenchWindow
            $state = $null
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings $settings
                $deadline = [datetime]::UtcNow.AddSeconds(30)
                while ($null -ne $state.ActiveJobId -and [datetime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 100
                    Invoke-EwWorkbenchJobMonitor -State $state
                }
                $state.ActiveJobId | Should -BeNullOrEmpty
                @($state.PackageDefinitions | ForEach-Object Name) | Should -Be @('First')

                $second = Join-Path -Path $Root -ChildPath 'Second'
                $null = New-Item -Path $second -ItemType Directory -Force
                Set-Content -LiteralPath (Join-Path -Path $second -ChildPath 'App.json') -Value '{invalid json'
                $state.LoadPackageDefinitionsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $deadline = [datetime]::UtcNow.AddSeconds(30)
                while ($null -ne $state.ActiveJobId -and [datetime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 100
                    Invoke-EwWorkbenchJobMonitor -State $state
                }
                $state.ActiveJobId | Should -BeNullOrEmpty
                @($state.PackageDefinitions | ForEach-Object Name | Sort-Object) | Should -Be @('First', 'Second')
            }
            finally {
                if ($null -ne $state -and $null -ne $state.ActiveJobId) {
                    Stop-EwJob -Id $state.ActiveJobId -Confirm:$false
                    Remove-EwJob -Id $state.ActiveJobId -Confirm:$false
                }
                $window.Close()
            }
        }
    }
}
