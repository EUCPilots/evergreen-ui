#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Microsoft 365 Intune publishing' {
    BeforeEach {
        $script:oldAppData = $env:APPDATA
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $root -ItemType Directory -Force
        $env:APPDATA = $root
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'App.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'package.intunewin') -Value 'package'
    }

    AfterEach { $env:APPDATA = $oldAppData }

    It 'matches normalized configuration GUIDs and rejects unverifiable app notes' {
        InModuleScope EvergreenUI {
            Mock Get-EwIntuneApp {
                [PSCustomObject]@{
                    IntuneAppId = 'app'; NotesValid = 'Yes'; NotesGuid = '{9FDDD581-F505-4760-9BB3-2365DB204B38}'
                    IsUpdateApp = $false; DisplayName = 'Office'; DisplayVersion = '1.0'
                }
            }
            $matches = @(Get-EwM365IntuneMatch -ConfigurationId '9fddd581-f505-4760-9bb3-2365db204b38')
            $matches.Count | Should -Be 1
            $matches[0].Id | Should -Be 'app'
            Mock Get-EwIntuneApp {
                [PSCustomObject]@{ IntuneAppId = 'app'; NotesValid = 'No'; NotesGuid = ''; IsUpdateApp = $false }
            }
            { Get-EwM365IntuneMatch -ConfigurationId '9fddd581-f505-4760-9bb3-2365db204b38' } |
                Should -Throw '*Matching cannot be verified*'
        }
    }

    It 'publishes a new app and creates the confirmed update relationship' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            Mock Assert-EwM365IntunePublishPlan {}
            Mock Assert-EwM365BuildPlan {}
            Mock New-EwPackage {
                [PSCustomObject]@{
                    Succeeded = $true; PackagePath = (Join-Path -Path $Root -ChildPath 'package.intunewin')
                    SourcePath = $Root; Version = '16.0.1234.1'; SetupFile = 'setup.exe'; Error = ''
                }
            }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-app'; Error = '' } }
            Mock Get-EwM365IntuneMatch { [PSCustomObject]@{ Id = 'old-app'; Name = 'Office'; Version = '1.0' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $true; Error = '' } }
            $build = [PSCustomObject]@{
                Provider = 'Intune'; ConfigurationId = '9fddd581-f505-4760-9bb3-2365db204b38'
                ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'
                TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{
                BuildPlan = $build; PreviousAppId = 'old-app'
                Matches = @([PSCustomObject]@{ Id = 'old-app'; Name = 'Office'; Version = '1.0' })
            }
            $result = Publish-EwM365IntuneApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $result.Succeeded | Should -BeTrue -Because $result.Error
            $result.IntuneAppId | Should -Be 'new-app'
            $result.SupersedenceStatus | Should -Be 'Completed'
            $result.RecoveryId | Should -BeNullOrEmpty
            $recovery = Invoke-EwM365IntuneRecoveryStore -Action Read
            @($recovery.Operations).Count | Should -Be 0
            Should -Invoke Set-EwIntuneSupersedence -Exactly 1 -ParameterFilter {
                $NewAppId -eq 'new-app' -and $PreviousAppId -eq 'old-app'
            }
        }
    }

    It 'persists uncertain creation and blocks another write until explicitly reviewed' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            Mock Assert-EwM365IntunePublishPlan {}
            Mock New-EwPackage {
                [PSCustomObject]@{
                    Succeeded = $true; PackagePath = (Join-Path -Path $Root -ChildPath 'package.intunewin')
                    SourcePath = $Root; Version = '16.0.1234.1'; SetupFile = 'setup.exe'; Error = ''
                }
            }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $false; IntuneAppId = 'new-app'; Error = 'response lost' } }
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            $build = [PSCustomObject]@{
                Provider = 'Intune'; ConfigurationId = '9fddd581-f505-4760-9bb3-2365db204b38'
                ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'
                TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{ BuildPlan = $build; PreviousAppId = ''; Matches = @() }
            $result = Publish-EwM365IntuneApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.IntuneAppId | Should -Be 'new-app'
            $record = @(Get-EwM365IntuneRecovery)[0]
            $record.AppId | Should -Be 'new-app'
            $record.Status | Should -Be 'Unknown'
            $oldModulePath = [Environment]::GetEnvironmentVariable('EW_TEST_MODULE_PATH')
            $env:EW_TEST_MODULE_PATH = (Get-Module -Name EvergreenUI).Path
            try {
                $restarted = & pwsh -NoProfile -Command 'Import-Module -Name $env:EW_TEST_MODULE_PATH -Force; & (Get-Module -Name EvergreenUI) { (Invoke-EwM365IntuneRecoveryStore -Action Read).Operations[0].AppId }'
                $LASTEXITCODE | Should -Be 0
                @($restarted)[-1] | Should -Be 'new-app'
            }
            finally { [Environment]::SetEnvironmentVariable('EW_TEST_MODULE_PATH', $oldModulePath) }
            $second = Publish-EwM365IntuneApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $second.Error | Should -Match 'explicit review'
            Should -Invoke Publish-EwIntuneApp -Exactly 1
            { Clear-EwM365IntuneRecovery -Id $record.Id -Reviewed:$false -Confirm:$false } |
                Should -Throw '*Review*'
            Clear-EwM365IntuneRecovery -Id $record.Id -Reviewed -Confirm:$false
            @(Get-EwM365IntuneRecovery).Count | Should -Be 0
        }
    }

    It 'preserves the new app and uncertain relationship separately' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            Mock Assert-EwM365IntunePublishPlan {}
            Mock Assert-EwM365BuildPlan {}
            Mock New-EwPackage {
                [PSCustomObject]@{
                    Succeeded = $true; PackagePath = (Join-Path -Path $Root -ChildPath 'package.intunewin')
                    SourcePath = $Root; Version = '16.0.1234.1'; SetupFile = 'setup.exe'; Error = ''
                }
            }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-app'; Error = '' } }
            Mock Get-EwM365IntuneMatch { [PSCustomObject]@{ Id = 'old-app'; Name = 'Office'; Version = '1.0' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $false; Error = 'response lost' } }
            $build = [PSCustomObject]@{
                Provider = 'Intune'; ConfigurationId = '9fddd581-f505-4760-9bb3-2365db204b38'
                ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'
                TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{
                BuildPlan = $build; PreviousAppId = 'old-app'
                Matches = @([PSCustomObject]@{ Id = 'old-app'; Name = 'Office'; Version = '1.0' })
            }
            $result = Publish-EwM365IntuneApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.IntuneAppId | Should -Be 'new-app'
            $result.SupersedenceStatus | Should -Be 'Unknown'
            $state = Invoke-EwM365IntuneRecoveryStore -Action Read
            $record = @($state.Operations)[0]
            $record.Stage | Should -Be 'Supersedence'
            $record.AppId | Should -Be 'new-app'
            $record.PreviousAppId | Should -Be 'old-app'
            Should -Invoke Set-EwIntuneSupersedence -Exactly 1
        }
    }

    It 'retains a review record when cancellation follows an Intune write' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            Mock Assert-EwM365IntunePublishPlan {}
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock New-EwPackage {
                [PSCustomObject]@{
                    Succeeded = $true; PackagePath = (Join-Path -Path $Root -ChildPath 'package.intunewin')
                    SourcePath = $Root; Version = '16.0.1234.1'; SetupFile = 'setup.exe'; Error = ''
                }
            }
            Mock Publish-EwIntuneApp {
                [PSCustomObject]@{
                    Succeeded = $false; IntuneAppId = 'new-app'; Error = 'Cancelled after upload'
                    Cancelled = $true; WriteStarted = $true
                }
            }
            $build = [PSCustomObject]@{
                Provider = 'Intune'; ConfigurationId = '9fddd581-f505-4760-9bb3-2365db204b38'
                ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'
                TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{ BuildPlan = $build; PreviousAppId = ''; Matches = @() }
            $result = Publish-EwM365IntuneApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $result.Status | Should -Be 'Cancelled'
            $result.IntuneAppId | Should -Be 'new-app'
            $record = @(Get-EwM365IntuneRecovery)[0]
            $record.AppId | Should -Be 'new-app'
            $record.Status | Should -Be 'Unknown'
        }
    }

    It 'does not acknowledge an operation owned by a running process' {
        InModuleScope EvergreenUI {
            $process = [System.Diagnostics.Process]::GetCurrentProcess()
            try { $ticks = $process.StartTime.ToUniversalTime().Ticks }
            finally { $process.Dispose() }
            $record = [ordered]@{
                Id = 'op'; TenantId = 'tenant'; ConfigurationId = 'config'; Status = 'InProgress'
                OwnerProcessId = $PID; OwnerStartTimeTicks = $ticks
            }
            $null = Invoke-EwM365IntuneRecoveryStore -Action Begin -Record $record
            { Invoke-EwM365IntuneRecoveryStore -Action Remove -Id op } | Should -Throw '*still running*'
            $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id op
        }
    }
}
