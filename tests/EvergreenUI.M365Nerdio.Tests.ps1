#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Microsoft 365 Nerdio publishing' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path (Join-Path -Path $root -ChildPath 'shell-app') -ItemType Directory -Force
        $script:file = Join-Path -Path $root -ChildPath 'package.zip'
        Set-Content -LiteralPath $file -Value 'package'
    }

    It 'reports completed when a created Office app can be identified after a completed response without an app ID' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $definition = [PSCustomObject]@{
                name = 'Office'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = ''; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Assert-EwNerdioDestination {}
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = $File; Error = '' } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ job = [PSCustomObject]@{ id = '16830'; status = 'Completed' } } }
            Mock Get-EwNerdioShellApp { [PSCustomObject]@{ Id = 'app-42'; Name = 'Office'; Publisher = 'Microsoft' } }
            Mock Get-EwNerdioShellAppVersion { [PSCustomObject]@{ name = '16.0.20625.20142' } }
            $build = [PSCustomObject]@{
                ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root; OfficeVersion = '16.0.20625.20142'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'; TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = ''; Destination = [PSCustomObject]@{} }
            $result = Publish-EwM365NerdioApp -Plan $plan -WorkingPath $Root -Confirm:$false

            $result.Error | Should -Not -Be "Nerdio returned 'Completed'; inspect the operation before retrying."
            $result.Status | Should -Be 'Completed'
            $result.Succeeded | Should -BeTrue
            $result.AppId | Should -Be 'app-42'
            $result.JobId | Should -Be '16830'
            Should -Invoke Invoke-EwNerdioRecoveryStore -Exactly 1 -ParameterFilter { $null -ne $UpsertOffer }
        }
    }

    It 'keeps an ID-less completed result unresolved when <Scenario>' -ForEach @(
        @{ Scenario = 'the app is not yet visible'; Apps = 0; Versions = 1 }
        @{ Scenario = 'the app lookup fails'; Apps = 0; Versions = 1 }
        @{ Scenario = 'multiple apps match'; Apps = 2; Versions = 1 }
        @{ Scenario = 'the publisher differs'; Apps = 1; Versions = 1 }
        @{ Scenario = 'the app ID is duplicated'; Apps = 1; Versions = 1 }
        @{ Scenario = 'the version is not yet visible'; Apps = 1; Versions = 0 }
        @{ Scenario = 'the version is duplicated'; Apps = 1; Versions = 2 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file; Apps = $Apps; Versions = $Versions; Scenario = $Scenario } {
            $definition = [PSCustomObject]@{
                name = 'Office'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = ''; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Assert-EwNerdioDestination {}
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ job = [PSCustomObject]@{ id = '16830'; status = 'Completed' } } }
            Mock Get-EwNerdioShellApp {
                if ($Scenario -eq 'the app lookup fails') { throw 'App lookup failed' }
                for ($index = 0; $index -lt $Apps; $index++) {
                    $publisher = if ($Scenario -eq 'the publisher differs') { 'Other' } else { 'Microsoft' }
                    [PSCustomObject]@{ Id = "app-$index"; Name = 'Office'; Publisher = $publisher }
                }
                if ($Scenario -eq 'the app ID is duplicated') { [PSCustomObject]@{ Id = 'app-0'; Name = 'Other'; Publisher = 'Microsoft' } }
            }
            Mock Get-EwNerdioShellAppVersion {
                for ($index = 0; $index -lt $Versions; $index++) {
                    [PSCustomObject]@{ name = '16.0.20625.20142' }
                }
            }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.20625.20142' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = ''; Destination = [PSCustomObject]@{} }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath (Join-Path -Path $Root -ChildPath 'shell-app') -PackagePath $File `
                -Version $build.OfficeVersion -M365Plan $plan -M365PackageHash $hash -Confirm:$false

            $result.Status | Should -Be 'Unknown'
            $result.Succeeded | Should -BeFalse
            $result.AppId | Should -BeNullOrEmpty
            $result.JobId | Should -Be '16830'
            if ($Scenario -eq 'the app lookup fails') { $result.Error | Should -Match 'App lookup failed' }
            else { $result.Error | Should -Match 'could not be verified' }
            Should -Invoke Invoke-EwNerdioRecoveryStore -Exactly 0 -ParameterFilter { $null -ne $UpsertOffer }
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1
        }
    }

    It 'retains an unknown outcome if the destination changes while resolving the created app' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $definition = [PSCustomObject]@{
                name = 'Office'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = ''; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Assert-EwM365NerdioPublishPlan {}
            $checks = @{ Count = 0 }
            Mock Assert-EwNerdioDestination {
                $checks.Count++
                if ($checks.Count -eq 2) { throw 'Destination changed' }
            }
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ job = [PSCustomObject]@{ id = '16830'; status = 'Completed' } } }
            Mock Get-EwNerdioShellApp { [PSCustomObject]@{ Id = 'app-42'; Name = 'Office'; Publisher = 'Microsoft' } }
            Mock Get-EwNerdioShellAppVersion { [PSCustomObject]@{ name = '16.0.20625.20142' } }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.20625.20142' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = ''; Destination = [PSCustomObject]@{} }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath (Join-Path -Path $Root -ChildPath 'shell-app') -PackagePath $File `
                -Version $build.OfficeVersion -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.AppId | Should -BeNullOrEmpty
            $result.Error | Should -Match 'Destination changed'
            Should -Invoke Invoke-EwNerdioRecoveryStore -Exactly 0 -ParameterFilter { $null -ne $UpsertOffer }
        }
    }

    It 'requires unique targets and attestation for an existing Office version' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root } {
            Mock Assert-EwM365BuildPlan {}
            Mock Assert-EwNerdioDestination {}
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwAzureStorageContainer { 'container' }
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{
                    SessionId = 'session'; TenantId = 'tenant'; SubscriptionId = 'subscription'
                    NmeHost = 'nme.test'; ResourceGroupName = 'rg'; StorageAccountName = 'storage'
                    ContainerName = 'container'; ApiOnly = $false
                }
            }
            Mock Get-EwNerdioShellApp {
                [PSCustomObject]@{ Id = 'app'; Name = 'Office'; Publisher = 'Microsoft' }
            }
            Mock Get-EwNerdioShellAppVersion { [PSCustomObject]@{ name = '16.0.1234.1' } }
            $build = [PSCustomObject]@{
                Provider = 'Nerdio'; ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1'
            }
            { Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation Create -Name 'Office' } |
                Should -Throw '*already exists*'
            { Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation 'Add version' -Name 'Office' -ShellAppId app } |
                Should -Throw '*Attest*'
            $plan = Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation 'Add version' `
                -Name 'Office' -ShellAppId app -SameVersionAttested
            $plan.Target.Id | Should -Be 'app'
            $plan.SameVersionAttested | Should -BeTrue
            Mock Get-EwNerdioShellAppVersion { [PSCustomObject]@{ name = '16.0.9999.1' } }
            { Assert-EwM365NerdioPublishPlan -Plan $plan } | Should -Throw '*versions changed*'
            Mock Get-EwAzureStorageContainer { 'other' }
            { Assert-EwM365NerdioPublishPlan -Plan $plan } | Should -Throw '*container*'
        }
    }

    It 'stops after building if the target changes and honours cancellation before building' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $build = [PSCustomObject]@{
                Provider = 'Nerdio'; ConfigurationPath = 'C:\fixture\install.xml'; ConfigurationRoot = $Root
                OfficeVersion = '16.0.1234.1'; Channel = 'Current'; CompanyName = 'Contoso'
                ImportFor = 'Single session'; TenantId = 'tenant'; AppJsonTemplatePath = 'C:\fixture\app.json'
            }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = '' }
            $checks = @{ Count = 0 }
            Mock Assert-EwM365NerdioPublishPlan {
                $checks.Count++
                if ($checks.Count -eq 2) { throw 'Target changed' }
            }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = $File; Error = '' } }
            Mock Publish-EwNerdioApp { throw 'Publishing must not start.' }
            $result = Publish-EwM365NerdioApp -Plan $plan -WorkingPath $Root -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.PackagePath | Should -Be $File
            $result.Error | Should -Match 'Target changed'
            Should -Invoke Publish-EwNerdioApp -Exactly 0
            $cancel = [System.Threading.CancellationTokenSource]::new()
            $cancel.Cancel()
            $result = Publish-EwM365NerdioApp -Plan $plan -WorkingPath $Root `
                -CancellationToken $cancel.Token -Confirm:$false
            $result.Status | Should -Be 'Cancelled'
            Should -Invoke New-EwPackage -Exactly 1
            $cancel.Dispose()
        }
    }

    It 'rechecks after upload and preserves the blob when the target changes' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $folder = Join-Path -Path $Root -ChildPath 'shell-app'
            $definition = [PSCustomObject]@{
                name = 'original'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = 'old'; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest {}
            $checks = @{ Count = 0 }
            Mock Assert-EwM365NerdioPublishPlan {
                $checks.Count++
                if ($checks.Count -eq 3) { throw 'Target changed after upload' }
            }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = '' }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath $folder -PackagePath $File -Version '16.0.1234.1' `
                -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Status | Should -Be 'Failed'
            $result.BlobName | Should -Be 'blob'
            $result.Error | Should -Match 'Target changed'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 0
        }
    }

    It 'finishes an upload but does not publish after cancellation' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $folder = Join-Path -Path $Root -ChildPath 'shell-app'
            $definition = [PSCustomObject]@{
                name = 'original'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = 'old'; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioApiRequest {}
            $script:cancelAfterUpload = [System.Threading.CancellationTokenSource]::new()
            try {
                Mock Invoke-EwNerdioBlobUpload {
                    $script:cancelAfterUpload.Cancel()
                    [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file?sig=secret'; Sha256 = 'hash' }
                }
                $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1' }
                $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = '' }
                $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
                $result = Publish-EwNerdioApp -DefinitionPath $folder -PackagePath $File -Version '16.0.1234.1' `
                    -M365Plan $plan -M365PackageHash $hash -CancellationToken $script:cancelAfterUpload.Token -Confirm:$false
                $result.Status | Should -Be 'Cancelled'
                $result.BlobName | Should -Be 'blob'
                Should -Invoke Invoke-EwNerdioApiRequest -Exactly 0
                Should -Invoke Invoke-EwNerdioRecoveryStore -Exactly 1 -ParameterFilter { $RemoveOperationId }
            }
            finally { $script:cancelAfterUpload.Dispose() }
        }
    }

    It 'reports the Nerdio validation detail when an add-version request returns HTTP 400' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $folder = Join-Path -Path $Root -ChildPath 'shell-app'
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwNerdioPublishContent { [PSCustomObject]@{} }
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioBlobUpload {
                [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file?sig=secret'; Sha256 = 'hash' }
            }
            Mock Invoke-RestMethod {
                $exception = [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).')
                $record = [System.Management.Automation.ErrorRecord]::new($exception, 'HttpResponseException', 'InvalidOperation', $null)
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"message":"The version name is invalid."}')
                throw $record
            }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Add version'; ShellAppId = '68' }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath $folder -PackagePath $File -Version $build.OfficeVersion `
                -ShellAppId '68' -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.AppId | Should -Be '68'
            $result.Error | Should -Match 'The version name is invalid'
            $result.Error | Should -Not -Match 'sig=secret|token'
            Should -Invoke Invoke-RestMethod -Exactly 1
        }
    }

    It 'does not persist unsafe provider error details' -ForEach @(
        @{ Detail = '{"message":"Bad URL https://example.test/a?sig=secret"}' }
        @{ Detail = '{"message":"API key is sensitive"}' }
        @{ Detail = '{"message":"Bad abcd"}' }
        @{ Detail = '{"message":"unexpected abcdefghijklmnopqrstuvwxyz0123456789"}' }
        @{ Detail = '<html>private response</html>' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file; Detail = $Detail } {
            $folder = Join-Path -Path $Root -ChildPath 'shell-app'
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'abcd'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwNerdioPublishContent { [PSCustomObject]@{} }
            Mock Assert-EwM365NerdioPublishPlan {}
            $saved = @{ Error = '' }
            Mock Invoke-EwNerdioRecoveryStore { if ($null -ne $UpsertOperation) { $saved.Error = $UpsertOperation.Error } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-RestMethod {
                $exception = [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).')
                $record = [System.Management.Automation.ErrorRecord]::new($exception, 'HttpResponseException', 'InvalidOperation', $null)
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
                throw $record
            }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Add version'; ShellAppId = '68' }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath $folder -PackagePath $File -Version $build.OfficeVersion `
                -ShellAppId '68' -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Error | Should -Be 'Response status code does not indicate success: 400 (Bad Request).'
            $saved.Error | Should -Be $result.Error
            $result.Status | Should -Be 'Unknown'
        }
    }

    It 'reports a provider rejection of an attested duplicate version' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; File = $file } {
            $folder = Join-Path -Path $Root -ChildPath 'shell-app'
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test'; ApiOnly = $false } }
            Mock Assert-EwNerdioWriteAllowed {}
            Mock Get-EwNerdioPublishContent { [PSCustomObject]@{} }
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Invoke-EwNerdioRecoveryStore {}
            Mock Invoke-EwNerdioBlobUpload {
                [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file?sig=secret'; Sha256 = 'hash' }
            }
            Mock Invoke-EwNerdioApiRequest { throw 'Duplicate version rejected by Nerdio' }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.1234.1' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Add version'; ShellAppId = 'app' }
            $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath $folder -PackagePath $File -Version '16.0.1234.1' `
                -ShellAppId app -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Status | Should -Be 'Unknown'
            $result.BlobName | Should -Be 'blob'
            $result.Error | Should -Match 'Duplicate version rejected'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1
        }
    }
}
