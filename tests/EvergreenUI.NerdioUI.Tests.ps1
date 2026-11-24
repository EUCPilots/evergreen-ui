#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $script:testAppData = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "EvergreenUI.NerdioUI.Tests.$([guid]::NewGuid())"
    $env:APPDATA = $script:testAppData
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}
AfterAll {
    Remove-Module -Name EvergreenUI -Force
    $env:APPDATA = $script:originalAppData
    if (Test-Path -LiteralPath $script:testAppData) {
        Remove-Item -LiteralPath $script:testAppData -Recurse -Force
    }
}

Describe 'Nerdio WPF view' {
    BeforeEach {
        $recoveryPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\nerdio-recovery.json'
        if (Test-Path -LiteralPath $recoveryPath) {
            Remove-Item -LiteralPath $recoveryPath -Force
        }
    }

    It 'places provider setup on the Nerdio Settings tab' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavNerdio.IsChecked = $true
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $tabs = $state.NerdioPanel.Children[0]
                @($tabs.Items | ForEach-Object { $_.Header }) | Should -Be @('Shell Apps', 'Microsoft 365 Apps', 'Settings')
                $tabs.SelectedIndex | Should -Be 0
                $setup = $window.FindName('NerdioSetupScrollViewer')
                $tabs.Items[2].Content | Should -Be $setup.Parent
                @($setup.Content.Children | ForEach-Object { $_.Header }) |
                    Should -Be @('Azure storage setup', 'Nerdio API setup', 'Shell App definitions')
                $setup.Content.Children[0].Content.Children.Contains($state.NerdioTenantIdBox) | Should -BeTrue
                $setup.Content.Children[1].Content.Children.Contains($state.NmeHostBox) | Should -BeTrue
                $setup.Content.Children[2].Content.Children.Contains($state.NerdioDefinitionsPathBox.Parent) | Should -BeTrue
                $tabs.Items[0].Content | Should -Be $state.NerdioComparisonListView.Parent
            }
            finally { $window.Close() }
        }
    }

    It 'keeps comparison and results usable at the minimum window size in both native themes' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavNerdio.IsChecked = $true
                $window.Width = $window.MinWidth
                $window.Height = $window.MinHeight
                $window.Show()
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $state.NerdioComparisonListView.ActualHeight | Should -BeGreaterThan 100
                    $state.NerdioPublishResultsListView.ActualHeight | Should -BeGreaterThan 60
                    $state.NerdioComparisonListView.ActualWidth | Should -BeGreaterThan 500
                    $state.NerdioConnectionStatusLabel.Foreground.Color | Should -Be $window.TryFindResource('TextFillColorPrimaryBrush').Color
                    $button = $state.PublishSelectedNerdioButton
                    $point = $button.TranslatePoint([System.Windows.Point]::new(0, 0), $state.NerdioPanel)
                    ($point.X + $button.ActualWidth) | Should -BeLessOrEqual $state.NerdioPanel.ActualWidth
                }
                $tabs = $state.NerdioPanel.Children[0]
                $tabs.SelectedIndex = 2
                $setup = $window.FindName('NerdioSetupScrollViewer')
                foreach ($section in $setup.Content.Children) { $section.IsExpanded = $true }
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $state.NerdioConnectionStatusLabel.Text = "Connection status in $mode"
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $window.FindName('NerdioSettingsConnectionStatusLabel').Text | Should -Be "Connection status in $mode"
                    $setup.ExtentHeight | Should -BeGreaterThan $setup.ViewportHeight
                    $setup.ScrollToBottom()
                    $window.UpdateLayout()
                    $savePoint = $state.SaveNerdioSettingsButton.TranslatePoint([System.Windows.Point]::new(0, 0), $setup)
                    $savePoint.Y | Should -BeGreaterOrEqual 0
                    ($savePoint.Y + $state.SaveNerdioSettingsButton.ActualHeight) | Should -BeLessOrEqual $setup.ActualHeight
                }
                $tabs.SelectedIndex = 0
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $state.NerdioComparisonListView.ActualHeight | Should -BeGreaterThan 100
                $state.NerdioPublishResultsListView.ActualHeight | Should -BeGreaterThan 60
            }
            finally { $window.Close() }
        }
    }

    It 'uses dedicated navigation and staged storage discovery without touching Intune state' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavNerdio.IsChecked = $true
                $state.NerdioPanel.Visibility.ToString() | Should -Be 'Visible'
                $state.IntunePanel.Visibility.ToString() | Should -Be 'Collapsed'
                $state.ViewTitleText.Text | Should -Be 'Nerdio'
                $state.NavIntune.Content | Should -Be 'Intune'
                $state.IntuneTenantId = 'intune-tenant'
                $state.NerdioAzureIdentity = [PSCustomObject]@{ TenantId = 'tenant'; SubscriptionId = 'sub' }
                $state.AllowNerdioEvents = $false
                $state.NmeResourceGroupCombo.ItemsSource = [string[]]@('rg-one', 'rg-two')
                $state.NmeStorageAccountCombo.ItemsSource = [string[]]@('storage')
                $state.NmeContainerCombo.ItemsSource = [string[]]@('container')
                $state.NmeStorageAccountCombo.SelectedItem = 'storage'
                $state.NmeContainerCombo.SelectedItem = 'container'
                $state.AllowNerdioEvents = $true
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                $state.NmeResourceGroupCombo.SelectedItem = 'rg-two'
                $state.NmeStorageAccountCombo.Items.Count | Should -Be 0
                $state.NmeContainerCombo.Items.Count | Should -Be 0
                $state.NerdioDestination | Should -BeNullOrEmpty
                $state.IntuneTenantId | Should -Be 'intune-tenant'
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Nerdio Storage' }
            }
            finally { $window.Close() }
        }
    }

    It 'saves non-secret setup only on explicit Save and clears the password on connect' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavNerdio.IsChecked = $true
                $tabs = $state.NerdioPanel.Children[0]
                $tabs.SelectedIndex = 2
                Mock Set-EwSetting {}
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                $state.NmeHostBox.Text = 'nme.test'
                $state.NmeClientSecretBox.Password = 'synthetic-secret'
                $destination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                $state.NerdioDestination = $destination
                $state.NerdioPlan = [PSCustomObject]@{ Items = @() }
                $state.NerdioDefinitionsPathBox.Text = 'changed-definitions'
                $state.NerdioDestination | Should -Be $destination
                $state.NerdioPlan | Should -BeNullOrEmpty
                $tabs.SelectedIndex = 0
                $tabs.SelectedIndex = 2
                $state.NmeHostBox.Text | Should -Be 'nme.test'
                Should -Invoke Set-EwSetting -Exactly 0
                $state.SaveNerdioSettingsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                Should -Invoke Set-EwSetting -Exactly 10
                Should -Invoke Set-EwSetting -Exactly 0 -ParameterFilter { $Value -eq 'synthetic-secret' }
                $state.NerdioAzureIdentity = [PSCustomObject]@{ TenantId = 'tenant'; SubscriptionId = 'sub' }
                $state.AllowNerdioEvents = $false
                $state.NmeContainerCombo.ItemsSource = [string[]]@('container')
                $state.NmeContainerCombo.SelectedItem = 'container'
                $state.AllowNerdioEvents = $true
                Invoke-EwWorkbenchNerdioAction -State $state -Action ApiConnect
                $state.NmeClientSecretBox.Password | Should -Be ''
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Nerdio ApiConnect' }
            }
            finally { $window.Close() }
        }
    }

    It 'restores unresolved outcomes and pruning offers from durable recovery state' {
        InModuleScope EvergreenUI {
            $destination = [ordered]@{
                TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation ([ordered]@{
                    Id = 'restart-publish'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                    Name = 'Browser'; DefinitionPath = 'C:\Apps\Browser'; Version = '2.0'
                    AppId = '42'; JobId = 'job'; BlobName = 'blob'; Error = 'Inspect Nerdio'
                }) | Out-Null
            Invoke-EwNerdioRecoveryStore -Action Update -UpsertOffer ([ordered]@{
                    Id = 'restart-offer'; Type = 'PruningOffer'; Destination = $destination
                    AppId = '43'; Name = 'Editor'; PublishedVersion = '3.0'
                }) | Out-Null
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NerdioResults | Should -HaveCount 1
                $state.NerdioResults[0].RecoveryOperationId | Should -Be 'restart-publish'
                $state.NerdioResults[0].Status | Should -Be 'Unknown'
                $state.NerdioBlockedOutcomes.ContainsKey('restart-publish') | Should -BeTrue
                $state.NerdioPruningOffers | Should -HaveCount 1
                $state.NerdioPruningOffers[0].Id | Should -Be 'restart-offer'
            }
            finally { $window.Close() }
        }
    }

    It 'declining confirmation does not start publishing and pending outcomes survive comparison refresh' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = [PSCustomObject]@{
                    AppName = 'App'; DefinitionPath = 'app-path'; SourceVersion = '2'; Eligible = $true
                    Operation = 'Create'; NerdioAppId = ''; Message = ''
                }
                $plan = [PSCustomObject]@{ DefinitionRoot = 'root'; Destination = [PSCustomObject]@{ NmeHost = 'nme.test' }; Items = @($row) }
                $state.NerdioPlan = $plan
                $state.NerdioDestination = $plan.Destination
                $state.NerdioComparisonListView.ItemsSource = [object[]]@($row)
                $state.NerdioComparisonListView.SelectedItem = $row
                Mock Confirm-EwWorkbenchNerdioBatch { $false }
                Mock Start-EwJob {}
                Invoke-EwWorkbenchNerdioAction -State $state -Action Publish
                Should -Invoke Start-EwJob -Exactly 0
                $pending = [PSCustomObject]@{
                    Name = 'App'; DefinitionPath = 'app-path'; Version = '2'; Status = 'Pending'
                    AppId = 'id'; JobId = 'job'; BlobName = 'blob'; Succeeded = $false; Error = 'Review'
                }
                $recoveryState = [ordered]@{
                    SchemaVersion = 1
                    Operations = @([ordered]@{
                            Id = 'pending-op'; Type = 'Publish'; Status = 'Pending'; Name = 'App'
                            DefinitionPath = 'app-path'; Version = '2'; AppId = 'id'; JobId = 'job'
                            BlobName = 'blob'; Error = 'Review'
                            Destination = [ordered]@{ NmeHost = 'nme.test' }
                        })
                    PruningOffers = @()
                }
                Mock Invoke-EwNerdioRecoveryStore { $recoveryState }
                $null = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPublish `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = @($pending); TerminatingError = $null })
                $state.NerdioResults.Count | Should -Be 1
                $state.NerdioBlockedOutcomes.ContainsKey('pending-op') | Should -BeTrue
                $other = [PSCustomObject]@{
                    AppName = 'Other'; DefinitionPath = 'other-path'; SourceVersion = '2'; Eligible = $true
                    Operation = 'Create'; NerdioAppId = ''; Message = ''
                }
                $plan.Items += $other
                $null = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioCompare `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = @($plan); TerminatingError = $null })
                $row.Eligible | Should -BeFalse
                $other.Eligible | Should -BeFalse
                $state.NerdioResults.Count | Should -Be 1
                $other.Eligible = $true
                $state.NerdioComparisonListView.SelectedItem = $other
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.PublishSelectedNerdioButton.IsEnabled | Should -BeFalse
                Invoke-EwWorkbenchNerdioAction -State $state -Action Publish
                Should -Invoke Confirm-EwWorkbenchNerdioBatch -Exactly 1
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally { $window.Close() }
        }
    }

    It 'makes cancellation cooperative and disables connection changes during publishing' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'NerdioPublish'
                $state.NerdioCancellation = [System.Threading.CancellationTokenSource]::new()
                Invoke-EwWorkbenchBusyState -State $state -IsBusy $true
                $state.NmeHostBox.IsEnabled | Should -BeFalse
                $state.DisconnectNerdioButton.IsEnabled | Should -BeFalse
                $state.CancelNerdioBatchButton.IsEnabled | Should -BeTrue
                Mock Stop-EwJob {}
                Invoke-EwWorkbenchNerdioAction -State $state -Action Cancel
                $state.NerdioCancellation.IsCancellationRequested | Should -BeTrue
                Should -Invoke Stop-EwJob -Exactly 0
                Mock Get-EwJob { throw 'Job snapshot unavailable' }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.ActiveJobKind | Should -Be 'NerdioPublish'
                $state.ActiveJobId | Should -Not -BeNullOrEmpty
                $state.DisconnectNerdioButton.IsEnabled | Should -BeFalse
                $state.NerdioCancellation.Dispose()
            }
            finally { $window.Close() }
        }
    }

    It 'enables standalone pruning only for one matched existing row regardless of publishing eligibility' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = [PSCustomObject]@{ RowType = 'Definition'; NerdioAppId = '42'; Eligible = $false }
                $other = [PSCustomObject]@{ RowType = 'Definition'; NerdioAppId = '43'; Eligible = $false }
                $state.NerdioPlan = [PSCustomObject]@{ Items = @($row, $other) }
                $state.NerdioDestination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                $state.NerdioComparisonListView.ItemsSource = [object[]]@($row, $other)
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
                $state.NerdioComparisonListView.SelectedItem = $row
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeTrue
                $state.PublishSelectedNerdioButton.IsEnabled | Should -BeFalse
                $state.NerdioComparisonListView.SelectedItems.Add($other) | Out-Null
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
                $state.NerdioComparisonListView.SelectedItems.Remove($other)
                $row.NerdioAppId = ''
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
                $row.NerdioAppId = '42'
                $row.RowType = 'Nerdio'
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
            }
            finally { $window.Close() }
        }
    }

    It 'previews and prunes a selected app without a publish offer then refreshes and restores its selection' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = [PSCustomObject]@{
                    RowType = 'Definition'; AppName = 'App'; NerdioAppName = 'App'; NerdioAppId = '42'
                    DefinitionPath = 'app-path'; Publisher = 'Publisher'; Eligible = $false; VersionCount = 3
                }
                $destination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                $state.NerdioDestination = $destination
                $state.NerdioPlan = [PSCustomObject]@{ Destination = $destination; Items = @($row) }
                $state.NerdioComparisonListView.ItemsSource = [object[]]@($row)
                $state.NerdioComparisonListView.SelectedItem = $row
                Mock Start-EwJob {
                    $script:pruneWorker = $ScriptBlock
                    $script:pruneArguments = $ArgumentList
                    [PSCustomObject]@{ Id = [guid]::NewGuid() }
                }
                Mock Assert-EwNerdioDestination {}
                Mock Get-EwNerdioShellAppVersion {
                    @('1.0', '3.0', '2.0') | ForEach-Object { [PSCustomObject]@{ name = $_ } }
                }
                Mock Show-EwWorkbenchNerdioPruneDialog {
                    param($Plans)
                    $Plans
                }
                Mock Remove-EwNerdioShellAppVersion {
                    [PSCustomObject]@{ Id = '42'; RemovedCount = 2; FailedCount = 0; PendingVersions = @(); UnknownVersions = @() }
                }
                $state.PruneSelectedNerdioVersionsButton.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $state.ActiveJobKind | Should -Be 'NerdioPrunePreview'
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
                $preview = @(& $script:pruneWorker @script:pruneArguments)
                $preview | Should -HaveCount 1
                $preview[0].OfferId | Should -BeNullOrEmpty
                $preview[0].PublishedVersion | Should -BeNullOrEmpty
                $preview[0].Keep | Should -Be @('3.0')
                $preview[0].Remove | Should -Be @('2.0', '1.0')
                $preview[0].Destination | Should -Be $destination
                $next = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPrunePreview `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = $preview; TerminatingError = $null })
                $next | Should -Be 'PruneSelected'
                $state.ActiveJobId = $null
                Invoke-EwWorkbenchNerdioAction -State $state -Action $next
                $outcomes = @(& $script:pruneWorker @script:pruneArguments)
                Should -Invoke Remove-EwNerdioShellAppVersion -Exactly 1 -ParameterFilter {
                    $Id -eq '42' -and $KeepVersions -eq 1 -and -not $OfferId -and -not $Confirm -and
                    ($ExpectedVersionNames -join ',') -eq '1.0,3.0,2.0' -and
                    ($ExpectedRemovalVersions -join ',') -eq '2.0,1.0'
                }
                Should -Invoke Assert-EwNerdioDestination -Exactly 3 -ParameterFilter { $Destination.NmeHost -eq 'nme.test' }
                $next = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPruneSelected `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = $outcomes; TerminatingError = $null })
                $next | Should -Be 'Compare'
                $state.NerdioComparisonListView.Items.Count | Should -Be 0
                $row.VersionCount = 1
                $refreshed = [PSCustomObject]@{ Destination = $destination; Items = @($row) }
                $null = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioCompare `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = @($refreshed); TerminatingError = $null })
                $state.NerdioComparisonListView.SelectedItem.NerdioAppId | Should -Be '42'
                $state.NerdioComparisonListView.SelectedItem.VersionCount | Should -Be 1
                $state.NerdioPruneSelectionId | Should -BeNullOrEmpty
            }
            finally { $window.Close() }
        }
    }

    It 'does not delete when the standalone preview is cancelled' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Show-EwWorkbenchNerdioPruneDialog { @() }
                Mock Start-EwJob {}
                $next = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPrunePreview `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = @([PSCustomObject]@{ Id = '42' }); TerminatingError = $null })
                $next | Should -BeNullOrEmpty
                $state.NerdioSelectedPrunePlans | Should -HaveCount 0
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally { $window.Close() }
        }
    }

    It 'blocks standalone preview and execution when recovery is unresolved or unavailable' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = [PSCustomObject]@{ RowType = 'Definition'; NerdioAppId = '42'; Eligible = $false }
                $state.NerdioDestination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                $state.NerdioPlan = [PSCustomObject]@{ Items = @($row) }
                $state.NerdioComparisonListView.ItemsSource = [object[]]@($row)
                $state.NerdioComparisonListView.SelectedItem = $row
                Mock Start-EwJob {}
                Mock Sync-EwWorkbenchNerdioRecoveryState {
                    param($State)
                    $State.NerdioBlockedOutcomes['unrelated-app'] = [PSCustomObject]@{ Type = 'Delete'; AppId = '43' }
                    $true
                }
                foreach ($action in 'PruneExisting', 'PruneSelected') {
                    Invoke-EwWorkbenchNerdioAction -State $state -Action $action
                }
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.PruneSelectedNerdioVersionsButton.IsEnabled | Should -BeFalse
                Mock Sync-EwWorkbenchNerdioRecoveryState { $false }
                foreach ($action in 'PruneExisting', 'PruneSelected') {
                    Invoke-EwWorkbenchNerdioAction -State $state -Action $action
                }
                Should -Invoke Start-EwJob -Exactly 0
            }
            finally { $window.Close() }
        }
    }

    It 'rejects a changed destination or newly unresolved operation in the deletion worker' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $plan = [PSCustomObject]@{
                    Id = '42'; OfferId = ''; Eligible = $true; KeepVersions = 1
                    VersionNames = @('1.0', '2.0'); Remove = @('1.0')
                    Destination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                }
                Mock Start-EwJob {
                    $script:pruneWorker = $ScriptBlock
                    $script:pruneArguments = $ArgumentList
                    [PSCustomObject]@{ Id = [guid]::NewGuid() }
                }
                Mock Assert-EwNerdioDestination { throw 'The confirmed Nerdio destination changed.' }
                Mock Remove-EwNerdioShellAppVersion {}
                Invoke-EwWorkbenchNerdioAction -State $state -Action PruneSelected -Selection @($plan)
                { & $script:pruneWorker @script:pruneArguments } | Should -Throw '*destination changed*'
                Mock Invoke-EwNerdioRecoveryStore { [PSCustomObject]@{ Operations = @([PSCustomObject]@{ AppId = '43' }) } }
                { & $script:pruneWorker @script:pruneArguments } | Should -Throw '*Review all pending or unknown*'
                Should -Invoke Remove-EwNerdioShellAppVersion -Exactly 0
                Should -Invoke Assert-EwNerdioDestination -Exactly 1
            }
            finally { $window.Close() }
        }
    }

    It 'refreshes comparison after an interrupted standalone deletion without retrying it' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NerdioDestination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                $state.NerdioPruneSelectionId = '42'
                Mock Remove-EwNerdioShellAppVersion {}
                $next = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPruneSelected `
                    -Job ([PSCustomObject]@{ State = 'Failed'; Output = @(); TerminatingError = 'Worker interrupted' })
                $next | Should -Be 'Compare'
                $state.NerdioPruneSelectionId | Should -Be '42'
                Should -Invoke Remove-EwNerdioShellAppVersion -Exactly 0
            }
            finally { $window.Close() }
        }
    }

    It 'retains the published-version constraint and offer identity for post-publish pruning' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NerdioDestination = [PSCustomObject]@{ NmeHost = 'nme.test' }
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOffer ([ordered]@{
                        Id = 'publish-offer'; Type = 'PruningOffer'
                        Destination = [ordered]@{ NmeHost = 'nme.test' }
                        AppId = '42'; Name = 'App'; Publisher = 'Publisher'; DefinitionPath = 'app-path'
                        PublishedVersion = '2.0'
                    }) | Out-Null
                Mock Start-EwJob {
                    $script:pruneWorker = $ScriptBlock
                    $script:pruneArguments = $ArgumentList
                    [PSCustomObject]@{ Id = [guid]::NewGuid() }
                }
                Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ NmeHost = 'nme.test' } }
                Mock Assert-EwNerdioRecoveryDestination {}
                Mock Get-EwNerdioShellAppVersion {
                    @('1.0', '2.0') | ForEach-Object { [PSCustomObject]@{ name = $_ } }
                }
                Invoke-EwWorkbenchNerdioAction -State $state -Action Prune
                $preview = @(& $script:pruneWorker @script:pruneArguments)
                $preview[0].PublishedVersion | Should -Be '2.0'
                $preview[0].OfferId | Should -Be 'publish-offer'
                $preview[0].Destination.NmeHost | Should -Be 'nme.test'
                $state.ActiveJobId = $null
                Invoke-EwWorkbenchNerdioAction -State $state -Action PruneSelected -Selection $preview
                $state.NerdioPruneSelectionId | Should -BeNullOrEmpty
            }
            finally { $window.Close() }
        }
    }

    It 'uses standalone wording and disables no-op retention plans in the shared dialog' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                Mock Get-EwNerdioShellAppVersion {
                    @('1.0', '2.0') | ForEach-Object { [PSCustomObject]@{ name = $_ } }
                }
                $plan = Get-EwNerdioShellAppVersionPrunePlan -Id '42'
                $plan | Add-Member -NotePropertyName Name -NotePropertyValue 'App'
                $observed = @{}
                $window.Show()
                $window.Dispatcher.BeginInvoke([action]{
                    $dialog = @($window.OwnedWindows)[0]
                    try {
                        $content = $dialog.Content.Children[1]
                        $observed.Label = $content.Children[0].Children[0].Text
                        $retention = $content.Children[0].Children[1]
                        $check = $content.Children[2].Content.Children[0]
                        $observed.Description = [string]$check.Content
                        $observed.InitiallyEnabled = $check.IsEnabled
                        $check.IsChecked = $true
                        $retention.Text = '2'
                        $observed.NoOpEnabled = $check.IsEnabled
                    }
                    finally { $dialog.Close() }
                }.GetNewClosure()) | Out-Null
                @(Show-EwWorkbenchNerdioPruneDialog -Owner $window -Plans @($plan)) | Should -HaveCount 0
                $observed.Label | Should -Be 'Keep newest versions:'
                $observed.Description | Should -Not -Match 'published:'
                $observed.Description | Should -Match 'keep: 2.0; delete: 1.0'
                $observed.InitiallyEnabled | Should -BeTrue
                $observed.NoOpEnabled | Should -BeFalse
            }
            finally { $window.Close() }
        }
    }
}
