#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}
AfterAll { Remove-Module -Name EvergreenUI -Force }

Describe 'Nerdio publish outcomes' {
    BeforeEach {
        $folder = Join-Path -Path $TestDrive -ChildPath 'App'
        $null = New-Item -Path $folder -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Definition.json') -Value '{"name":"App","publisher":"Vendor","versions":[{"name":"1","file":{"sourceUrl":"","sha256":""}}]}'
        foreach ($name in 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath $name) -Value 'Write-Output "script"'
        }
        $file = Join-Path -Path $TestDrive -ChildPath 'app.exe'
        Set-Content -LiteralPath $file -Value 'payload'
    }

    It 'retains pending identifiers and does not report completion' {
        InModuleScope EvergreenUI -Parameters @{ Folder = $folder; File = $file } {
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test' } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file?sig=secret'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ item = [PSCustomObject]@{ id = 'app' }; job = [PSCustomObject]@{ id = 'job'; status = 'Pending' } } }
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -PackagePath $File -Version '2.0' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Status | Should -Be 'Pending'
            $result.BlobName | Should -Be 'blob'
            $result.AppId | Should -Be 'app'
            $result.JobId | Should -Be 'job'
            $result | ConvertTo-Json | Should -Not -Match 'sig=secret'
        }
    }

    It 'rejects malformed create content before upload and preserves unknown post outcomes' {
        InModuleScope EvergreenUI -Parameters @{ Folder = $folder; File = $file } {
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test' } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { throw 'Response lost' }
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -PackagePath $File -Version '2.0' -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.BlobName | Should -Be 'blob'
            Set-Content -LiteralPath (Join-Path -Path $Folder -ChildPath 'Definition.json') -Value '{"versions":[]}'
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -PackagePath $File -Version '2.0' -Confirm:$false
            $result.Status | Should -Be 'Failed'
            Should -Invoke Invoke-EwNerdioBlobUpload -Exactly 1
        }
    }

    It 'retains upload identifiers and stops uncertain uploads without posting to Nerdio' {
        InModuleScope EvergreenUI -Parameters @{ Folder = $folder; File = $file } {
            $context = [PSCustomObject]@{
                AccessToken = 'token'; NmeHost = 'nme.test'; ResourceGroupName = 'rg'
                StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Mock Get-EwNerdioSessionContext { $context }
            Mock Assert-EwModule {}
            Mock Get-AzStorageAccountKey { [PSCustomObject]@{ Value = 'synthetic-key' } }
            Mock New-AzStorageContext { [PSCustomObject]@{ Name = 'synthetic-context' } }
            Mock Set-AzStorageBlobContent -RemoveParameterType Context { throw 'Upload response lost at https://storage.test/file?sig=secret' }
            Mock New-AzStorageBlobSASToken -RemoveParameterType Context { throw 'SAS denied' }
            Mock Invoke-EwNerdioApiRequest {}
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -ShellAppId 'target' -PackagePath $File -Version '2.0' -Confirm:$false
            $result.Status | Should -Be 'Unknown'
            $result.AppId | Should -Be 'target'
            $result.BlobName | Should -Match '\.app.exe$'
            $result.Error | Should -Not -Match 'sig=secret'
            Should -Invoke New-AzStorageBlobSASToken -Exactly 0
            Mock Set-AzStorageBlobContent -RemoveParameterType Context { [PSCustomObject]@{ ICloudBlob = [PSCustomObject]@{ Uri = [uri]'https://storage.test/file' } } }
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -ShellAppId 'target' -PackagePath $File -Version '2.0' -Confirm:$false
            $result.Status | Should -Be 'Failed' -Because $result.Error
            $result.BlobName | Should -Match '\.app.exe$'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 0
        }
    }

    It 'rechecks the snapshot after upload before adding a version' {
        InModuleScope EvergreenUI -Parameters @{ Folder = $folder; File = $file } {
            Mock Get-EwNerdioSessionContext { [PSCustomObject]@{ AccessToken = 'token'; NmeHost = 'nme.test' } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest {
                [PSCustomObject]@{ job = [PSCustomObject]@{ id = 'job'; status = 'Completed' } }
            }
            $snapshot = [PSCustomObject]@{ Item = [PSCustomObject]@{ DefinitionPath = $Folder; SourceVersion = '2.0'; NerdioAppId = 'target' } }
            $checks = @{ Count = 0; Changed = $false }
            Mock Assert-EwNerdioPublishSnapshot {
                $checks.Count++
                if ($checks.Changed -and $checks.Count -eq 3) { throw 'Target changed after upload' }
            }
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -ShellAppId 'target' -PackagePath $File -Version '2.0' -Snapshot $snapshot -Confirm:$false
            $result.Status | Should -Be 'Completed'
            $result.AppId | Should -Be 'target'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1 -ParameterFilter {
                $Uri -eq 'https://nme.test/api/v1/shell-app/target/version' -and $Body.name -eq '2.0'
            }
            $checks.Count = 0
            $checks.Changed = $true
            $result = Publish-EwNerdioApp -DefinitionPath $Folder -ShellAppId 'target' -PackagePath $File -Version '2.0' -Snapshot $snapshot -Confirm:$false
            $result.Status | Should -Be 'Failed'
            $result.BlobName | Should -Be 'blob'
            $result.AppId | Should -Be 'target'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1
        }
    }
}

Describe 'Sequential Nerdio batches' {
    It 'cancels only after the active item completes and stops after access loss' {
        InModuleScope EvergreenUI -Parameters @{ Working = $TestDrive } {
            $items = @(
                foreach ($name in 'One', 'Two') {
                    [PSCustomObject]@{ Eligible = $true; Operation = 'Create'; DefinitionPath = $name; Publisher = 'Vendor'; AppName = $name; SourceVersion = '2.0'; NerdioAppId = ''; Artifact = [PSCustomObject]@{ URI = 'https://example.test/app.exe' } }
                }
            )
            $plan = [PSCustomObject]@{ DefinitionRoot = 'root'; Destination = [PSCustomObject]@{ NmeHost = 'nme.test'; ResourceGroupName = 'rg'; StorageAccountName = 'storage' } }
            Mock Assert-EwNerdioDestination {}
            Mock Assert-EwNerdioPublishSnapshot {}
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'app.exe'
                Set-Content -LiteralPath $path -Value 'payload'
                [PSCustomObject]@{ FullName = $path }
            }
            $cancel = [System.Threading.CancellationTokenSource]::new()
            Mock Publish-EwNerdioApp {
                $cancel.Cancel()
                [PSCustomObject]@{ Succeeded = $true; Status = 'Completed'; AppId = 'app'; JobId = 'job'; BlobName = 'blob'; Error = '' }
            }
            try {
                $results = @(Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -CancellationToken $cancel.Token -Confirm:$false)
                $results.Status | Should -Be @('Completed', 'Cancelled')
            }
            finally { $cancel.Dispose() }
            Mock Publish-EwNerdioApp { [PSCustomObject]@{ Succeeded = $false; Status = 'Failed'; AppId = ''; JobId = ''; BlobName = 'blob'; Error = 'Failed' } }
            Mock Get-EwNerdioShellApp { throw 'Access lost' }
            $results = @(Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -Confirm:$false)
            $results.Status | Should -Be @('Failed', 'Not started')
        }
    }
    It 'continues definite failures when access checks pass but skips stale selections' {
        InModuleScope EvergreenUI -Parameters @{ Working = $TestDrive } {
            $items = @(
                foreach ($name in 'One', 'Two') {
                    [PSCustomObject]@{ Eligible = $true; Operation = 'Create'; DefinitionPath = $name; Publisher = 'Vendor'; AppName = $name; SourceVersion = '2.0'; NerdioAppId = ''; Artifact = [PSCustomObject]@{ URI = 'https://example.test/app.exe' } }
                }
            )
            $plan = [PSCustomObject]@{ DefinitionRoot = 'root'; Destination = [PSCustomObject]@{ NmeHost = 'nme.test'; ResourceGroupName = 'rg'; StorageAccountName = 'storage' } }
            Mock Assert-EwNerdioDestination {}
            Mock Assert-EwNerdioPublishSnapshot {}
            Mock Get-EwNerdioShellApp {}
            Mock Get-EwAzureStorageContainer { 'container' }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'app.exe'
                Set-Content -LiteralPath $path -Value 'payload'
                [PSCustomObject]@{ FullName = $path }
            }
            Mock Publish-EwNerdioApp {
                $success = $DefinitionPath -eq 'Two'
                [PSCustomObject]@{ Succeeded = $success; Status = if ($success) { 'Completed' } else { 'Failed' }; AppId = ''; JobId = ''; BlobName = ''; Error = if ($success) { '' } else { 'Failed' } }
            }
            $results = @(Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -Confirm:$false)
            $results.Status | Should -Be @('Failed', 'Completed')
            Mock Assert-EwNerdioPublishSnapshot { throw 'Changed' }
            $results = @(Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -Confirm:$false)
            $results.Status | Should -Be @('Skipped', 'Skipped')
            Should -Invoke Invoke-EwArtifactSave -Exactly 2
        }
    }

    It 'stops pending batches without starting later items and respects confirmation decline' {
        InModuleScope EvergreenUI -Parameters @{ Working = $TestDrive } {
            $items = @(
                foreach ($name in 'One', 'Two') {
                    [PSCustomObject]@{ Eligible = $true; Operation = 'Create'; DefinitionPath = $name; Publisher = 'Vendor'; AppName = $name; SourceVersion = '2.0'; NerdioAppId = ''; Artifact = [PSCustomObject]@{ URI = 'https://example.test/app.exe' } }
                }

            )
            $plan = [PSCustomObject]@{ DefinitionRoot = 'root'; Destination = [PSCustomObject]@{ NmeHost = 'nme.test' } }
            Mock Assert-EwNerdioDestination {}
            Mock Assert-EwNerdioPublishSnapshot {}
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'app.exe'
                Set-Content -LiteralPath $path -Value 'payload'
                [PSCustomObject]@{ FullName = $path }
            }
            Mock Publish-EwNerdioApp { [PSCustomObject]@{ Succeeded = $false; Status = 'Pending'; AppId = 'app'; JobId = 'job'; BlobName = 'blob'; Error = 'Review' } }
            $results = @(Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -Confirm:$false)
            $results.Status | Should -Be @('Pending', 'Not started')
            Should -Invoke Publish-EwNerdioApp -Exactly 1
            Publish-EwNerdioBatch -Plan $plan -Selection $items -WorkingPath $Working -WhatIf
            Should -Invoke Invoke-EwArtifactSave -Exactly 1
        }
    }
}

