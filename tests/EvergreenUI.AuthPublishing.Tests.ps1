#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Provider authentication' {
    It 'connects to Intune with the required delegated scope' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Connect-MgGraph {}
            Mock Get-MgContext { [PSCustomObject]@{ Account = 'user@example.test'; TenantId = 'tenant-id' } }
            $result = Connect-EwIntune -TenantId 'tenant-id'
            $result.Succeeded | Should -BeTrue
            $result.AccountId | Should -Be 'user@example.test'
            Should -Invoke Connect-MgGraph -Exactly 1 -ParameterFilter {
                $Scopes -contains 'DeviceManagementApps.ReadWrite.All' -and
                $ContextScope -eq 'Process' -and $TenantId -eq 'tenant-id'
            }
        }
    }

    It 'connects Azure and keeps Nerdio auth metadata in process memory' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioAccessToken { [PSCustomObject]@{ access_token = 'test-token'; expires_in = 3600 } }
            Mock Assert-EwModule {}
            Mock Connect-AzAccount {}
            Mock Get-AzContext {
                [PSCustomObject]@{
                    Account = [PSCustomObject]@{ Id = 'user@example.test' }
                    Subscription = [PSCustomObject]@{ Id = 'sub-id'; Name = 'Test subscription' }
                }
            }
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            $result = Connect-EwNerdio -TenantId tenant-id -SubscriptionId sub-id -ClientId client-id `
                -ClientSecret $secret -ApiScope 'api://nme/.default' -NmeHost 'nme.example.test' `
                -ResourceGroupName apps -StorageAccountName packages -ContainerName shell-apps
            $result.Succeeded | Should -BeTrue
            $result.AccountId | Should -Be 'user@example.test'
            $result.NmeHost | Should -Be 'nme.example.test'
            $script:ewNerdioSession.Context.AccessToken | Should -Be 'test-token'
            $script:ewNerdioSession.Context.PSObject.Properties.Name | Should -Not -Contain 'ClientSecret'
            Should -Invoke Connect-AzAccount -Exactly 1 -ParameterFilter { $Tenant -eq 'tenant-id' -and $Subscription -eq 'sub-id' }
        }
    }

    It 'rejects non-HTTPS token endpoints before sending a client secret' {
        InModuleScope EvergreenUI {
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            { Get-EwNerdioAccessToken -TenantId t -ClientId c -ClientSecret $secret -ApiScope s -OAuthTokenUrl 'http://example.test/token' } |
                Should -Throw '*HTTPS*'
        }
    }
}

