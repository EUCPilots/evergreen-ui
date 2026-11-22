#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'settings'
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
    $env:APPDATA = $script:originalAppData
}

Describe 'Microsoft 365 provider views' {
    It 'shares settings only when saved and defaults selections from configuration' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $intune = $state.M365Views.Intune
                $nerdio = $state.M365Views.Nerdio
                Mock Set-EwSetting {}
                $intune.PathBox.Text = 'C:\M365'
                $intune.CompanyBox.Text = 'Contoso'
                Should -Invoke Set-EwSetting -Exactly 0
                $intune.SaveButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                Should -Invoke Set-EwSetting -Exactly 4
                $nerdio.PathBox.Text | Should -Be 'C:\M365'
                $nerdio.CompanyBox.Text | Should -Be 'Contoso'
                $configuration = [PSCustomObject]@{
                    FileName = 'install.xml'; DisplayName = 'Office'; Channel = 'Current'; IsVdi = $true; Status = 'Valid'
                }
                $nerdio.ConfigurationCombo.ItemsSource = @($configuration)
                $nerdio.ConfigurationCombo.SelectedItem = $configuration
                $nerdio.ChannelCombo.SelectedItem | Should -Be 'Current'
                $nerdio.SessionCombo.SelectedItem | Should -Be 'Multi-session'
                $state.NerdioM365NameBox.Text | Should -Be 'Office'
                $nerdio.BuildPlan = [PSCustomObject]@{ OfficeVersion = '1.0' }
                $nerdio.CompanyBox.Text = 'Changed'
                $nerdio.BuildPlan | Should -BeNullOrEmpty
            }
            finally { $window.Close() }
        }
    }

    It 'enables Nerdio API-only sign-in without Azure or storage' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                $state.NerdioApiOnlyToggle.IsChecked = $true
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.ConnectNerdioButton.IsEnabled | Should -BeTrue
                $state.NmeClientSecretBox.Password = 'synthetic-secret'
                Invoke-EwWorkbenchNerdioAction -State $state -Action ApiConnect
                $state.NmeClientSecretBox.Password | Should -Be ''
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Nerdio ApiConnect' -and $ArgumentList[1].ApiOnly -eq $true -and
                    -not $ArgumentList[1].ContainsKey('StorageAccountName')
                }
            }
            finally { $window.Close() }
        }
    }

    It 'shows matches and separate versions in a confirmed Intune preview' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.M365ActiveProvider = 'Intune'
                $state.M365ActiveAction = 'PreviewPublish'
                $build = [PSCustomObject]@{
                    ConfigurationPath = 'C:\M365\install.xml'; ConfigurationId = 'id'; TenantId = 'tenant'
                    Channel = 'Current'; OfficeVersion = '16.0.1234.1'; ToolVersion = '16.0.5678.1'
                    CompanyName = 'Contoso'; ImportFor = 'Single session'
                }
                $publish = [PSCustomObject]@{
                    BuildPlan = $build; PreviousAppId = 'old'
                    Matches = @([PSCustomObject]@{ Name = 'Office'; Id = 'old'; Version = '1.0' })
                }
                $job = [PSCustomObject]@{
                    State = 'Completed'; TerminatingError = $null
                    Output = @([PSCustomObject]@{ Build = $build; Publish = $publish })
                }
                Invoke-EwWorkbenchM365JobResult -State $state -Job $job
                $state.IntuneM365PreviewText.Text | Should -Match '16.0.1234.1'
                $state.IntuneM365PreviewText.Text | Should -Match '16.0.5678.1'
                $state.IntuneM365PreviewText.Text | Should -Match 'Office \[old\]'
                $state.IntuneM365PreviewText.Text | Should -Match 'not uninstall'
                $state.M365Views.Intune.PublishPlan | Should -Not -BeNullOrEmpty
            }
            finally { $window.Close() }
        }
    }

    It 'does not start publishing when confirmation is declined' {
        $xmlPath = Join-Path -Path $TestDrive -ChildPath 'confirm.xml'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $TestDrive } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.Settings.PackageOutputPath = $WorkingPath
                $state.M365Views.Intune.PublishPlan = [PSCustomObject]@{
                    BuildPlan = [PSCustomObject]@{ ConfigurationPath = $ConfigurationPath }
                }
                $state.IntuneM365PreviewText.Text = 'Confirmed preview'
                Mock Confirm-EwWorkbenchM365Action { $false }
                Mock Start-EwJob {}
                Invoke-EwWorkbenchM365Action -State $state -Provider Intune -Action Publish
                $state.IntuneM365ResultText.Text | Should -BeNullOrEmpty
                Should -Invoke Confirm-EwWorkbenchM365Action -Exactly 1 -ParameterFilter {
                    $Title -eq 'Confirm Microsoft 365 publishing' -and $Message -match 'Confirmed preview'
                }
                Should -Invoke Start-EwJob -Exactly 0
                $state.M365Cancellation | Should -BeNullOrEmpty
            }
            finally { $window.Close() }
        }
    }

    It 'requires replacement approval before starting a build' {
        $xmlPath = Join-Path -Path $TestDrive -ChildPath 'replacement.xml'
        $working = Join-Path -Path $TestDrive -ChildPath 'replacement-output'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $working } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.Settings.PackageOutputPath = $WorkingPath
                $state.M365Views.Intune.BuildPlan = [PSCustomObject]@{ ConfigurationPath = $ConfigurationPath }
                $configuration = Read-EwM365Configuration -Path $ConfigurationPath
                $name = [regex]::Replace($configuration.DisplayName, '[\\/:*?"<>|]', '_').Trim('_')
                $output = Join-Path -Path $WorkingPath -ChildPath "$name\Output"
                $null = New-Item -Path $output -ItemType Directory -Force
                $existing = Join-Path -Path $output -ChildPath 'existing.intunewin'
                Set-Content -LiteralPath $existing -Value 'previous package'
                Mock Confirm-EwWorkbenchM365Action { $false }
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                Invoke-EwWorkbenchM365Action -State $state -Provider Intune -Action Build
                Should -Invoke Start-EwJob -Exactly 0
                (Get-Content -LiteralPath $existing -Raw).Trim() | Should -Be 'previous package'

                Mock Confirm-EwWorkbenchM365Action { $true }
                Invoke-EwWorkbenchM365Action -State $state -Provider Intune -Action Build
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Microsoft 365 Intune Build' -and $ArgumentList[4] -eq $true
                }
            }
            finally {
                if ($null -ne $state.M365Cancellation) { $state.M365Cancellation.Dispose() }
                $window.Close()
            }
        }
    }

    It 'routes completed publishing results through the job monitor' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $jobId = [guid]::NewGuid()
                $state.ActiveJobId = $jobId
                $state.ActiveJobKind = 'M365'
                $state.M365ActiveProvider = 'Intune'
                $state.M365ActiveAction = 'Publish'
                $state.M365Views.Intune.PublishPlan = [PSCustomObject]@{ Name = 'old preview' }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $jobId; State = 'Completed'; TerminatingError = $null
                        Progress = @(); Information = @(); Errors = @()
                        Output = @([PSCustomObject]@{
                            Succeeded = $false; Status = 'Unknown'; IntuneAppId = 'new-app'
                            PreviousAppId = 'old-app'; SupersedenceStatus = 'Unknown'
                            RecoveryId = 'recovery-id'; Error = 'Review the provider outcome.'
                        })
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneM365ResultText.Text | Should -Match 'new-app'
                $state.IntuneM365ResultText.Text | Should -Match 'recovery-id'
                $state.M365Views.Intune.PublishPlan | Should -BeNullOrEmpty
                $state.ActiveJobId | Should -BeNullOrEmpty
                Should -Invoke Remove-EwJob -Exactly 1
            }
            finally { $window.Close() }
        }
    }
}
