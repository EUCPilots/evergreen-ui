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