Describe 'Read-only Nerdio publishing preparation' {
    It 'resolves unmatched sources, blocks invalid/current/duplicate rows, and catches edited scripts' {
        InModuleScope EvergreenUI -Parameters @{ Root = $TestDrive } {
            foreach ($name in 'New', 'Update', 'Current', 'Missing', 'DuplicateA', 'DuplicateB', 'Static', 'VcRedist') {
                $folder = Join-Path -Path $Root -ChildPath $name
                $null = New-Item -Path $folder -ItemType Directory -Force
                $appName = if ($name -like 'Duplicate*') { 'Duplicate' } else { $name }
                $definition = [PSCustomObject]@{
                    name = $appName; publisher = 'Vendor'
                    source = [PSCustomObject]@{ type = if ($name -in @('Static', 'VcRedist')) { $name } else { 'Evergreen' }; app = 'Example'; filter = '' }
                    versions = @([PSCustomObject]@{ name = '1'; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
                }
                $definition | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Definition.json')
                if ($name -ne 'Missing') {
                    foreach ($script in 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
                        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath $script) -Value 'Write-Output "script"'
                    }
                }
            }
            $destination = [PSCustomObject]@{
                SessionId = 'id'; TenantId = 'tenant'; SubscriptionId = 'sub'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Mock Get-EwNerdioSessionContext { $destination }
            Mock Assert-EwNerdioDestination {}
            $remote = @(
                [PSCustomObject]@{ Id = 'current'; Name = 'Current'; Publisher = 'Vendor'; LatestVersion = '2.0'; VersionCount = 1 }
                [PSCustomObject]@{ Id = 'update'; Name = 'Update'; Publisher = 'Vendor'; LatestVersion = '1.0'; VersionCount = 1 }
            )
            $resolvedSource = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/app.exe'; Artifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/app.exe' } }
            Mock Get-EwNerdioShellApp { $remote }
            Mock Resolve-EwNerdioSource { $resolvedSource }
            $plan = Get-EwNerdioPublishPlan -DefinitionPath $Root
            $new = $plan.Items | Where-Object AppName -eq 'New'
            $new.Eligible | Should -BeTrue
            $new.SourceVersion | Should -Be '2.0'
            $new.Operation | Should -Be 'Create'
            @($plan.Items | Where-Object Eligible).Count | Should -Be 2
            $update = $plan.Items | Where-Object AppName -eq 'Update'
            $update.Operation | Should -Be 'Add version'
            ($plan.Items | Where-Object AppName -eq 'Static').Eligible | Should -BeFalse
            ($plan.Items | Where-Object AppName -eq 'VcRedist').Eligible | Should -BeFalse
            ($plan.Items | Where-Object AppName -eq 'Current').Eligible | Should -BeFalse
            ($plan.Items | Where-Object AppName -eq 'Missing').MatchStatus | Should -Be 'Preflight failed'
            $snapshot = [PSCustomObject]@{ Destination = $destination; DefinitionRoot = $Root; Item = $new }
            { Assert-EwNerdioPublishSnapshot -Snapshot $snapshot } | Should -Not -Throw
            $resolvedSource.Version = '3.0'
            { Assert-EwNerdioPublishSnapshot -Snapshot $snapshot } | Should -Throw '*SourceVersion changed*'
            $resolvedSource.Version = '2.0'
            $resolvedSource.URI = 'https://example.test/replacement.exe'
            { Assert-EwNerdioPublishSnapshot -Snapshot $snapshot } | Should -Throw '*SourceURI changed*'
            $resolvedSource.URI = 'https://example.test/app.exe'
            $updateSnapshot = [PSCustomObject]@{ Destination = $destination; DefinitionRoot = $Root; Item = $update }
            $remote[1].Id = 'replacement'
            { Assert-EwNerdioPublishSnapshot -Snapshot $updateSnapshot } | Should -Throw '*NerdioAppId changed*'
            Set-Content -LiteralPath (Join-Path -Path $new.DefinitionPath -ChildPath 'Install.ps1') -Value 'Write-Output "changed"'
            { Assert-EwNerdioPublishSnapshot -Snapshot $snapshot } | Should -Throw '*DefinitionHash changed*'
        }
    }
}