Describe 'Provider publishing' {
    BeforeEach {
        $script:publishRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $script:intuneDefinitionPath = Join-Path -Path $publishRoot -ChildPath 'Intune\App.json'
        $intuneDirectory = Split-Path -Path $intuneDefinitionPath -Parent
        $shellDefinitionPath = Join-Path -Path $publishRoot -ChildPath 'ShellApp'
        New-Item -Path $intuneDirectory -ItemType Directory -Force | Out-Null
        New-Item -Path $shellDefinitionPath -ItemType Directory -Force | Out-Null
        [PSCustomObject]@{
            Application = [PSCustomObject]@{ Name = 'Example' }
            PackageInformation = [PSCustomObject]@{ Version = '1.0'; SetupFile = 'setup.exe' }
            Information = [PSCustomObject]@{ DisplayName = 'Example app'; PSPackageFactoryGuid = '9fddd581-f505-4760-9bb3-2365db204b38' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $intuneDefinitionPath
        [PSCustomObject]@{
            name = 'Example shell app'
            versions = @([PSCustomObject]@{ name = '0.0'; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            source = [PSCustomObject]@{ filter = 'internal-only' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path -Path $shellDefinitionPath -ChildPath 'Definition.json')
        foreach ($fileName in @('Detect.ps1', 'Install.ps1', 'Uninstall.ps1')) {
            Set-Content -LiteralPath (Join-Path -Path $shellDefinitionPath -ChildPath $fileName) -Value "Write-Output '$fileName'"
        }
        $script:packagePath = Join-Path -Path $publishRoot -ChildPath 'package.intunewin'
        Set-Content -LiteralPath $packagePath -Value 'package'
    }

    It 'publishes Intune only after confirmation and returns the Graph outcome' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $intuneDefinitionPath; PackagePath = $packagePath } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Invoke-EwIntuneGraphWin32Import {
                [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'app-id'; DisplayName = 'Example app'; Error = '' }
            }
            $result = Publish-EwIntuneApp -DefinitionPath $DefinitionPath -PackagePath $PackagePath -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.IntuneAppId | Should -Be 'app-id'
            Should -Invoke Invoke-EwIntuneGraphWin32Import -Exactly 1 -ParameterFilter {
                $PSPackageFactoryGuid -eq '9fddd581-f505-4760-9bb3-2365db204b38' -and
                $DownloadedVersion -eq '1.0' -and $IntuneWinPath -eq $PackagePath
            }
        }
    }

    It 'does not publish the Intune package under WhatIf' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $intuneDefinitionPath; PackagePath = $packagePath } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Invoke-EwIntuneGraphWin32Import {}
            Publish-EwIntuneApp -DefinitionPath $DefinitionPath -PackagePath $PackagePath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-EwIntuneGraphWin32Import -Exactly 0
        }
    }

    It 'retains a created app ID when its content version fails with uninstall option <Option>' -ForEach @(
        @{ Option = 'omitted'; UninstallValue = $null; ExpectedUninstall = $false; Architecture = 'x64'; ExpectedArchitecture = 'x64' }
        @{ Option = 'enabled'; UninstallValue = $true; ExpectedUninstall = $true; Architecture = 'x86,x64'; ExpectedArchitecture = 'x86,x64' }
        @{ Option = 'disabled'; UninstallValue = $false; ExpectedUninstall = $false; Architecture = 'arm64, x64'; ExpectedArchitecture = 'x64,arm64' }
        @{ Option = 'x86'; UninstallValue = $null; ExpectedUninstall = $false; Architecture = 'x86'; ExpectedArchitecture = 'x86' }
        @{ Option = 'arm64'; UninstallValue = $null; ExpectedUninstall = $false; Architecture = 'arm64'; ExpectedArchitecture = 'arm64' }
        @{ Option = 'x86 and arm64'; UninstallValue = $null; ExpectedUninstall = $false; Architecture = 'x86,arm64'; ExpectedArchitecture = 'x86,arm64' }
        @{ Option = 'all'; UninstallValue = $null; ExpectedUninstall = $false; Architecture = 'All'; ExpectedArchitecture = 'x86,x64,arm64' }
    ) {
        $template = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Resources\m365-app.json'
        $definition = Get-Content -LiteralPath $template -Raw | ConvertFrom-Json
        $definition.RequirementRule.Architecture = $Architecture
        $registryPath = [string]$definition.DetectionRule[1].KeyPath
        $definition.DetectionRule[1].PSObject.Properties.Remove('KeyPath')
        $definition.DetectionRule[1] | Add-Member -NotePropertyName Path -NotePropertyValue $registryPath
        $definition.PackageInformation.IconFile = ''
        if ($null -ne $UninstallValue) {
            $definition.Program | Add-Member -NotePropertyName AllowAvailableUninstall -NotePropertyValue $UninstallValue
        }
        $archivePath = Join-Path -Path $publishRoot -ChildPath 'test.intunewin'
        $archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entry in @(
                    @{ Name = 'detection.xml'; Content = '<ApplicationInfo><UnencryptedContentSize>1</UnencryptedContentSize><EncryptionInfo><EncryptionKey>x</EncryptionKey><MacKey>x</MacKey><InitializationVector>x</InitializationVector><Mac>x</Mac><FileDigest>x</FileDigest><FileDigestAlgorithm>SHA256</FileDigestAlgorithm><ProfileIdentifier>EncryptionVersion1</ProfileIdentifier></EncryptionInfo></ApplicationInfo>' }
                    @{ Name = 'IntunePackage.intunewin'; Content = 'x' }
                )) {
                $writer = [System.IO.StreamWriter]::new($archive.CreateEntry($entry.Name).Open())
                try { $writer.Write($entry.Content) } finally { $writer.Dispose() }
            }
        }
        finally {
            $archive.Dispose()
        }
        InModuleScope EvergreenUI -Parameters @{
            Definition = $definition; Archive = $archivePath; ExpectedUninstall = $ExpectedUninstall; ExpectedArchitecture = $ExpectedArchitecture
        } {
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Write-UILog {}
            Mock Invoke-MgGraphRequest {
                if ($Uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps') {
                    return [PSCustomObject]@{ id = 'created-id' }
                }
                throw 'content version failed'
            }
            $result = Invoke-EwIntuneGraphWin32Import -DefinitionObject $Definition -IntuneWinPath $Archive `
                -SetupFilePath 'Setup.exe' -DownloadedVersion '2.0' -PSPackageFactoryGuid 'guid' -SyncHash @{}
            $result.Succeeded | Should -BeFalse
            $result.IntuneAppId | Should -Be 'created-id'
            $result.Error | Should -Match 'content version'
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -and
                ($Body | ConvertFrom-Json).displayName -eq "$($Definition.Information.DisplayName) 2.0" -and
                ($Body | ConvertFrom-Json).allowAvailableUninstall -ceq $ExpectedUninstall -and
                ($Body | ConvertFrom-Json).allowedArchitectures -ceq $ExpectedArchitecture -and
                ($Body | ConvertFrom-Json).detectionRules[1].keyPath -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -and
                ($Body | ConvertFrom-Json).detectionRules[0].detectionType -eq 'version' -and
                ($Body | ConvertFrom-Json).detectionRules[0].detectionValue -eq '16.0.15726.20262'
            }

            Mock Start-Sleep {}
            Mock Invoke-RestMethod {}
            Mock Invoke-MgGraphRequest {
                if ($Uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps') {
                    return [PSCustomObject]@{ id = 'created-id' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*/contentVersions') {
                    return [PSCustomObject]@{ id = 'version-id' }
                }
                if ($Method -eq 'POST' -and $Uri -like '*/files') {
                    return [PSCustomObject]@{ id = 'file-id'; azureStorageUri = 'https://example.test/blob' }
                }
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{ uploadState = 'commitFileSuccess' }
                }
            }
            $update = Invoke-EwIntuneGraphWin32Import -DefinitionObject $Definition -IntuneWinPath $Archive `
                -SetupFilePath 'Setup.exe' -DownloadedVersion '2.0' -PSPackageFactoryGuid 'guid' `
                -ImportAsUpdate -SyncHash @{}
            $update.Succeeded | Should -BeTrue -Because $update.Error
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -and
                ($Body | ConvertFrom-Json).requirementRules[1].keyPath -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
            }
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Uri -like '*/assignments' -and
                ($Body | ConvertFrom-Json).target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' -and
                ($Body | ConvertFrom-Json).intent -eq 'required'
            }

            $script:cancelAfterUpload = [System.Threading.CancellationTokenSource]::new()
            try {
                Mock Invoke-RestMethod {
                    if ($Uri -like '*comp=blocklist*') { $script:cancelAfterUpload.Cancel() }
                }
                $cancelled = Invoke-EwIntuneGraphWin32Import -DefinitionObject $Definition -IntuneWinPath $Archive `
                    -SetupFilePath 'Setup.exe' -DownloadedVersion '2.0' -PSPackageFactoryGuid 'guid' `
                    -CancellationToken $script:cancelAfterUpload.Token -SyncHash @{}
                $cancelled.Succeeded | Should -BeFalse
                $cancelled.Cancelled | Should -BeTrue
                $cancelled.WriteStarted | Should -BeTrue
                $cancelled.IntuneAppId | Should -Be 'created-id'
                $cancelled.Error | Should -Match 'after upload'
                Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter { $Uri -like '*/commit' }
            }
            finally { $script:cancelAfterUpload.Dispose() }
        }
    }

    It 'rejects missing and malformed OS architecture requirements before any Graph request' -ForEach @(
        @{ Architecture = '' }
        @{ Architecture = '-' }
        @{ Architecture = 'x64,typo' }
        @{ Architecture = 'All,x64' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Architecture = $Architecture; Archive = $packagePath } {
            Mock Invoke-MgGraphRequest {}
            $definition = [PSCustomObject]@{ RequirementRule = [PSCustomObject]@{ Architecture = $Architecture } }
            $result = Invoke-EwIntuneGraphWin32Import -DefinitionObject $definition -IntuneWinPath $Archive `
                -DownloadedVersion '1' -PSPackageFactoryGuid 'guid' -SyncHash @{}
            $result.Succeeded | Should -BeFalse
            $result.WriteStarted | Should -BeFalse
            $result.Error | Should -Match 'architecture'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }
    }

    It 'uploads a Nerdio Shell App payload and removes internal source metadata' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $shellDefinitionPath; PackagePath = $packagePath } {
            $script:ewNerdioSession.Context = [PSCustomObject]@{
                AccessToken = 'test-token'
                TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
                NmeHost = 'nme.example.test'
            }
            Mock Invoke-EwNerdioBlobUpload {
                [PSCustomObject]@{ Sha256 = 'sha256'; SourceUrl = 'https://storage.example.test/package.zip' }
            }
            Mock Invoke-EwNerdioApiRequest {
                [PSCustomObject]@{ item = [PSCustomObject]@{ id = 'shell-id' }; job = [PSCustomObject]@{ id = 'job-id'; status = 'Completed' } }
            }
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{
                    AccessToken = 'test-token'; TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.example.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
            }
            $result = Publish-EwNerdioApp -DefinitionPath $DefinitionPath -PackagePath $PackagePath -Version '2.0' -Confirm:$false
            $result.Succeeded | Should -BeTrue -Because $result.Error
            $result.JobId | Should -Be 'job-id'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'https://nme.example.test/api/v1/shell-app' -and
                $Body.versions[0].name -eq '2.0' -and
                $null -eq $Body.PSObject.Properties['source'] -and
                $Body.detectScript -match 'Detect.ps1'
            }
        }
    }

    It 'sets Intune supersedence through Graph and rejects self-supersedence' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Invoke-MgGraphRequest {
                if ($Method -eq 'GET') { [PSCustomObject]@{ value = @() } }
            }
            $result = Set-EwIntuneSupersedence -NewAppId new-id -PreviousAppId old-id -Confirm:$false
            $result.Succeeded | Should -BeTrue
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*mobileApps/new-id/updateRelationships'
            }
            { Set-EwIntuneSupersedence -NewAppId same-id -PreviousAppId same-id -Confirm:$false } |
                Should -Throw '*must be different*'
        }
    }
}
