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
