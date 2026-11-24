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
