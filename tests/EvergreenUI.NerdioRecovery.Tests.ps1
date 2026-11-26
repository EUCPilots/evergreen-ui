#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $script:testAppData = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "EvergreenUI.NerdioRecovery.Tests.$([guid]::NewGuid())"
    $env:APPDATA = $script:testAppData
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force
    $env:APPDATA = $script:originalAppData
    if (Test-Path -LiteralPath $script:testAppData) {
        Remove-Item -LiteralPath $script:testAppData -Recurse -Force
    }
}

Describe 'Nerdio recovery state' {
    BeforeEach {
        $recoveryPath = Join-Path -Path $script:testAppData -ChildPath 'EvergreenWorkbench\nerdio-recovery.json'
        if (Test-Path -LiteralPath $recoveryPath) {
            Remove-Item -LiteralPath $recoveryPath -Force
        }
    }

    It 'allows a Microsoft 365 preview after explicitly acknowledging an unknown publish' {
        InModuleScope EvergreenUI {
            $destination = [ordered]@{
                TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation ([ordered]@{
                    Id = 'office-unknown'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                    Name = 'Microsoft 365 Apps for enterprise: Desktop, Current, x64'
                    Publisher = 'Microsoft'; DefinitionPath = 'C:\fixture\shell-app'
                    AppId = ''; Version = '16.0.20625.20142'; JobId = ''; BlobName = ''; Error = 'Unknown'
                }) | Out-Null
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{
                    SessionId = 'session'; TenantId = 'tenant'; SubscriptionId = 'subscription'
                    NmeHost = 'nme.test'; ResourceGroupName = 'rg'; StorageAccountName = 'storage'
                    ContainerName = 'container'; ApiOnly = $false
                }
            }
            Mock Assert-EwM365BuildPlan {}
            Mock Get-EwM365NerdioTarget { [PSCustomObject]@{} }
            Mock Assert-EwM365NerdioPublishPlan {}
            $build = [PSCustomObject]@{ Provider = 'Nerdio' }
            { Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation Create -Name 'Office' } |
                Should -Throw "*version '16.0.20625.20142' needs review before another write*"

            Clear-EwNerdioRecovery -OperationId 'office-unknown' -Confirm:$false

            $plan = Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation Create -Name 'Office'
            $plan.Name | Should -Be 'Office'
            (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 0
        }
    }

    It 'rejects acknowledgment of a live operation and permits it when its lease ends' {
        InModuleScope EvergreenUI {
            $destination = [ordered]@{
                TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            $id = [guid]::NewGuid().ToString()
            $lease = [System.Threading.Semaphore]::new(0, 1, "Local\EvergreenWorkbench.NerdioOperation.$id")
            try {
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation ([ordered]@{
                        Id = $id; Type = 'Publish'; Status = 'InProgress'; HasActiveLease = $true
                        Destination = $destination; Name = 'Office'; Version = '1.0'
                    }) | Out-Null
                Mock Get-EwNerdioSessionContext { [PSCustomObject]$destination }
                { Clear-EwNerdioRecovery -OperationId $id -Confirm:$false -WarningAction SilentlyContinue } |
                    Should -Throw '*still running*'
                { Resolve-EwNerdioOperationReview -OperationId $id -Outcome Failed } |
                    Should -Throw '*still running*'
                (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 1
            }
            finally { $lease.Dispose() }
            Clear-EwNerdioRecovery -OperationId $id -Confirm:$false -WarningAction SilentlyContinue
            (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 0
        }
    }

    It 'replaces a completed ID-less Microsoft 365 recovery record with a verified pruning offer' {
        InModuleScope EvergreenUI -Parameters @{ Root = $TestDrive } {
            $package = Join-Path -Path $Root -ChildPath 'office.zip'
            Set-Content -LiteralPath $package -Value 'fixture'
            $definition = [PSCustomObject]@{
                name = 'Office'; publisher = 'Microsoft'
                versions = @([PSCustomObject]@{ name = ''; file = [PSCustomObject]@{ sourceUrl = ''; sha256 = '' } })
            }
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                    AccessToken = 'token'; ApiOnly = $false
                }
            }
            Mock Get-EwNerdioPublishContent { $definition }
            Mock Assert-EwM365NerdioPublishPlan {}
            Mock Assert-EwNerdioDestination {}
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'office.zip'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ job = [PSCustomObject]@{ id = '16830'; status = 'Completed' } } }
            Mock Get-EwNerdioShellApp { [PSCustomObject]@{ Id = 'app-42'; Name = 'Office'; Publisher = 'Microsoft' } }
            Mock Get-EwNerdioShellAppVersion { [PSCustomObject]@{ name = '16.0.20625.20142' } }
            $build = [PSCustomObject]@{ ConfigurationRoot = $Root; OfficeVersion = '16.0.20625.20142' }
            $plan = [PSCustomObject]@{ BuildPlan = $build; Name = 'Office'; Operation = 'Create'; ShellAppId = ''; Destination = [PSCustomObject]@{} }
            $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
            $result = Publish-EwNerdioApp -DefinitionPath (Join-Path -Path $Root -ChildPath 'shell-app') -PackagePath $package `
                -Version $build.OfficeVersion -M365Plan $plan -M365PackageHash $hash -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $recovery = Invoke-EwNerdioRecoveryStore -Action Read
            $recovery.Operations | Should -HaveCount 0
            $recovery.PruningOffers | Should -HaveCount 1
            $recovery.PruningOffers[0].AppId | Should -Be 'app-42'
            $recovery.PruningOffers[0].PublishedVersion | Should -Be '16.0.20625.20142'
        }
    }

    It 'keeps a publish protected until its provider request returns' {
        InModuleScope EvergreenUI -Parameters @{ Root = $TestDrive } {
            $package = Join-Path -Path $Root -ChildPath 'office.zip'
            Set-Content -LiteralPath $package -Value 'fixture'
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                    AccessToken = 'token'; ApiOnly = $false
                }
            }
            Mock Get-EwNerdioPublishContent { [PSCustomObject]@{ name = 'Office'; publisher = 'Microsoft' } }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ BlobName = 'blob'; SourceUrl = 'https://storage.test/file'; Sha256 = 'hash' } }
            Mock Invoke-EwNerdioApiRequest {
                $active = @((Invoke-EwNerdioRecoveryStore -Action Read).Operations)[0]
                $active.HasActiveLease | Should -BeTrue
                { Clear-EwNerdioRecovery -OperationId $active.Id -Confirm:$false -WarningAction SilentlyContinue } |
                    Should -Throw '*still running*'
                [PSCustomObject]@{ job = [PSCustomObject]@{ id = 'job'; status = 'Pending' } }
            }
            $result = Publish-EwNerdioApp -DefinitionPath 'C:\fixture' -PackagePath $package -ShellAppId 'app' -Version '1.0' -Confirm:$false
            $result.Status | Should -Be 'Pending'
            $record = @(Get-EwNerdioRecovery)[0]
            Clear-EwNerdioRecovery -OperationId $record.Id -Confirm:$false -WarningAction SilentlyContinue
            @(Get-EwNerdioRecovery) | Should -HaveCount 0
        }
    }

    It 'limits recovery listing and acknowledgment to the connected destination and preserves other records' {
        InModuleScope EvergreenUI {
            $destination = [ordered]@{
                TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            $other = [ordered]@{} + $destination
            $other.NmeHost = 'other.test'
            foreach ($record in @(
                    [ordered]@{ Id = 'current'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination },
                    [ordered]@{ Id = 'other'; Type = 'Publish'; Status = 'Pending'; Destination = $other }
                )) {
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $record | Out-Null
            }
            Invoke-EwNerdioRecoveryStore -Action Update -UpsertOffer ([ordered]@{ Id = 'offer'; Destination = $destination }) | Out-Null
            Mock Get-EwNerdioSessionContext { [PSCustomObject]$destination }
            @(Get-EwNerdioRecovery).Id | Should -Be @('current')
            Clear-EwNerdioRecovery -OperationId 'current' -WhatIf -WarningAction SilentlyContinue
            (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 2
            { Clear-EwNerdioRecovery -OperationId 'other' -Confirm:$false -WarningAction SilentlyContinue } |
                Should -Throw '*destination recorded*'
            { Clear-EwNerdioRecovery -OperationId 'missing' -Confirm:$false -WarningAction SilentlyContinue } |
                Should -Throw '*missing or ambiguous*'
            Clear-EwNerdioRecovery -OperationId 'current' -Confirm:$false -WarningAction SilentlyContinue
            $remaining = Invoke-EwNerdioRecoveryStore -Action Read
            @($remaining.Operations).Id | Should -Be @('other')
            @($remaining.PruningOffers).Id | Should -Be @('offer')
        }
    }

    It 'persists only operation metadata and keeps state readable across loads' {
        InModuleScope EvergreenUI -Parameters @{ Root = $script:testAppData } {
            $path = Join-Path -Path $Root -ChildPath 'recovery.json'
            $operation = [ordered]@{
                Id = 'operation-one'; Type = 'Publish'; Status = 'Unknown'
                Destination = [ordered]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                Name = 'Browser'; AppId = '42'; Version = '2.0'; JobId = 'job-one'
            }
            Invoke-EwNerdioRecoveryStore -Action Update -Path $path -UpsertOperation $operation | Out-Null
            $firstRead = Invoke-EwNerdioRecoveryStore -Action Read -Path $path
            $secondRead = Invoke-EwNerdioRecoveryStore -Action Read -Path $path

            $firstRead.Operations | Should -HaveCount 1
            $secondRead.Operations[0].Status | Should -Be 'Unknown'
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'AccessToken|ClientSecret|synthetic-secret'

            Invoke-EwNerdioRecoveryStore -Action Update -Path $path -RemoveOperationId 'operation-one' | Out-Null
            (Invoke-EwNerdioRecoveryStore -Action Read -Path $path).Operations | Should -HaveCount 0
        }
    }

    It 'requires refresh verification before resolving a successful publish into a pruning offer' {
            InModuleScope EvergreenUI {
                $destination = [ordered]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                $operation = [ordered]@{
                    Id = 'publish-review'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                    Name = 'Browser'; Publisher = 'Vendor'; DefinitionPath = 'C:\Apps\Browser'
                    AppId = '42'; Version = '2.0'; JobId = 'job-one'
                }
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $operation | Out-Null
                Mock Get-EwNerdioSessionContext {
                    [PSCustomObject]@{
                        TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                        ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                    }
                }
                Mock Get-EwNerdioShellApp { @([PSCustomObject]@{ Id = '42'; Name = 'Browser'; Publisher = 'Vendor' }) }
                Mock Get-EwNerdioShellAppVersion { @([PSCustomObject]@{ name = '1.0' }, [PSCustomObject]@{ name = '2.0' }) }

                $result = Resolve-EwNerdioOperationReview -OperationId 'publish-review' -Outcome Completed

                $result.Succeeded | Should -BeTrue
                Should -Invoke Get-EwNerdioShellApp -Exactly 1
                Should -Invoke Get-EwNerdioShellAppVersion -Exactly 1
                $recovery = Invoke-EwNerdioRecoveryStore -Action Read
                $recovery.Operations | Should -HaveCount 0
                $recovery.PruningOffers | Should -HaveCount 1
                $recovery.PruningOffers[0].PublishedVersion | Should -Be '2.0'
            }
        }

    It 'keeps a successful publish unresolved when the refreshed version is missing' {
            InModuleScope EvergreenUI {
                $destination = [ordered]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                $operation = [ordered]@{
                    Id = 'publish-review'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                    Name = 'Browser'; Publisher = 'Vendor'; DefinitionPath = 'C:\Apps\Browser'
                    AppId = '42'; Version = '2.0'; JobId = 'job-one'
                }
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $operation | Out-Null
                Mock Get-EwNerdioSessionContext {
                    [PSCustomObject]@{
                        TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                        ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                    }
                }
                Mock Get-EwNerdioShellApp { @([PSCustomObject]@{ Id = '42'; Name = 'Browser'; Publisher = 'Vendor' }) }
                Mock Get-EwNerdioShellAppVersion { @([PSCustomObject]@{ name = '1.0' }) }

                { Resolve-EwNerdioOperationReview -OperationId 'publish-review' -Outcome Completed } |
                    Should -Throw '*unique newest version*'
                (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 1
            }
        }

        It 'requires the recorded tenant, subscription, host, and storage destination for review' {
            InModuleScope EvergreenUI {
                $destination = [ordered]@{
                    TenantId = 'tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                    ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation ([ordered]@{
                        Id = 'wrong-destination'; Type = 'Publish'; Status = 'Unknown'; Destination = $destination
                        Name = 'Browser'; Publisher = 'Vendor'; DefinitionPath = 'C:\Apps\Browser'
                        AppId = '42'; Version = '2.0'
                    }) | Out-Null
                Mock Get-EwNerdioSessionContext {
                    [PSCustomObject]@{
                        TenantId = 'other-tenant'; SubscriptionId = 'subscription'; NmeHost = 'nme.test'
                        ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                    }
                }
                Mock Get-EwNerdioShellApp {}

                { Resolve-EwNerdioOperationReview -OperationId 'wrong-destination' -Outcome Completed } |
                    Should -Throw '*recorded for this operation*'
                Should -Invoke Get-EwNerdioShellApp -Exactly 0
                (Invoke-EwNerdioRecoveryStore -Action Read).Operations | Should -HaveCount 1
            }
        }
    }

Describe 'Nerdio Shell App pruning plans' {
    It 'keeps the newest requested versions and removes only older exact names' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioShellAppVersion {
                @(
                    [PSCustomObject]@{ name = '1.0' }
                    [PSCustomObject]@{ name = '2.0' }
                    [PSCustomObject]@{ name = '10.0' }
                )
            }

            $plan = Get-EwNerdioShellAppVersionPrunePlan -Id '42' -KeepVersions 2 -PublishedVersion '10.0'
            $plan.Eligible | Should -BeTrue
            $plan.Keep | Should -Be @('10.0', '2.0')
            $plan.Remove | Should -Be @('1.0')
        }
    }

    It 'skips duplicate, unorderable, and non-newest published versions' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioShellAppVersion { @([PSCustomObject]@{ name = '1.0' }, [PSCustomObject]@{ name = '1.0' }) }
            $duplicate = Get-EwNerdioShellAppVersionPrunePlan -Id '42'
            $duplicate.Eligible | Should -BeFalse
            $duplicate.Message | Should -Match 'Duplicate'

            Mock Get-EwNerdioShellAppVersion { @([PSCustomObject]@{ name = '1.0' }, [PSCustomObject]@{ name = 'latest' }) }
            $unorderable = Get-EwNerdioShellAppVersionPrunePlan -Id '42'
            $unorderable.Eligible | Should -BeFalse
            $unorderable.Message | Should -Match 'ordered reliably'

            Mock Get-EwNerdioShellAppVersion { @([PSCustomObject]@{ name = '1.0' }, [PSCustomObject]@{ name = '2.0' }) }
            $notNewest = Get-EwNerdioShellAppVersionPrunePlan -Id '42' -PublishedVersion '1.0'
            $notNewest.Eligible | Should -BeFalse
            $notNewest.Message | Should -Match 'uniquely the newest'
        }
    }
}

Describe 'Nerdio version deletion outcomes' {
    BeforeEach {
        $recoveryPath = Join-Path -Path $script:testAppData -ChildPath 'EvergreenWorkbench\nerdio-recovery.json'
        if (Test-Path -LiteralPath $recoveryPath) {
            Remove-Item -LiteralPath $recoveryPath -Force
        }
    }

    It 'records a pending deletion and stops before later versions or writes' {
        InModuleScope EvergreenUI -Parameters @{ Root = $script:testAppData } {
            $env:APPDATA = $Root
            $recoveryPath = Join-Path -Path $Root -ChildPath 'EvergreenWorkbench\nerdio-recovery.json'
            if (Test-Path -LiteralPath $recoveryPath) {
                Remove-Item -LiteralPath $recoveryPath -Force
            }
            $context = [PSCustomObject]@{
                AccessToken = 'token'; TenantId = 'tenant'; SubscriptionId = 'sub'
                NmeHost = 'nme.test'; ResourceGroupName = 'rg'
                StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Mock Get-EwNerdioSessionContext { $context }
            Mock Get-EwNerdioShellAppVersion {
                @(
                    [PSCustomObject]@{ name = '1.0' }
                    [PSCustomObject]@{ name = '2.0' }
                    [PSCustomObject]@{ name = '3.0' }
                )
            }
            Mock Invoke-EwNerdioApiRequest {
                $active = @((Invoke-EwNerdioRecoveryStore -Action Read).Operations)[0]
                $active.HasActiveLease | Should -BeTrue
                $active.OwnerProcessId | Should -Be $PID
                { Clear-EwNerdioRecovery -OperationId $active.Id -Confirm:$false -WarningAction SilentlyContinue } |
                    Should -Throw '*still running*'
                [PSCustomObject]@{ job = [PSCustomObject]@{ id = 'delete-job'; status = 'Pending' } }
            }

            $result = Remove-EwNerdioShellAppVersion -Id '42' -KeepVersions 1 `
                -ExpectedVersionNames @('1.0', '2.0', '3.0') -ExpectedRemovalVersions @('2.0', '1.0') -Confirm:$false

            $result.PendingVersions | Should -Be @('2.0')
            $result.RemovedCount | Should -Be 0
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1
            $recovery = Invoke-EwNerdioRecoveryStore -Action Read
            $recovery.Operations | Should -HaveCount 1
            $recovery.Operations[0].Status | Should -Be 'Pending'
            { Remove-EwNerdioShellAppVersion -Id '42' -KeepVersions 1 -Confirm:$false } |
                Should -Throw '*outcome*needs review*'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1
        }
    }

    It 'rejects a stale exact-version preview before deleting' {
        InModuleScope EvergreenUI {
            $context = [PSCustomObject]@{
                AccessToken = 'token'; TenantId = 'tenant'; SubscriptionId = 'sub'
                NmeHost = 'nme.test'; ResourceGroupName = 'rg'
                StorageAccountName = 'storage'; ContainerName = 'container'
            }
            Mock Get-EwNerdioSessionContext { $context }
            Mock Get-EwNerdioShellAppVersion {
                @([PSCustomObject]@{ name = '1.0' }, [PSCustomObject]@{ name = '2.0' })
            }
            Mock Invoke-EwNerdioApiRequest {}
            {
                Remove-EwNerdioShellAppVersion -Id '42' -KeepVersions 1 `
                    -ExpectedVersionNames @('1.0', '2.0', '3.0') -ExpectedRemovalVersions @('1.0') -Confirm:$false
            } | Should -Throw '*versions changed*'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 0
        }
    }
}
