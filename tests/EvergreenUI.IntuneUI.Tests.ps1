#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'appdata'
    $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    $env:APPDATA = $script:originalAppData
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Intune Publish view' {
    It 'preserves batch confirmation details for new and update apps' {
        InModuleScope EvergreenUI {
            $selection = @(
                [PSCustomObject]@{ DefinitionName = 'New & Co'; ImportAsUpdate = $false; IntuneAppId = '' }
                [PSCustomObject]@{ DefinitionName = 'Existing'; ImportAsUpdate = $true; IntuneAppId = 'previous-id' }
            )
            Mock Confirm-EwWorkbenchAction { $true }
            Confirm-EwWorkbenchIntuneBatch -Window ([object]::new()) -Selection $selection -TenantId 'tenant-id' |
                Should -BeTrue
            Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                $Title -eq 'Confirm Intune publishing' -and $DefaultYes -and
                $Message -match 'Tenant: tenant-id' -and
                $Message -match 'New & Co: Definition assignments; new app' -and
                $Message -match 'Existing: UPDATE APP: required for All Devices; supersedes previous-id' -and
                $Message -match 'Definition and Source\\Install.json files may be updated on disk'
            }
        }
    }

    It 'renders the confirmation in <Mode> mode with the <Default> default' -ForEach @(
        @{ Mode = 'Light'; Default = 'Yes' }
        @{ Mode = 'Dark'; Default = 'No' }
        @{ Mode = 'System'; Default = 'Yes' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; Default = $Default } {
            $owner = Get-EwWorkbenchWindow
            $dialog = $null
            try {
                $owner.ThemeMode = [System.Windows.ThemeMode]::$Mode
                $owner.Show()
                $message = "Tenant: tenant & co`n`nAn <application> will change."
                $dialog = New-EwWorkbenchConfirmationDialog -Owner $owner -Title 'Confirm action' `
                    -Message $message -DefaultYes ($Default -eq 'Yes')
                $dialog.Show()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $dialog.UpdateLayout()

                $dialog.Owner | Should -Be $owner
                $dialog.ThemeMode | Should -Be $owner.ThemeMode
                $dialog.WindowStartupLocation | Should -Be ([System.Windows.WindowStartupLocation]::CenterOwner)
                $dialog.ShowInTaskbar | Should -BeFalse
                $dialog.TryFindResource('ApplicationBackgroundBrush').Color |
                    Should -Be $owner.TryFindResource('ApplicationBackgroundBrush').Color
                $dialog.FindName('ConfirmationHeadingText').Text | Should -Be 'Confirm action'
                $dialog.FindName('ConfirmationMessageText').Text | Should -Be $message
                $dialog.FindName('ConfirmationYesButton').IsDefault | Should -Be ($Default -eq 'Yes')
                $dialog.FindName('ConfirmationNoButton').IsDefault | Should -Be ($Default -eq 'No')
                $dialog.FindName('ConfirmationNoButton').IsCancel | Should -BeTrue
                $dialog.FindName("Confirmation${Default}Button").Style |
                    Should -Be $dialog.TryFindResource('AccentButtonStyle')
            }
            finally {
                if ($null -ne $dialog) { $dialog.Close() }
                $owner.Close()
            }
        }
    }

    It 'keeps long confirmation details scrollable and actions visible' -Skip:($env:GITHUB_ACTIONS -eq 'true') {
        InModuleScope EvergreenUI {
            $owner = Get-EwWorkbenchWindow
            $dialog = $null
            try {
                $owner.Height = 660
                $owner.FontSize = 20
                $owner.Show()
                $message = ((1..80 | ForEach-Object { "Application $_`: $([string]('long-name' * 12))" }) -join "`n")
                $dialog = New-EwWorkbenchConfirmationDialog -Owner $owner -Title 'Confirm action' `
                    -Message $message -DefaultYes $true
                $dialog.Show()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $dialog.UpdateLayout()

                $dialog.FontSize | Should -Be 20
                $dialog.FindName('ConfirmationMessageText').Text | Should -Be $message
                $dialog.FindName('ConfirmationMessageText').TextWrapping | Should -Be ([System.Windows.TextWrapping]::Wrap)
                $scroll = $dialog.FindName('ConfirmationDetailsScrollViewer')
                $scroll.ScrollableHeight | Should -BeGreaterThan 0
                $scroll.ScrollToEnd()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $scroll.VerticalOffset | Should -Be $scroll.ScrollableHeight
                $yes = $dialog.FindName('ConfirmationYesButton')
                $position = $yes.TranslatePoint([System.Windows.Point]::new(0, 0), $dialog)
                ($position.Y + $yes.ActualHeight) | Should -BeLessOrEqual $dialog.ActualHeight
            }
            finally {
                if ($null -ne $dialog) { $dialog.Close() }
                $owner.Close()
            }
        }
    }

    It 'returns <Accepted> for <Action> with Yes default <DefaultYes>' -ForEach @(
        @{ Action = 'Yes'; DefaultYes = $true; Accepted = $true }
        @{ Action = 'No'; DefaultYes = $true; Accepted = $false }
        @{ Action = 'Close'; DefaultYes = $true; Accepted = $false }
        @{ Action = 'Return'; DefaultYes = $true; Accepted = $true }
        @{ Action = 'Return'; DefaultYes = $false; Accepted = $false }
        @{ Action = 'Escape'; DefaultYes = $true; Accepted = $false }
    ) {
        if ($env:GITHUB_ACTIONS -eq 'true' -and $Action -in 'Return', 'Escape') {
            Set-ItResult -Skipped -Because 'Keyboard focus requires an interactive desktop.'
            return
        }
        InModuleScope EvergreenUI -Parameters @{ Action = $Action; DefaultYes = $DefaultYes; Accepted = $Accepted } {
            $owner = Get-EwWorkbenchWindow
            $observed = @{ Action = $Action; DefaultYes = $DefaultYes; InitiallyFocused = $false; VisibleAfter = $null }
            try {
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $dialog = @($owner.OwnedWindows)[0]
                    $default = if ($observed.DefaultYes) { 'Yes' } else { 'No' }
                    $observed.InitiallyFocused = $dialog.FindName("Confirmation${default}Button").IsKeyboardFocused
                    if ($observed.Action -in 'Return', 'Escape') {
                        $key = [System.Windows.Input.Key]::Parse([System.Windows.Input.Key], $observed.Action)
                        $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                            [System.Windows.Input.Keyboard]::PrimaryDevice,
                            [System.Windows.PresentationSource]::FromVisual($dialog), 0, $key
                        )
                        $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                        $null = [System.Windows.Input.InputManager]::Current.ProcessInput($keyArgs)
                    }
                    elseif ($observed.Action -in 'Yes', 'No') {
                        $button = $dialog.FindName("Confirmation$($observed.Action)Button")
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                        $provider = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
                        $provider.Invoke()
                        $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    }
                    else { $dialog.Close() }
                    $observed.VisibleAfter = $dialog.IsVisible
                    if ($dialog.IsVisible) { $dialog.Close() }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $result = Confirm-EwWorkbenchAction -Window $owner -Title 'Confirm action' `
                    -Message 'Proceed?' -DefaultYes $DefaultYes
                $result | Should -Be $Accepted
                if ($env:GITHUB_ACTIONS -ne 'true') { $observed.InitiallyFocused | Should -BeTrue }
                $observed.VisibleAfter | Should -BeFalse
            }
            finally { $owner.Close() }
        }
    }

    It 'requires approval before retrying Intune supersedence' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $item = [PSCustomObject]@{
                    Status = 'Supersedence failed'; TenantId = 'tenant'
                    IntuneAppId = 'new-id'; PreviousAppId = 'old-id'
                }
                $state.IntuneResults.Add($item)
                $state.IntunePublishResultsListView.SelectedItem = $item
                Mock Confirm-EwWorkbenchAction { $false }
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.RetryIntuneSupersedenceButton.RaiseEvent($click)
                Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                    $DefaultYes -and $Title -eq 'Confirm supersedence retry' -and
                    $Message -match 'Tenant: tenant' -and $Message -match 'New app: new-id' -and
                    $Message -match 'Previous app: old-id'
                }
                Should -Invoke Start-EwJob -Exactly 0
                Mock Confirm-EwWorkbenchAction { $true }
                $state.RetryIntuneSupersedenceButton.RaiseEvent($click)
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Retry Intune supersedence' -and
                    $ArgumentList[0] -eq 'new-id' -and $ArgumentList[1] -eq 'old-id' -and $ArgumentList[2] -eq 'tenant'
                }
            }
            finally { $window.Close() }
        }
    }

    It 'toggles the connection action only after successful sign-in and sign-out' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantIdBox.Text = 'requested-tenant'
                $state.UseIntuneDeviceCodeToggle.IsChecked = $true
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                Mock Remove-EwJob {}

                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.ConnectIntuneButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntuneConnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeFalse
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Connect to Intune' -and
                    $ArgumentList[0] -eq 'requested-tenant' -and $ArgumentList[1] -eq $true
                }

                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Succeeded = $true; AccountId = 'person@example.com'; TenantId = 'connected-tenant'
                            })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -Be 'connected-tenant'
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'person@example.com'
                $state.ConnectIntuneButton.Content | Should -Be 'Disconnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeTrue
                $state.CompareIntuneButton.IsEnabled | Should -BeTrue

                $state.ConnectIntuneButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntuneDisconnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeFalse
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Disconnect from Intune' }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $false; Error = 'Disconnect failed' })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -Be 'connected-tenant'
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'person@example.com'
                $state.ConnectIntuneButton.Content | Should -Be 'Disconnect'

                $state.ConnectIntuneButton.RaiseEvent($click)
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $true; Error = '' })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -BeNullOrEmpty
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'Not connected'
                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.CompareIntuneButton.IsEnabled | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps the connection action disconnected after sign-in fails' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntuneConnect'
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $false; Error = 'Sign-in failed' })
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -BeNullOrEmpty
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'Not connected'
                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeTrue
                $state.CompareIntuneButton.IsEnabled | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'starts a confirmed batch and requests cooperative cancellation' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntunePanel.Visibility.ToString() | Should -Be 'Visible'
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonRoot = 'C:\Definitions'
                $state.Settings.IntuneDefinitionsPath = 'C:\Definitions'
                $state.Settings.PackageOutputPath = 'C:\Packages'
                $row = [PSCustomObject]@{
                    DefinitionName = 'App'; DefinitionPath = 'C:\Definitions\App\App.json'
                    MatchStatus = 'Matched (current)'; IntuneAppId = 'old-id'; ImportAsUpdate = $true
                }
                $state.IntuneComparisonListView.ItemsSource = @($row)
                $state.IntuneComparisonListView.SelectedItem = $row
                Mock Confirm-EwWorkbenchIntuneBatch { $true }
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.PublishSelectedIntuneButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntunePublish'
                $state.CancelIntuneBatchButton.IsEnabled | Should -BeTrue
                Should -Invoke Confirm-EwWorkbenchIntuneBatch -Exactly 1 -ParameterFilter {
                    $TenantId -eq 'tenant' -and $Selection[0].ImportAsUpdate
                }
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $ArgumentList[0] -eq 'C:\Definitions' -and $ArgumentList[2] -eq 'C:\Packages' -and
                    $ArgumentList[3] -eq 'tenant'
                }
                $state.CancelIntuneBatchButton.RaiseEvent($click)
                $state.IntuneCancellation.IsCancellationRequested | Should -BeTrue
            }
            finally {
                if ($null -ne $state.IntuneCancellation) { $state.IntuneCancellation.Dispose() }
                $window.Close()
            }
        }
    }

    It 'preserves partial results and refreshes the comparison after a batch' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntunePublish'
                $state.IntuneCancellation = [System.Threading.CancellationTokenSource]::new()
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Name = 'App'; Status = 'Supersedence failed'; Succeeded = $false
                                IntuneAppId = 'new-id'; PreviousAppId = 'old-id'
                                ChangedPaths = @(); Error = 'link failed'
                            })
                    }
                }
                Mock Remove-EwJob {}
                Mock Invoke-EwWorkbenchIntuneComparison {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneResults.Count | Should -Be 1
                $state.IntuneResults[0].TenantId | Should -Be 'tenant'
                $state.IntuneResults[0].IntuneAppId | Should -Be 'new-id'
                $state.IntunePublishResultsListView.SelectedItem = $state.IntuneResults[0]
                $state.RetryIntuneSupersedenceButton.IsEnabled | Should -BeTrue
                Should -Invoke Invoke-EwWorkbenchIntuneComparison -Exactly 1
            }
            finally {
                $window.Close()
            }
        }
    }
}
