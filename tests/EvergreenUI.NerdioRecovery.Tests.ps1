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
