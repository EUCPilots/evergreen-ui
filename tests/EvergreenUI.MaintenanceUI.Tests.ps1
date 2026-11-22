#Requires -Version 7.6

BeforeDiscovery {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Apps maintenance' {
    InModuleScope EvergreenUI {
        BeforeEach {
            $window = Get-EwWorkbenchWindow
            $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
            $app = [PSCustomObject]@{ Name = 'TestApp'; FriendlyName = 'Test App'; IsFavourite = $true }
            $artifact = [PSCustomObject]@{ Version = '1.0'; Architecture = 'x64'; URI = 'https://example.test/old.msi' }
            $state.AppCatalog = @($app)
            $state.CurrentApp = $app
            $state.CurrentAppName = $app.Name
            Invoke-EwWorkbenchAppList -State $state
            $state.AllArtifacts = @($artifact)
            Invoke-EwWorkbenchArtifactList -State $state -RebuildFilters
            $state.Queue.Add([PSCustomObject]@{ Id = 'queued'; Status = 'Pending'; Artifact = $artifact; Version = '1.0' })
            $state.MaintenanceContext = @{ AppName = 'TestApp'; Filters = @{}; Catalog = @(); Outcome = 'Update succeeded.' }
            Mock Start-EwJob { [PSCustomObject]@{ Id = 'next-job' } }
            Mock Remove-EwJob {}
            Mock Invoke-EwWorkbenchInfoJobMonitor {}
            Mock Confirm-EwWorkbenchCacheClear { $false }
        }

        AfterEach {
            $state.ActiveJobId = $null
            $state.ActiveJobKind = ''
            $window.Close()
        }

        It 'wires all three maintenance controls in Apps and updates without confirmation' {
            foreach ($name in 'UpdateEvergreenButton', 'ClearWorkbenchCacheButton', 'OpenCacheFolderButton', 'AppsMaintenanceStatusLabel') {
                $window.FindName($name) | Should -Not -BeNullOrEmpty
            }
            $state.UpdateEvergreenButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            $state.ActiveJobKind | Should -Be 'EvergreenUpdate'
            $state.UpdateEvergreenButton.IsEnabled | Should -BeFalse
            $state.ClearWorkbenchCacheButton.IsEnabled | Should -BeFalse
            Should -Invoke Confirm-EwWorkbenchCacheClear -Times 0
            Should -Invoke Start-EwJob -Times 1 -ParameterFilter {
                $ScriptBlock.ToString() -match 'Update-EwEvergreen -Confirm:\$false' -and
                $ScriptBlock.ToString() -notmatch 'Update-Module'
            }
        }

        It 'declines clear without starting any job' {
            $state.ClearWorkbenchCacheButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            Should -Invoke Confirm-EwWorkbenchCacheClear -Times 1
            Should -Invoke Start-EwJob -Times 0
            $state.MaintenancePromptActive | Should -BeFalse
        }

        It 'starts confirmed clear once with headless confirmation disabled' {
            Mock Confirm-EwWorkbenchCacheClear { $true }
            Invoke-EwWorkbenchMaintenanceAction -State $state -Action Clear
            $state.ActiveJobKind | Should -Be 'CacheClear'
            Should -Invoke Start-EwJob -Times 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Clear-EwCache -Confirm:\$false' }
        }

        It 'does not queue maintenance behind another operation or reenter a prompt' {
            $state.ActiveJobId = 'existing'
            Invoke-EwWorkbenchMaintenanceAction -State $state -Action Clear
            $state.ActiveJobId = $null
            $state.MaintenancePromptActive = $true
            Invoke-EwWorkbenchMaintenanceAction -State $state -Action Update
            Invoke-EwWorkbenchJobMonitor -State $state
            Should -Invoke Start-EwJob -Times 0
            Should -Invoke Confirm-EwWorkbenchCacheClear -Times 0
            Should -Invoke Invoke-EwWorkbenchInfoJobMonitor -Times 0
            $state.MaintenancePromptActive = $false
        }

        It 'blocks closing during mutations and allows closing during read-only refresh' {
            foreach ($kind in 'EvergreenUpdate', 'CacheClear', 'IntunePublish', 'IntuneRetry', 'NerdioPublish') {
                $state.ActiveJobKind = $kind
                $closingArgs = [System.ComponentModel.CancelEventArgs]::new()
                Invoke-EwWorkbenchClosingGuard -State $state -ClosingArgs $closingArgs
                $closingArgs.Cancel | Should -BeTrue
            }
            foreach ($kind in 'MaintenanceCatalog', 'MaintenanceArtifacts', '') {
                $state.ActiveJobKind = $kind
                $closingArgs = [System.ComponentModel.CancelEventArgs]::new()
                Invoke-EwWorkbenchClosingGuard -State $state -ClosingArgs $closingArgs
                $closingArgs.Cancel | Should -BeFalse
            }
        }

        It 'removes the mutation job and clears its active identity before the forced catalog reload starts' {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000001'
            $state.ActiveJobKind = 'EvergreenUpdate'
            $script:removedMutation = $false
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = '00000000-0000-0000-0000-000000000001'; State = 'Completed'; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @()
                    Output = @('native output', [PSCustomObject]@{ Succeeded = $true; Error = '' }, 'trailing native output')
                }
            }
            Mock Remove-EwJob { $script:removedMutation = $true }
            Mock Start-EwJob {
                $script:removedMutation | Should -BeTrue
                $state.ActiveJobId | Should -BeNullOrEmpty
                $state.ActiveJobKind | Should -Be ''
                [PSCustomObject]@{ Id = 'catalog' }
            }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobKind | Should -Be 'MaintenanceCatalog'
            Should -Invoke Start-EwJob -Times 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-EwApp -Force' }
            $closingArgs = [System.ComponentModel.CancelEventArgs]::new()
            Invoke-EwWorkbenchClosingGuard -State $state -ClosingArgs $closingArgs
            $closingArgs.Cancel | Should -BeFalse
        }

        It 'retains the display and starts no refresh when maintenance fails entirely' {
            $job = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @([PSCustomObject]@{ Succeeded = $false; Error = 'update failed' }) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind EvergreenUpdate -Job $job | Should -Be ''
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'failed.*update failed'
            $state.AllArtifacts[0] | Should -Be $artifact
            $state.AppsDisplayStale | Should -BeFalse
            Should -Invoke Start-EwJob -Times 0
        }

        It 'starts selected Artifact reload only after catalog job cleanup' {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000004'
            $state.ActiveJobKind = 'MaintenanceCatalog'
            $script:catalogRemoved = $false
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = '00000000-0000-0000-0000-000000000004'; State = 'Completed'; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @(); Output = @($app)
                }
            }
            Mock Remove-EwJob { $script:catalogRemoved = $true }
            Mock Start-EwJob {
                $script:catalogRemoved | Should -BeTrue
                $state.ActiveJobId | Should -BeNullOrEmpty
                [PSCustomObject]@{ Id = 'artifacts' }
            }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobKind | Should -Be 'MaintenanceArtifacts'
            Should -Invoke Start-EwJob -Times 1 -ParameterFilter { $ArgumentList[0] -eq 'TestApp' }
        }

        It 'does not start the next maintenance read when completed job cleanup fails' {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000005'
            $state.ActiveJobKind = 'EvergreenUpdate'
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = '00000000-0000-0000-0000-000000000005'; State = 'Completed'; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @()
                    Output = @([PSCustomObject]@{ Succeeded = $true; Error = '' })
                }
            }
            Mock Remove-EwJob { throw 'cleanup unavailable' }
            Invoke-EwWorkbenchJobMonitor -State $state
            Should -Invoke Start-EwJob -Times 0
            $state.ActiveJobId | Should -BeNullOrEmpty
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'succeeded.*STALE.*cleanup unavailable'
            $state.AllArtifacts[0] | Should -Be $artifact
        }

        It 'settles an unreadable <Kind> once and restores controls despite cleanup errors: <CleanupFails>' -ForEach @(
            @{ Kind = 'MaintenanceCatalog'; CleanupFails = $false },
            @{ Kind = 'MaintenanceArtifacts'; CleanupFails = $false },
            @{ Kind = 'MaintenanceCatalog'; CleanupFails = $true },
            @{ Kind = 'MaintenanceArtifacts'; CleanupFails = $true }
        ) {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000006'
            $state.ActiveJobKind = $Kind
            $state.MaintenanceContext.Outcome = 'Workbench cache clearing partially completed: locked entry.'
            Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
            Mock Get-EwJob { throw 'job snapshot unavailable' }
            Mock Stop-EwJob {}
            if ($CleanupFails) {
                Mock Stop-EwJob { throw 'stop unavailable' }
                Mock Remove-EwJob { throw 'remove unavailable' }
            }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobId | Should -BeNullOrEmpty
            $state.ActiveJobKind | Should -Be ''
            $state.AppsDisplayStale | Should -BeTrue
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'partially completed.*locked entry.*STALE'
            $state.AppCatalog[0] | Should -Be $app
            $state.AllArtifacts[0] | Should -Be $artifact
            $state.Queue.Count | Should -Be 1
            $state.Queue[0].Artifact | Should -Be $artifact
            $state.UpdateEvergreenButton.IsEnabled | Should -BeTrue
            $state.ClearWorkbenchCacheButton.IsEnabled | Should -BeTrue
            $state.RefreshAppsButton.IsEnabled | Should -BeTrue
            $state.AppsListView.IsEnabled | Should -BeTrue
            $state.AppSearchBox.IsEnabled | Should -BeTrue
            if ($CleanupFails) {
                $state.ActivityLog.Text | Should -Match 'stop unavailable'
                $state.ActivityLog.Text | Should -Match 'remove unavailable'
            }
            $settledLog = $state.ActivityLog.Text
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActivityLog.Text | Should -Be $settledLog
            Should -Invoke Get-EwJob -Times 1 -Exactly
            Should -Invoke Stop-EwJob -Times 1 -Exactly -ParameterFilter {
                $Id -eq [guid]'00000000-0000-0000-0000-000000000006' -and -not $Confirm
            }
            Should -Invoke Remove-EwJob -Times 1 -Exactly -ParameterFilter {
                $Id -eq [guid]'00000000-0000-0000-0000-000000000006' -and -not $Confirm
            }
            Should -Invoke Start-EwJob -Times 0
        }

        It 'keeps unreadable mutation <Kind> fail-closed without stopping or removing it' -ForEach @(
            @{ Kind = 'EvergreenUpdate' },
            @{ Kind = 'CacheClear' }
        ) {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000007'
            $state.ActiveJobKind = $Kind
            Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
            Mock Get-EwJob { throw 'mutation snapshot unavailable' }
            Mock Stop-EwJob {}
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActiveJobId | Should -Be '00000000-0000-0000-0000-000000000007'
            $state.ActiveJobKind | Should -Be $Kind
            $state.UpdateEvergreenButton.IsEnabled | Should -BeFalse
            $state.ClearWorkbenchCacheButton.IsEnabled | Should -BeFalse
            Should -Invoke Stop-EwJob -Times 0
            Should -Invoke Remove-EwJob -Times 0
            Should -Invoke Start-EwJob -Times 0
        }

        It 'refreshes once after a changed partial clear and preserves the partial error through refresh' {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000002'
            $state.ActiveJobKind = 'CacheClear'
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = '00000000-0000-0000-0000-000000000002'; State = 'Completed'; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @()
                    Output = @([PSCustomObject]@{ Succeeded = $false; Changed = $true; Error = 'locked cache entry'; Errors = @('locked cache entry') })
                }
            }
            Invoke-EwWorkbenchJobMonitor -State $state
            Should -Invoke Start-EwJob -Times 1
            $state.ActiveJobKind | Should -Be 'MaintenanceCatalog'
            $state.MaintenanceContext.Outcome | Should -Match 'partially completed.*locked cache entry'
            $catalog = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($app) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceCatalog -Job $catalog | Should -Be 'Artifacts'
            $versions = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($artifact) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceArtifacts -Job $versions | Should -Be ''
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'locked cache entry.*Apps refreshed'
        }

        It 'marks previous catalog and Artifacts STALE on refresh failure without losing the maintenance outcome' -ForEach @(
            @{ Kind = 'MaintenanceCatalog' },
            @{ Kind = 'MaintenanceArtifacts' }
        ) {
            $state.MaintenanceContext.Catalog = @([PSCustomObject]@{ Name = 'TestApp'; FriendlyName = 'New App'; IsFavourite = $true })
            $job = [PSCustomObject]@{ State = 'Failed'; TerminatingError = $null; Output = @() }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind $Kind -Job $job | Should -Be ''
            $state.AppCatalog[0] | Should -Be $app
            $state.AllArtifacts[0] | Should -Be $artifact
            $state.AppsDisplayStale | Should -BeTrue
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'Update succeeded.*STALE.*refresh failed'
            $state.ArtifactCountLabel.Text | Should -Match '^STALE'
            $state.Queue[0].Artifact | Should -Be $artifact
        }

        It 'preserves app search favourites filters and queued version snapshots across both refresh stages' {
            $state.AppSearchBox.Text = 'Test'
            $state.ArtifactFilterControls['Architecture'].Control.SelectedItem = 'x64'
            Invoke-EwWorkbenchMaintenanceAction -State $state -Action Update
            $newApp = [PSCustomObject]@{ Name = 'TestApp'; FriendlyName = 'Test App New'; IsFavourite = $true }
            $catalog = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($newApp) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceCatalog -Job $catalog | Should -Be 'Artifacts'
            $state.AppCatalog[0] | Should -Be $app
            $newArtifacts = @(
                [PSCustomObject]@{ Version = '2.0'; Architecture = 'x64'; URI = 'https://example.test/new.msi' },
                [PSCustomObject]@{ Version = '2.0'; Architecture = 'x86'; URI = 'https://example.test/new-x86.msi' }
            )
            $versions = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = $newArtifacts }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceArtifacts -Job $versions | Should -Be ''
            $state.AppSearchBox.Text | Should -Be 'Test'
            $state.CurrentApp | Should -Be $newApp
            $state.AppsListView.SelectedItem | Should -Be $newApp
            $state.FavoriteAppButton.Content | Should -Be 'Remove favourite'
            $state.ArtifactFilterControls['Architecture'].Control.SelectedItem | Should -Be 'x64'
            @($state.ArtifactsGrid.ItemsSource).Count | Should -Be 1
            $state.Queue.Count | Should -Be 1
            $state.Queue[0].Version | Should -Be '1.0'
            $state.Queue[0].Artifact | Should -Be $artifact
        }

        It 'resets unsupported filter values to All and logs a notice' {
            $state.MaintenanceContext.Catalog = @($app)
            $state.MaintenanceContext.Filters = @{ Architecture = 'arm64'; Channel = 'Beta' }
            $job = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($artifact) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceArtifacts -Job $job | Should -Be ''
            $state.ArtifactFilterControls['Architecture'].Control.SelectedIndex | Should -Be 0
            $state.ActivityLog.Text | Should -Match 'arm64.*reset to All'
            $state.ActivityLog.Text | Should -Match "Channel.*reset to All"
        }

        It 'retains selected app details when its new friendly name no longer matches the preserved search' {
            $state.AppSearchBox.Text = 'Test App'
            $newApp = [PSCustomObject]@{ Name = 'TestApp'; FriendlyName = 'Renamed'; IsFavourite = $true }
            $state.MaintenanceContext.Catalog = @($newApp)
            $job = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($artifact) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceArtifacts -Job $job | Should -Be ''
            $state.AppSearchBox.Text | Should -Be 'Test App'
            $state.CurrentApp | Should -Be $newApp
            $state.AllArtifacts.Count | Should -Be 1
            $state.SelectedAppText.Text | Should -Match 'Renamed'
        }

        It 'retains the previous display if filter metadata cannot be rebuilt' {
            $state.MaintenanceContext.Catalog = @($app)
            Mock Get-EwFilterableProperty { throw 'metadata unavailable' }
            $job = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @($artifact) }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceArtifacts -Job $job | Should -Be ''
            $state.AppCatalog[0] | Should -Be $app
            $state.AllArtifacts[0] | Should -Be $artifact
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'STALE.*metadata unavailable'
        }

        It 'forwards native maintenance progress and information into the existing ActivityLog' {
            $state.ActiveJobId = '00000000-0000-0000-0000-000000000003'
            $state.ActiveJobKind = 'EvergreenUpdate'
            Mock Get-EwJob {
                [PSCustomObject]@{
                    Id = '00000000-0000-0000-0000-000000000003'; State = 'Running'; TerminatingError = $null
                    Progress = @([System.Management.Automation.ProgressRecord]::new(1, 'Refresh data', 'Fetching application manifests'))
                    Information = @([System.Management.Automation.InformationRecord]::new('Native Evergreen detail', 'Evergreen'))
                    Errors = @(); Output = @()
                }
            }
            Invoke-EwWorkbenchJobMonitor -State $state
            $state.ActivityLog.Text | Should -Match 'Refresh data.*Fetching application manifests'
            $state.ActivityLog.Text | Should -Match 'Native Evergreen detail'
            Should -Invoke Start-EwJob -Times 0
        }

        It 'clears vanished application details with an explanation without modifying the queue' {
            $job = [PSCustomObject]@{ State = 'Completed'; TerminatingError = $null; Output = @() }
            Invoke-EwWorkbenchMaintenanceJobResult -State $state -Kind MaintenanceCatalog -Job $job | Should -Be ''
            $state.CurrentApp | Should -BeNullOrEmpty
            $state.AllArtifacts.Count | Should -Be 0
            $state.SelectedAppText.Text | Should -Match 'no longer in the catalog'
            $state.Queue[0].Artifact | Should -Be $artifact
            Should -Invoke Start-EwJob -Times 0
        }

        It 'creates a missing cache folder before opening it and surfaces opening failures' {
            $cachePath = Join-Path -Path $TestDrive -ChildPath 'new-cache'
            $originalInvoker = $state.ModuleInvoker
            $state.ModuleInvoker = {
                param($Name, $Parameters)
                if ($Name -eq 'Get-EwCachePath') { return $cachePath }
                & $originalInvoker -Name $Name -Parameters $Parameters
            }.GetNewClosure()
            Mock Start-Process { Test-Path -LiteralPath $FilePath -PathType Container | Should -BeTrue }
            $state.OpenCacheFolderButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            $cachePath | Should -Exist
            Should -Invoke Start-Process -Times 1
            Mock Start-Process { throw 'Explorer unavailable' }
            Invoke-EwWorkbenchMaintenanceAction -State $state -Action Open
            $state.AppsMaintenanceStatusLabel.Text | Should -Match 'Open failed.*Explorer unavailable'
            $state.ActivityLog.Text | Should -Match 'Explorer unavailable'
        }
    }
}
