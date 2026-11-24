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

    It 'preserves publishing details and defaults to No in the shared confirmation' {
        InModuleScope EvergreenUI {
            $selection = @([PSCustomObject]@{
                    AppName = 'App & Co'; SourceVersion = '2.0'; Operation = 'Add version'; NerdioAppId = '42'
                })
            $destination = [PSCustomObject]@{
                NmeHost = 'nme.test'; TenantId = 'tenant'; SubscriptionId = 'subscription'
                ResourceGroupName = 'group'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Mock Confirm-EwWorkbenchAction { $true }
            Confirm-EwWorkbenchNerdioBatch -Window ([object]::new()) -Selection $selection -Destination $destination |
                Should -BeTrue
            Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                $Title -eq 'Confirm Nerdio publishing' -and -not $DefaultYes -and
                $Message -match 'Nerdio: nme.test' -and $Message -match 'Tenant: tenant' -and
                $Message -match 'Subscription: subscription' -and $Message -match 'group / storage / container' -and
                $Message -match 'App & Co 2.0: Add version 42' -and
                $Message -match 'Local definitions will not be changed'
            }
            Mock Confirm-EwWorkbenchAction { $false }
            Confirm-EwWorkbenchNerdioBatch -Window ([object]::new()) -Selection $selection -Destination $destination |
                Should -BeFalse
        }
    }

    It 'returns <Expected> from the <Mode> outcome review dialog on <Action>' -ForEach @(
        @{ Mode = 'Light'; Action = 'Yes'; Expected = 'Yes' }
        @{ Mode = 'Dark'; Action = 'No'; Expected = 'No' }
        @{ Mode = 'System'; Action = 'Cancel'; Expected = 'Cancel' }
        @{ Mode = 'Dark'; Action = 'Close'; Expected = 'Cancel' }
        @{ Mode = 'Light'; Action = 'Return'; Expected = 'Cancel' }
        @{ Mode = 'Dark'; Action = 'Escape'; Expected = 'Cancel' }
    ) {
        if ($env:GITHUB_ACTIONS -eq 'true' -and $Action -in 'Return', 'Escape') {
            Set-ItResult -Skipped -Because 'Keyboard focus requires an interactive desktop.'
        }
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; Action = $Action; Expected = $Expected } {
            $owner = Get-EwWorkbenchWindow
            $observed = @{ Action = $Action; Error = ''; InitiallyFocused = $false }
            try {
                $owner.ThemeMode = [System.Windows.ThemeMode]::$Mode
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $dialog = @($owner.OwnedWindows)[0]
                    try {
                        $cancel = $dialog.FindName('ConfirmationCancelButton')
                        $yes = $dialog.FindName('ConfirmationYesButton')
                        $no = $dialog.FindName('ConfirmationNoButton')
                        $observed.SafeDefault = $cancel.IsDefault -and $cancel.IsCancel -and
                            -not $yes.IsDefault -and -not $no.IsDefault -and -not $no.IsCancel
                        $observed.InitiallyFocused = $cancel.IsKeyboardFocused
                        $observed.Accent = $cancel.Style -eq $dialog.TryFindResource('AccentButtonStyle')
                        $observed.Theme = $dialog.ThemeMode
                        $observed.Background = $dialog.TryFindResource('ApplicationBackgroundBrush').Color
                        $observed.OwnerBackground = $owner.TryFindResource('ApplicationBackgroundBrush').Color
                        $observed.Message = $dialog.FindName('ConfirmationMessageText').Text
                        if ($observed.Action -in 'Return', 'Escape') {
                            $key = [System.Windows.Input.Key]::Parse([System.Windows.Input.Key], $observed.Action)
                            $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                                [System.Windows.Input.Keyboard]::PrimaryDevice,
                                [System.Windows.PresentationSource]::FromVisual($dialog), 0, $key
                            )
                            $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                            $null = [System.Windows.Input.InputManager]::Current.ProcessInput($keyArgs)
                        }
                        elseif ($observed.Action -eq 'Close') { $dialog.Close() }
                        else {
                            $button = $dialog.FindName("Confirmation$($observed.Action)Button")
                            $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                            $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke()
                            $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                        }
                    }
                    catch { $observed.Error = $_.Exception.ToString() }
                    finally { if ($dialog.IsVisible) { $dialog.Close() } }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $result = [PSCustomObject]@{ NmeHost = 'nme.test'; Name = 'App'; AppId = '42'; JobId = 'job' }
                $answer = Show-EwWorkbenchNerdioReviewDialog -Owner $owner -Result $result
                $observed.Error | Should -BeNullOrEmpty
                $answer.ToString() | Should -Be $Expected
                $observed.SafeDefault | Should -BeTrue
                $observed.Accent | Should -BeTrue
                $observed.Theme | Should -Be $owner.ThemeMode
                $observed.Background | Should -Be $observed.OwnerBackground
                $observed.Message | Should -Match 'Nerdio host: nme.test'
                $observed.Message | Should -Match 'App ID: 42'
                if ($env:GITHUB_ACTIONS -ne 'true') { $observed.InitiallyFocused | Should -BeTrue }
            }
            finally { $owner.Close() }
        }
    }

    It 'maps <Choice> outcome review to <Outcome> without automatic retries' -ForEach @(
        @{ Choice = 'Yes'; Outcome = 'Completed' }
        @{ Choice = 'No'; Outcome = 'Failed' }
        @{ Choice = 'Cancel'; Outcome = '' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Choice = $Choice; Outcome = $Outcome } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $result = [PSCustomObject]@{
                    Name = 'App'; NmeHost = 'nme.test'; AppId = '42'; JobId = 'job'
                    Status = 'Unknown'; RecoveryOperationId = 'operation'; OutcomeKey = 'operation'
                }
                $state.NerdioResults.Add($result)
                $state.NerdioPublishResultsListView.SelectedItem = $result
                switch ($Choice) {
                    'Yes' { Mock Show-EwWorkbenchNerdioReviewDialog { [System.Windows.MessageBoxResult]::Yes } }
                    'No' { Mock Show-EwWorkbenchNerdioReviewDialog { [System.Windows.MessageBoxResult]::No } }
                    'Cancel' { Mock Show-EwWorkbenchNerdioReviewDialog { [System.Windows.MessageBoxResult]::Cancel } }
                }
                Mock Invoke-EwWorkbenchJob {}
                Invoke-EwWorkbenchNerdioAction -State $state -Action Review
                Should -Invoke Show-EwWorkbenchNerdioReviewDialog -Exactly 1
                if ($Choice -eq 'Cancel') {
                    Should -Invoke Invoke-EwWorkbenchJob -Exactly 0
                }
                else {
                    Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter {
                        $Kind -eq 'NerdioReview' -and $ArgumentList[0] -eq 'operation' -and $ArgumentList[1] -eq $Outcome
                    }
                }
            }
            finally { $window.Close() }
        }
    }

    It 'executes <Choice> outcome review through the real background job with a <Destination> destination' -ForEach @(
        @{ Choice = 'No'; Destination = 'matching'; Matches = $true }
        @{ Choice = 'Yes'; Destination = 'different'; Matches = $false }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Choice = $Choice; Matches = $Matches } {
            $window = Get-EwWorkbenchWindow
            $state = $null
            $originalContext = $script:ewNerdioSession.Context
            try {
                $destination = [ordered]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                $context = [PSCustomObject]$destination
                $context | Add-Member -NotePropertyName TokenExpiresAt -NotePropertyValue ([DateTimeOffset]::UtcNow.AddHours(1))
                if (-not $Matches) { $context.TenantId = 'other-tenant' }
                $script:ewNerdioSession.Context = $context
                $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation ([ordered]@{
                        Id = 'review-job'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                        Name = 'App'; AppId = '42'; Version = '2.0'; JobId = 'job'
                    })
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $result = [PSCustomObject]@{
                    Name = 'App'; NmeHost = 'nme.test'; AppId = '42'; JobId = 'job'
                    Status = 'Unknown'; RecoveryOperationId = 'review-job'; OutcomeKey = 'review-job'
                }
                $state.NerdioResults.Add($result)
                $state.NerdioPublishResultsListView.SelectedItem = $result
                if ($Choice -eq 'No') {
                    Mock Show-EwWorkbenchNerdioReviewDialog { [System.Windows.MessageBoxResult]::No }
                }
                else {
                    Mock Show-EwWorkbenchNerdioReviewDialog { [System.Windows.MessageBoxResult]::Yes }
                }
                Mock Invoke-EwWorkbenchBusyState {}
                Mock Write-EwWorkbenchLog {}

                Invoke-EwWorkbenchNerdioAction -State $state -Action Review
                $state.ActiveJobKind | Should -Be 'NerdioReview'
                $state.ActiveJobId | Should -Not -BeNullOrEmpty
                $handle = $script:ewJobs[$state.ActiveJobId.ToString()].Handle
                $deadline = [DateTime]::UtcNow.AddSeconds(15)
                while (-not $handle.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 50
                }
                $handle.IsCompleted | Should -BeTrue
                $job = Get-EwJob -Id $state.ActiveJobId

                $recovery = Invoke-EwNerdioRecoveryStore -Action Read
                if ($Matches) {
                    $job.TerminatingError | Should -BeNullOrEmpty
                    $job.State | Should -Be 'Completed'
                    @($job.Errors) | Should -HaveCount 0
                    $job.Output[0].Succeeded | Should -BeTrue
                    $job.Output[0].OperationId | Should -Be 'review-job'
                    $job.Output[0].Outcome | Should -Be 'Failed'
                    $recovery.Operations | Should -HaveCount 0
                }
                else {
                    $job.TerminatingError | Should -Match 'destination recorded for this operation'
                    $job.State | Should -Be 'Failed'
                    $recovery.Operations | Should -HaveCount 1
                    $recovery.Operations[0].Id | Should -Be 'review-job'
                }
                $recovery.PruningOffers | Should -HaveCount 0
            }
            finally {
                if ($null -ne $state -and $null -ne $state.ActiveJobId) {
                    $job = Get-EwJob -Id $state.ActiveJobId
                    if ($job.State -notin 'Completed', 'Failed', 'Stopped') {
                        $null = Stop-EwJob -Id $job.Id
                    }
                    Remove-EwJob -Id $job.Id -Confirm:$false
                }
                $script:ewNerdioSession.Context = $originalContext
                $window.Close()
            }
        }
    }

    It 'runs the <Action> pruning worker through the real background job' -ForEach @(
        @{ Action = 'Prune'; Expected = 'destination recorded for this operation' }
        @{ Action = 'PruneExisting'; Expected = 'confirmed Nerdio destination changed' }
        @{ Action = 'PruneSelected'; Expected = 'destination recorded for this operation' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Action = $Action; Expected = $Expected } {
            $window = Get-EwWorkbenchWindow
            $state = $null
            $originalContext = $script:ewNerdioSession.Context
            try {
                $destination = [ordered]@{
                    SessionId = 'session'; TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                $context = [PSCustomObject]$destination
                $context | Add-Member -NotePropertyName TokenExpiresAt -NotePropertyValue ([DateTimeOffset]::UtcNow.AddHours(1))
                $context.TenantId = 'other-tenant'
                $script:ewNerdioSession.Context = $context
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NerdioDestination = $destination
                Mock Sync-EwWorkbenchNerdioRecoveryState { $true }
                Mock Invoke-EwWorkbenchBusyState {}
                Mock Write-EwWorkbenchLog {}
                $selection = @()
                switch ($Action) {
                    'Prune' {
                        $state.NerdioPruningOffers = @([PSCustomObject]@{
                                Id = 'offer'; AppId = '42'; PublishedVersion = '2.0'; Destination = $destination
                                Name = 'App'; Publisher = 'Publisher'; DefinitionPath = 'App'
                            })
                    }
                    'PruneExisting' {
                        $row = [PSCustomObject]@{
                            RowType = 'Definition'; NerdioAppId = '42'; NerdioAppName = 'App'; Eligible = $false
                            Publisher = 'Publisher'; DefinitionPath = 'App'
                        }
                        $state.NerdioPlan = [PSCustomObject]@{ Destination = $destination }
                        $state.NerdioComparisonListView.ItemsSource = @($row)
                        $state.NerdioComparisonListView.SelectedItems.Add($row)
                    }
                    'PruneSelected' {
                        $selection = @([PSCustomObject]@{
                                Id = '42'; OfferId = 'offer'; Destination = $destination; Eligible = $true
                                Remove = @('1.0'); KeepVersions = 1; VersionNames = @('1.0', '2.0')
                            })
                    }
                }

                Invoke-EwWorkbenchNerdioAction -State $state -Action $Action -Selection $selection
                $state.ActiveJobId | Should -Not -BeNullOrEmpty
                $handle = $script:ewJobs[$state.ActiveJobId.ToString()].Handle
                $deadline = [DateTime]::UtcNow.AddSeconds(15)
                while (-not $handle.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 50
                }
                $handle.IsCompleted | Should -BeTrue
                $job = Get-EwJob -Id $state.ActiveJobId
                $job.State | Should -Be 'Failed'
                $job.TerminatingError | Should -Not -Match 'is not recognized'
                $job.TerminatingError | Should -Match $Expected
            }
            finally {
                if ($null -ne $state -and $null -ne $state.ActiveJobId) {
                    $job = Get-EwJob -Id $state.ActiveJobId
                    if ($job.State -notin 'Completed', 'Failed', 'Stopped') {
                        $null = Stop-EwJob -Id $job.Id
                    }
                    Remove-EwJob -Id $job.Id -Confirm:$false
                }
                $script:ewNerdioSession.Context = $originalContext
                $window.Close()
            }
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
                @($setup.Content.Children | Where-Object { $_ -is [System.Windows.Controls.Expander] } | ForEach-Object { $_.Header }) |
                    Should -Be @('Azure storage setup', 'Nerdio API setup')
                $setup.Content.Children[0].Content.Children.Contains($state.NerdioTenantIdBox) | Should -BeTrue
                $setup.Content.Children[1].Content.Children.Contains($state.NmeHostBox) | Should -BeTrue
                $setup.Content.Children.Contains($state.SaveNerdioSetupButton) | Should -BeTrue
                $shellApps = $state.NerdioComparisonListView.Parent
                $tabs.Items[0].Content | Should -Be $shellApps
                $pathPanel = $window.FindName('NerdioDefinitionsPathPanel')
                $pathPanel.Parent | Should -Be $shellApps
                $pathRow = $pathPanel.Children[1]
                foreach ($control in $state.NerdioDefinitionsPathBox, $state.BrowseNerdioDefinitionsButton, $state.SaveNerdioSettingsButton) {
                    $control.Parent | Should -Be $pathRow
                }
                [System.Windows.Controls.Grid]::GetRow($pathPanel) |
                    Should -BeLessThan ([System.Windows.Controls.Grid]::GetRow($state.NerdioComparisonListView))
            }
            finally { $window.Close() }
        }
    }

    It 'shows pruning actions immediately before review with a divider' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavNerdio.IsChecked = $true
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Width = $window.MinWidth
                $window.Height = $window.MinHeight
                $window.Show()
                $prune = $state.PruneSelectedNerdioVersionsButton
                $preview = $state.PruneNerdioVersionsButton
                $review = $state.ReviewNerdioOutcomeButton
                $actions = $review.Parent
                $prune.Parent | Should -Be $actions
                $preview.Parent | Should -Be $actions
                $divider = $actions.Children[$actions.Children.IndexOf($preview) + 1]
                $divider | Should -BeOfType [System.Windows.Controls.Border]
                $actions.Children.IndexOf($review) | Should -Be ($actions.Children.IndexOf($divider) + 1)
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    foreach ($control in $prune, $preview, $divider, $review) {
                        $control.IsVisible | Should -BeTrue
                    }
                    $divider.Background | Should -Not -BeNullOrEmpty
                    $prunePoint = $prune.TranslatePoint([System.Windows.Point]::new(0, 0), $state.NerdioPanel)
                    $previewPoint = $preview.TranslatePoint([System.Windows.Point]::new(0, 0), $state.NerdioPanel)
                    $dividerPoint = $divider.TranslatePoint([System.Windows.Point]::new(0, 0), $state.NerdioPanel)
                    $reviewPoint = $review.TranslatePoint([System.Windows.Point]::new(0, 0), $state.NerdioPanel)
                    ($prunePoint.X + $prune.ActualWidth) | Should -BeLessOrEqual $previewPoint.X
                    ($previewPoint.X + $preview.ActualWidth) | Should -BeLessThan $dividerPoint.X
                    ($dividerPoint.X + $divider.ActualWidth) | Should -BeLessThan $reviewPoint.X
                    ($reviewPoint.X + $review.ActualWidth) | Should -BeLessOrEqual $state.NerdioPanel.ActualWidth
                    $prunePoint.Y | Should -Be $previewPoint.Y
                    $previewPoint.Y | Should -Be $reviewPoint.Y
                }
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
                foreach ($section in $setup.Content.Children) {
                    if ($section -is [System.Windows.Controls.Expander]) { $section.IsExpanded = $true }
                }
                foreach ($mode in 'Light', 'Dark') {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $state.NerdioConnectionStatusLabel.Text = "Connection status in $mode"
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $window.FindName('NerdioSettingsConnectionStatusLabel').Text | Should -Be "Connection status in $mode"
                    $setup.ExtentHeight | Should -BeGreaterThan $setup.ViewportHeight
                    $setup.ScrollToBottom()
                    $window.UpdateLayout()
                    $savePoint = $state.SaveNerdioSetupButton.TranslatePoint([System.Windows.Point]::new(0, 0), $setup)
                    $savePoint.Y | Should -BeGreaterOrEqual 0
                    ($savePoint.Y + $state.SaveNerdioSetupButton.ActualHeight) | Should -BeLessOrEqual $setup.ActualHeight
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
                $state.SaveNerdioSetupButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                Should -Invoke Set-EwSetting -Exactly 20
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

    It 'themes standalone pruning in <Mode> mode and disables no-op retention plans' -ForEach @(
        @{ Mode = 'Light' }
        @{ Mode = 'Dark' }
        @{ Mode = 'System' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.ThemeMode = [System.Windows.ThemeMode]::$Mode
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
                        $observed.Label = $dialog.FindName('NerdioPruneRetentionText').Text
                        $retention = $dialog.FindName('NerdioPruneRetentionBox')
                        $card = $dialog.FindName('NerdioPrunePlansPanel').Children[0]
                        $check = $card.Child
                        $observed.Description = [string]$check.Content.Text
                        $observed.ResizeMode = $dialog.ResizeMode
                        $observed.SizeToContent = $dialog.SizeToContent
                        $observed.Theme = $dialog.ThemeMode
                        $observed.Background = $dialog.TryFindResource('ApplicationBackgroundBrush').Color
                        $observed.OwnerBackground = $window.TryFindResource('ApplicationBackgroundBrush').Color
                        $observed.CardBackground = $card.Background
                        $observed.Accent = $dialog.FindName('ReviewNerdioPruneButton').Style -eq
                            $dialog.TryFindResource('AccentButtonStyle')
                        $observed.RetentionTarget = $dialog.FindName('NerdioPruneRetentionText').Parent.Target -eq $retention
                        $observed.InitiallyEnabled = $check.IsEnabled
                        $check.IsChecked = $true
                        $retention.Text = '2'
                        $observed.NoOpEnabled = $check.IsEnabled
                    }
                    finally { $dialog.Close() }
                }.GetNewClosure()) | Out-Null
                @(Show-EwWorkbenchNerdioPruneDialog -Owner $window -Plans @($plan)) | Should -HaveCount 0
                $observed.Label | Should -Be 'Keep newest versions:'
                $observed.ResizeMode | Should -Be ([System.Windows.ResizeMode]::NoResize)
                $observed.SizeToContent | Should -Be ([System.Windows.SizeToContent]::WidthAndHeight)
                $observed.Theme | Should -Be $window.ThemeMode
                $observed.Background | Should -Be $observed.OwnerBackground
                $observed.CardBackground | Should -Not -BeNullOrEmpty
                $observed.Accent | Should -BeTrue
                $observed.RetentionTarget | Should -BeTrue
                $observed.Description | Should -Not -Match 'published:'
                $observed.Description | Should -Match 'keep: 2.0; delete: 1.0'
                $observed.InitiallyEnabled | Should -BeTrue
                $observed.NoOpEnabled | Should -BeFalse
            }
            finally { $window.Close() }
        }
    }

    It 'shows a themed notice without closing the pruning preview when no apps are selected' {
        InModuleScope EvergreenUI {
            $owner = Get-EwWorkbenchWindow
            $observed = @{ Error = '' }
            try {
                $owner.ThemeMode = [System.Windows.ThemeMode]::Dark
                Mock Get-EwNerdioShellAppVersion {
                    @('1.0', '2.0') | ForEach-Object { [PSCustomObject]@{ name = $_ } }
                }
                $plan = Get-EwNerdioShellAppVersionPrunePlan -Id '42'
                $plan | Add-Member -NotePropertyName Name -NotePropertyValue 'App'
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $preview = @($owner.OwnedWindows)[0]
                    $observed.Preview = $preview
                    try {
                        $button = $preview.FindName('ReviewNerdioPruneButton')
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                        $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke()
                    }
                    catch {
                        $observed.Error = $_.Exception.Message
                        $preview.Close()
                    }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $preview = $observed.Preview
                    if (-not $preview.IsVisible) { return }
                    $notice = @($preview.OwnedWindows)[0]
                    try {
                        $ok = $notice.FindName('ConfirmationYesButton')
                        $observed.Title = $notice.Title
                        $observed.Message = $notice.FindName('ConfirmationMessageText').Text
                        $observed.Theme = $notice.ThemeMode
                        $observed.OK = $ok.Content
                        $observed.Default = $ok.IsDefault -and $ok.IsCancel
                        $observed.OtherHidden = $notice.FindName('ConfirmationNoButton').Visibility -eq
                            [System.Windows.Visibility]::Collapsed
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($ok)
                        $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke()
                        $notice.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    }
                    catch { $observed.Error = $_.Exception.Message }
                    finally { if ($notice.IsVisible) { $notice.Close() } }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $observed.PreviewOpen = $observed.Preview.IsVisible
                    if ($observed.PreviewOpen) { $observed.Preview.Close() }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::SystemIdle)
                @(Show-EwWorkbenchNerdioPruneDialog -Owner $owner -Plans @($plan)) | Should -HaveCount 0
                $owner.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::SystemIdle)
                $observed.Error | Should -BeNullOrEmpty
                $observed.Title | Should -Be 'No Shell Apps selected'
                $observed.Message | Should -Match 'Select at least one Shell App'
                $observed.Theme | Should -Be $owner.ThemeMode
                $observed.OK | Should -Be 'OK'
                $observed.Default | Should -BeTrue
                $observed.OtherHidden | Should -BeTrue
                $observed.PreviewOpen | Should -BeTrue
            }
            finally { $owner.Close() }
        }
    }

    It 'requires explicit <Choice> confirmation for exact pruning versions' -ForEach @(
        @{ Choice = 'No'; Accepted = $false }
        @{ Choice = 'Yes'; Accepted = $true }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Choice = $Choice; Accepted = $Accepted } {
            $owner = Get-EwWorkbenchWindow
            $observed = @{ Choice = $Choice; Error = '' }
            try {
                $owner.ThemeMode = [System.Windows.ThemeMode]::Dark
                Mock Get-EwNerdioShellAppVersion {
                    @('1.0', '2.0') | ForEach-Object { [PSCustomObject]@{ name = $_ } }
                }
                $plan = Get-EwNerdioShellAppVersionPrunePlan -Id '42'
                $plan | Add-Member -NotePropertyName Name -NotePropertyValue 'App'
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $preview = @($owner.OwnedWindows)[0]
                    $observed.Preview = $preview
                    try {
                        $preview.FindName('NerdioPrunePlansPanel').Children[0].Child.IsChecked = $true
                        $button = $preview.FindName('ReviewNerdioPruneButton')
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                        $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke()
                    }
                    catch {
                        $observed.Error = $_.Exception.Message
                        $preview.Close()
                    }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $preview = $observed.Preview
                    if (-not $preview.IsVisible) { return }
                    $confirmation = @($preview.OwnedWindows)[0]
                    try {
                        $observed.Title = $confirmation.Title
                        $observed.Message = $confirmation.FindName('ConfirmationMessageText').Text
                        $observed.Theme = $confirmation.ThemeMode
                        $no = $confirmation.FindName('ConfirmationNoButton')
                        $observed.SafeDefault = $no.IsDefault -and $no.IsCancel
                        $button = $confirmation.FindName("Confirmation$($observed.Choice)Button")
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                        $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke()
                        $confirmation.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    }
                    catch { $observed.Error = $_.Exception.Message }
                    finally { if ($confirmation.IsVisible) { $confirmation.Close() } }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $observed.PreviewOpen = $observed.Preview.IsVisible
                    if ($observed.PreviewOpen) { $observed.Preview.Close() }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::SystemIdle)
                $selected = @(Show-EwWorkbenchNerdioPruneDialog -Owner $owner -Plans @($plan))
                $owner.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::SystemIdle)
                $observed.Error | Should -BeNullOrEmpty
                $observed.Title | Should -Be 'Confirm Nerdio version pruning'
                $observed.Message | Should -Match 'App: 1.0'
                $observed.Theme | Should -Be $owner.ThemeMode
                $observed.SafeDefault | Should -BeTrue
                $observed.PreviewOpen | Should -Be (-not $Accepted)
                $selected.Count | Should -Be ([int]$Accepted)
                if ($Accepted) { $selected[0].Remove | Should -Be @('1.0') }
            }
            finally { $owner.Close() }
        }
    }

    It 'keeps long pruning previews scrollable with the actions visible' -Skip:($env:GITHUB_ACTIONS -eq 'true') {
        InModuleScope EvergreenUI {
            $owner = Get-EwWorkbenchWindow
            $observed = @{}
            try {
                $owner.Width = $owner.MinWidth
                $owner.Height = $owner.MinHeight
                $owner.FontSize = 20
                $owner.ThemeMode = [System.Windows.ThemeMode]::Dark
                $plans = @(1..25 | ForEach-Object {
                        [PSCustomObject]@{
                            Id = [string]$_; Name = "Application $_ $([string]('long-name-' * 8))"
                            Eligible = $true; PublishedVersion = '2.0'; KeepVersions = 1
                            Keep = [string[]]@('2.0'); Remove = [string[]]@('1.0'); Message = ''
                            VersionDetails = @(
                                [PSCustomObject]@{ Name = '1.0'; SortKey = 1 }
                                [PSCustomObject]@{ Name = '2.0'; SortKey = 2 }
                            )
                        }
                    })
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $dialog = @($owner.OwnedWindows)[0]
                    try {
                        $dialog.UpdateLayout()
                        $scroll = $dialog.FindName('NerdioPruneScrollViewer')
                        $observed.ScrollableHeight = $scroll.ScrollableHeight
                        $scroll.ScrollToEnd()
                        $dialog.UpdateLayout()
                        $observed.Offset = $scroll.VerticalOffset
                        $observed.Plans = $dialog.FindName('NerdioPrunePlansPanel').Children.Count
                        $observed.FontSize = $dialog.FontSize
                        $observed.Height = $dialog.ActualHeight
                        $observed.MaxHeight = $dialog.MaxHeight
                        $button = $dialog.FindName('ReviewNerdioPruneButton')
                        $point = $button.TranslatePoint([System.Windows.Point]::new(0, 0), $dialog)
                        $observed.ButtonBottom = $point.Y + $button.ActualHeight
                    }
                    finally { $dialog.Close() }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                @(Show-EwWorkbenchNerdioPruneDialog -Owner $owner -Plans $plans) | Should -HaveCount 0
                $observed.ScrollableHeight | Should -BeGreaterThan 0
                $observed.Offset | Should -Be $observed.ScrollableHeight
                $observed.Plans | Should -Be 25
                $observed.FontSize | Should -Be 20
                $observed.Height | Should -BeLessOrEqual $observed.MaxHeight
                $observed.ButtonBottom | Should -BeLessOrEqual $observed.Height
            }
            finally { $owner.Close() }
        }
    }
}
