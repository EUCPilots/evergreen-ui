#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}
AfterAll { Remove-Module -Name EvergreenUI -Force }

Describe 'Nerdio WPF view' {
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
                $setup = $state.NerdioPanel.Children | Where-Object { $_ -is [System.Windows.Controls.ScrollViewer] }
                foreach ($section in $setup.Content.Children) { $section.IsExpanded = $true }
                $window.UpdateLayout()
                $state.NerdioComparisonListView.ActualHeight | Should -BeGreaterThan 40
                $state.NerdioPublishResultsListView.ActualHeight | Should -BeGreaterThan 25
                $setup.ExtentHeight | Should -BeGreaterThan $setup.ViewportHeight
                $setup.ScrollToBottom()
                $window.UpdateLayout()
                $savePoint = $state.SaveNerdioSettingsButton.TranslatePoint([System.Windows.Point]::new(0, 0), $setup)
                $savePoint.Y | Should -BeGreaterOrEqual 0
                ($savePoint.Y + $state.SaveNerdioSettingsButton.ActualHeight) | Should -BeLessOrEqual $setup.ActualHeight
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
                $null = Invoke-EwWorkbenchNerdioJobResult -State $state -Kind NerdioPublish `
                    -Job ([PSCustomObject]@{ State = 'Completed'; Output = @($pending); TerminatingError = $null })
                $state.NerdioResults.Count | Should -Be 1
                $state.NerdioBlockedOutcomes.ContainsKey('nme.test|app-path') | Should -BeTrue
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
}
