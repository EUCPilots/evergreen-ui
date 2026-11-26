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
    It 'keeps the <Title> confirmation message and No default' -ForEach @(
        @{ Title = 'Replace package' }
        @{ Title = 'Confirm Microsoft 365 publishing' }
        @{ Title = 'Review Intune outcome' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Title = $Title } {
            $expectedTitle = $Title
            $expectedMessage = "Tenant: example`nA package may be replaced."
            Mock Confirm-EwWorkbenchAction { $false }
            Confirm-EwWorkbenchM365Action -Window ([object]::new()) -Title $expectedTitle -Message $expectedMessage |
                Should -BeFalse
            Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                $Title -eq $expectedTitle -and $Message -eq $expectedMessage -and -not $DefaultYes
            }
        }
    }

    It 'uses native label colours in the <Provider> form starting in <InitialTheme> mode' -ForEach @(
        @{ Provider = 'Intune'; InitialTheme = 'Dark' }
        @{ Provider = 'Nerdio'; InitialTheme = 'Dark' }
        @{ Provider = 'Intune'; InitialTheme = 'Light' }
        @{ Provider = 'Nerdio'; InitialTheme = 'Light' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Provider = $Provider; InitialTheme = $InitialTheme } {
            function Get-TestFormLabel {
                param([System.Windows.DependencyObject]$Parent)

                if ($Parent -is [System.Windows.Controls.Label]) { return $Parent }
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Parent)) {
                    if ($child -is [System.Windows.DependencyObject]) { Get-TestFormLabel -Parent $child }
                }
            }

            function Find-TestVisualText {
                param([System.Windows.DependencyObject]$Parent)

                for ($index = 0; $index -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent); $index++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $index)
                    if ($child -is [System.Windows.Controls.TextBlock]) { return $child }
                    $match = Find-TestVisualText -Parent $child
                    if ($null -ne $match) { return $match }
                }
            }

            $window = Get-EwWorkbenchWindow
            try {
                $window.ThemeMode = [System.Windows.ThemeMode]::$InitialTheme
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                foreach ($name in 'AppsPanel', 'IntunePanel', 'NerdioPanel') {
                    $window.FindName($name).Visibility = 'Collapsed'
                }
                $page = $window.FindName("${Provider}Panel")
                $page.Visibility = 'Visible'
                $tabs = $page.Children[0]
                $tabs.SelectedItem = $tabs.Items |
                    Where-Object { $_.Header -eq 'Microsoft 365 Apps' } |
                    Select-Object -First 1
                $form = $window.FindName("${Provider}M365Form")
                $labels = @(Get-TestFormLabel -Parent $form)
                $labels.Count | Should -BeGreaterThan 0

                $reference = [System.Windows.Controls.Label]::new()
                $reference.Content = 'Native label'
                $null = $form.Children[0].Content.Children.Add($reference)
                $modes = if ($InitialTheme -eq 'Dark') {
                    @('Dark', 'Light', 'Dark', 'System')
                }
                else {
                    @('Light', 'Dark', 'Light', 'System')
                }
                foreach ($mode in $modes) {
                    $window.ThemeMode = [System.Windows.ThemeMode]::$mode
                    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    $window.UpdateLayout()
                    $form.IsVisible | Should -BeTrue
                    $referenceText = Find-TestVisualText -Parent $reference
                    $referenceText | Should -Not -BeNullOrEmpty
                    $expected = if ([System.Windows.SystemParameters]::HighContrast) {
                        $referenceText.Foreground.Color
                    }
                    else {
                        $window.TryFindResource('TextFillColorPrimaryBrush').Color
                    }
                    foreach ($label in $labels) {
                        $text = Find-TestVisualText -Parent $label
                        $text | Should -Not -BeNullOrEmpty
                        $text.Foreground.Color | Should -Be $expected -Because (
                            "'$($label.Content)' on the $Provider Microsoft 365 form should follow the $mode theme"
                        )
                    }

                    $labels[0].IsEnabled = $false
                    $reference.IsEnabled = $false
                    $window.UpdateLayout()
                    $disabledText = Find-TestVisualText -Parent $labels[0]
                    $disabledReference = Find-TestVisualText -Parent $reference
                    $disabledText.Foreground.Color | Should -Be $disabledReference.Foreground.Color
                    $labels[0].IsEnabled = $true
                    $reference.IsEnabled = $true
                }
            }
            finally { $window.Close() }
        }
    }

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

    It 'allows Nerdio API sign-in independently of Azure authentication' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid() } }
                Invoke-EwWorkbenchNerdioBusyState -State $state
                $state.ConnectNerdioButton.IsEnabled | Should -BeTrue
                $state.NerdioApiOnlyToggle.IsChecked | Should -BeFalse
                $state.NmeClientSecretBox.Password = 'synthetic-secret'
                Invoke-EwWorkbenchNerdioAction -State $state -Action ApiConnect
                $state.NmeClientSecretBox.Password | Should -Be ''
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Nerdio ApiConnect' -and $ArgumentList[1].ApiOnly -eq $true -and
                    -not $ArgumentList[1].ContainsKey('StorageAccountName')
                }

                $state.ActiveJobId = $null
                $destination = [PSCustomObject]@{ ApiOnly = $true; NmeHost = 'nme.test' }
                $state.NerdioDestination = $destination
                $script:ewNerdioSession.Context = [PSCustomObject]@{ ApiOnly = $true; NmeHost = 'nme.test' }
                Invoke-EwWorkbenchNerdioAction -State $state -Action AzureConnect
                $state.NerdioDestination | Should -Be $destination
                $script:ewNerdioSession.Context.ApiOnly | Should -BeTrue
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

    It 'does not start <Provider> publishing when confirmation is declined' -ForEach @(
        @{ Provider = 'Intune' }
        @{ Provider = 'Nerdio' }
    ) {
        $xmlPath = Join-Path -Path $TestDrive -ChildPath "confirm-$Provider.xml"
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $TestDrive; Provider = $Provider } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.Settings.PackageOutputPath = $WorkingPath
                $view = $state.M365Views[$Provider]
                $view.PublishPlan = [PSCustomObject]@{
                    BuildPlan = [PSCustomObject]@{ ConfigurationPath = $ConfigurationPath }
                }
                $view.PreviewText.Text = 'Confirmed preview'
                Mock Confirm-EwWorkbenchM365Action { $false }
                Mock Start-EwJob {}
                Invoke-EwWorkbenchM365Action -State $state -Provider $Provider -Action Publish
                $view.ResultText.Text | Should -BeNullOrEmpty
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
