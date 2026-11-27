#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force
    $waitForJob = {
        param($Job)
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $snapshot = Get-EwJob -Id $Job.Id
            if ($snapshot.State -notin @('Running', 'NotStarted')) { break }
            Start-Sleep -Milliseconds 20
        } while ([DateTime]::UtcNow -lt $deadline)
        $snapshot.State | Should -Be 'Completed'
        try { $snapshot.Output } finally { Remove-EwJob -Id $Job.Id -Confirm:$false }
    }
}

AfterAll { Remove-Module -Name EvergreenUI -Force }

Describe 'Nerdio sessions across Job workers' {
    It 'reauthenticates an expired cached Azure context inside a job before discovery' {
        $job = Start-EwJob -ScriptBlock {
            & (Get-Module -Name EvergreenUI) {
                $script:fixtureAzureSignedIn = $false
                try {
                    function Assert-EwModule {}
                    function Get-AzContext {
                        [PSCustomObject]@{
                            Account = [PSCustomObject]@{ Id = 'account' }
                            Tenant = [PSCustomObject]@{ Id = 'tenant' }
                            Subscription = [PSCustomObject]@{ Id = 'sub'; Name = 'subscription' }
                        }
                    }
                    function Get-AzAccessToken {
                        throw 'Your Azure credentials have not been set up or have expired'
                    }
                    function Connect-AzAccount { $script:fixtureAzureSignedIn = $true }
                    function Get-AzResourceGroup {
                        if (-not $script:fixtureAzureSignedIn) {
                            throw 'Your Azure credentials have not been set up or have expired'
                        }
                        [PSCustomObject]@{ ResourceGroupName = 'rg' }
                    }
                    $connection = Connect-EwAzure -TenantId tenant -SubscriptionId sub
                    if (-not $connection.Succeeded) { throw $connection.Error }
                    Get-EwAzureResourceGroup
                }
                finally { Remove-Variable -Name fixtureAzureSignedIn -Scope Script -ErrorAction SilentlyContinue }
            }
        }
        & $waitForJob -Job $job | Should -Be 'rg'
    }

    It 'rejects storage binding when <Reason>' -ForEach @(
        @{ Reason = 'the tenant differs'; Case = 'Tenant'; Error = '*tenants do not match*' }
        @{ Reason = 'the API session changed'; Case = 'Session'; Error = '*connection or Azure storage selection changed*' }
        @{ Reason = 'Azure context changed'; Case = 'Azure'; Error = '*Azure tenant or subscription changed*' }
        @{ Reason = 'the API session changes during validation'; Case = 'Race'; Error = '*Nerdio connection changed*' }
        @{ Reason = 'the API token expired'; Case = 'Expired'; Error = '*expired*' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Case = $Case; Error = $Error } {
            $originalContext = $script:ewNerdioSession.Context
            $originalApiOnly = $script:ewNerdioSession.ApiOnly
            try {
                $script:ewNerdioSession.Context = [PSCustomObject]@{
                    SessionId = 'session'; ApiOnly = $true; AccessToken = 'test-token'; TenantId = 'tenant'
                    NmeHost = 'nme.test'; TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
                }
                $script:ewNerdioSession.ApiOnly = $true
                $destination = [PSCustomObject]@{ SessionId = 'session'; NmeHost = 'nme.test' }
                $identity = [PSCustomObject]@{ AccountId = 'account'; TenantId = 'tenant'; SubscriptionId = 'sub'; SubscriptionName = 'subscription' }
                Mock Assert-EwAzureIdentity {}
                switch ($Case) {
                    'Tenant' { $identity.TenantId = 'different' }
                    'Session' { $destination.SessionId = 'old-session' }
                    'Azure' { Mock Assert-EwAzureIdentity { throw 'The selected Azure tenant or subscription changed. Connect Azure again.' } }
                    'Race' { Mock Assert-EwAzureIdentity { $script:ewNerdioSession.Context = $null } }
                    'Expired' { $script:ewNerdioSession.Context.TokenExpiresAt = [DateTimeOffset]::UtcNow.AddMinutes(-1) }
                }
                { Sync-EwNerdioStorageContext -Identity $identity -Destination $destination `
                        -ResourceGroupName 'rg' -StorageAccountName 'storage' -ContainerName 'container' } | Should -Throw $Error
                if ($Case -notin @('Expired', 'Race')) {
                    $script:ewNerdioSession.Context.ApiOnly | Should -BeTrue
                    $script:ewNerdioSession.Context.AccessToken | Should -Be 'test-token'
                }
            }
            finally {
                $script:ewNerdioSession.Context = $originalContext
                $script:ewNerdioSession.ApiOnly = $originalApiOnly
            }
        }
    }

    It 'binds Azure storage in a separate worker without exposing the API token' {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{
                SessionId = 'session'; ApiOnly = $true; AccessToken = 'test-token'; TenantId = 'tenant'
                NmeHost = 'nme.test'; TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
            }
            $script:ewNerdioSession.ApiOnly = $true
        }
        try {
            $job = Start-EwJob -ScriptBlock {
                & (Get-Module -Name EvergreenUI) {
                    function Assert-EwAzureIdentity {}
                    $identity = [PSCustomObject]@{ AccountId = 'account'; TenantId = 'tenant'; SubscriptionId = 'sub'; SubscriptionName = 'subscription' }
                    $destination = [PSCustomObject]@{ SessionId = 'session'; NmeHost = 'nme.test' }
                    Sync-EwNerdioStorageContext -Identity $identity -Destination $destination `
                        -ResourceGroupName 'rg' -StorageAccountName 'storage' -ContainerName 'container'
                }
            }
            $result = & $waitForJob -Job $job
            $result.ApiOnly | Should -BeFalse
            $result.PSObject.Properties.Name | Should -Not -Contain 'AccessToken'
            InModuleScope EvergreenUI {
                $context = Get-EwNerdioSessionContext
                $context.AccessToken | Should -Be 'test-token'
                $context.ContainerName | Should -Be 'container'
                $script:ewNerdioSession.ApiOnly | Should -BeFalse
            }
        }
        finally {
            InModuleScope EvergreenUI { $script:ewNerdioSession.Context = $null; $script:ewNerdioSession.ApiOnly = $false }
        }
    }

    It 'preserves API-only Nerdio authentication when Azure sign-in <Outcome>' -ForEach @(
        @{ Outcome = 'succeeds'; Succeeds = $true }
        @{ Outcome = 'fails'; Succeeds = $false }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Succeeds = $Succeeds } {
            Mock Get-EwNerdioAccessToken { [PSCustomObject]@{ access_token = 'test-token'; expires_in = 3600 } }
            if ($Succeeds) {
                Mock Connect-EwAzAccount { [PSCustomObject]@{ AccountId = 'account'; TenantId = 'tenant'; SubscriptionId = 'sub'; SubscriptionName = 'subscription' } }
            }
            else {
                Mock Connect-EwAzAccount { throw 'Azure sign-in failed' }
            }
            $secret = [System.Security.SecureString]::new()
            try {
                $nerdio = Connect-EwNerdio -TenantId tenant -ClientId client -ClientSecret $secret `
                    -ApiScope scope -NmeHost 'nme.example.test' -ApiOnly
                $nerdio.Succeeded | Should -BeTrue
                $azure = Connect-EwAzure -TenantId tenant -SubscriptionId sub
                $azure.Succeeded | Should -Be $Succeeds
                $context = Get-EwNerdioSessionContext
                $context.SessionId | Should -Be $nerdio.SessionId
                $context.AccessToken | Should -Be 'test-token'
                $script:ewNerdioSession.ApiOnly | Should -BeTrue
            }
            finally {
                $secret.Dispose()
                $null = Disconnect-EwNerdio
            }
        }
    }

    It 'invalidates an Azure-bound Nerdio session when Azure reconnects' {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{ SessionId = 'old-session'; ApiOnly = $false }
            $script:ewNerdioSession.ApiOnly = $false
            Mock Connect-EwAzAccount { [PSCustomObject]@{ AccountId = 'account'; TenantId = 'tenant'; SubscriptionId = 'new-sub'; SubscriptionName = 'subscription' } }
            $result = Connect-EwAzure -TenantId tenant -SubscriptionId new-sub
            $result.Succeeded | Should -BeTrue
            $script:ewNerdioSession.Context | Should -BeNullOrEmpty
        }
    }

    It 'preserves API-only authentication across an Azure sign-in job' {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{
                SessionId = 'session'; ApiOnly = $true; AccessToken = 'test-token'
                TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
            }
            $script:ewNerdioSession.ApiOnly = $true
        }
        try {
            $job = Start-EwJob -ScriptBlock {
                & (Get-Module -Name EvergreenUI) {
                    function Connect-EwAzAccount {
                        [PSCustomObject]@{ AccountId = 'account'; TenantId = 'tenant'; SubscriptionId = 'sub'; SubscriptionName = 'subscription' }
                    }
                    Connect-EwAzure -TenantId tenant -SubscriptionId sub
                }
            }
            $result = & $waitForJob -Job $job
            $result.Succeeded | Should -BeTrue
            InModuleScope EvergreenUI {
                (Get-EwNerdioSessionContext).SessionId | Should -Be 'session'
                $script:ewNerdioSession.ApiOnly | Should -BeTrue
            }
        }
        finally {
            InModuleScope EvergreenUI { $null = Disconnect-EwNerdio }
        }
    }

    It 'connects and disconnects an API-only session without changing Azure context' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioAccessToken { [PSCustomObject]@{ access_token = 'test-token'; expires_in = 3600 } }
            Mock Assert-EwModule { throw 'Azure should not be loaded.' }
            Mock Connect-EwAzAccount { throw 'Azure should not be connected.' }
            Mock Invoke-EwNerdioBlobUpload { throw 'Upload should not run.' }
            Mock Invoke-EwNerdioRecoveryStore { throw 'Recovery state should not be written.' }
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            try {
                $result = Connect-EwNerdio -TenantId tenant -ClientId client -ClientSecret $secret `
                    -ApiScope scope -NmeHost 'nme.example.test' -ApiOnly
                $result.Succeeded | Should -BeTrue -Because $result.Error
                $result.ApiOnly | Should -BeTrue
                (Get-EwNerdioSessionContext).TenantId | Should -Be 'tenant'
                $destination = [PSCustomObject]@{
                    SessionId = $result.SessionId; TenantId = 'tenant'; SubscriptionId = 'subscription'
                    NmeHost = 'nme.example.test'; ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
                }
                { Assert-EwNerdioDestination -Destination $destination } | Should -Throw '*destination changed*'
                $publish = Publish-EwNerdioApp -DefinitionPath 'missing' -Confirm:$false
                $publish.Succeeded | Should -BeFalse
                $publish.Error | Should -Match 'full Nerdio connection'
                (Disconnect-EwNerdio).Succeeded | Should -BeTrue
                Should -Invoke Assert-EwModule -Exactly 0
                Should -Invoke Connect-EwAzAccount -Exactly 0
                Should -Invoke Invoke-EwNerdioBlobUpload -Exactly 0
                Should -Invoke Invoke-EwNerdioRecoveryStore -Exactly 0
            }
            finally { $secret.Dispose() }
        }
    }

    It 'rejects mixed API-only and Azure options before authentication' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioAccessToken { throw 'The API should not be called.' }
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            try {
                $parameters = @{ TenantId = 'tenant'; ClientId = 'client'; ClientSecret = $secret; ApiScope = 'scope'; NmeHost = 'nme.example.test' }
                { Connect-EwNerdio @parameters -ApiOnly -SubscriptionId 'sub' } | Should -Throw '*Parameter set*'
                Should -Invoke Get-EwNerdioAccessToken -Exactly 0
            }
            finally { $secret.Dispose() }
        }
    }

    It 'does not disconnect Azure when an API-only token has expired' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioAccessToken { [PSCustomObject]@{ access_token = 'test-token'; expires_in = 3600 } }
            Mock Assert-EwModule { throw 'Azure should not be loaded.' }
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            try {
                $result = Connect-EwNerdio -TenantId tenant -ClientId client -ClientSecret $secret `
                    -ApiScope scope -NmeHost 'nme.example.test' -ApiOnly
                $result.Succeeded | Should -BeTrue -Because $result.Error
                $script:ewNerdioSession.Context.TokenExpiresAt = [DateTimeOffset]::UtcNow.AddSeconds(-1)
                { Get-EwNerdioSessionContext } | Should -Throw '*expired*'
                (Disconnect-EwNerdio).Succeeded | Should -BeTrue
                Should -Invoke Assert-EwModule -Exactly 0
            }
            finally { $secret.Dispose() }
        }
    }

    It 'preserves an API-only Nerdio session when Azure is disconnected' {
        InModuleScope EvergreenUI {
            Mock Get-EwNerdioAccessToken { [PSCustomObject]@{ access_token = 'test-token'; expires_in = 3600 } }
            Mock Assert-EwModule {}
            Mock Get-AzContext { $null }
            Mock Clear-AzContext {}
            $secret = ConvertTo-SecureString -String 'secret' -AsPlainText -Force
            try {
                $result = Connect-EwNerdio -TenantId tenant -ClientId client -ClientSecret $secret `
                    -ApiScope scope -NmeHost 'nme.example.test' -ApiOnly
                $result.Succeeded | Should -BeTrue -Because $result.Error
                (Disconnect-EwAzure).Succeeded | Should -BeTrue
                (Get-EwNerdioSessionContext).SessionId | Should -Be $result.SessionId
                (Disconnect-EwNerdio).Succeeded | Should -BeTrue
            }
            finally { $secret.Dispose() }
        }
    }

    It 'shares a worker-established session with the caller and a different worker without emitting tokens' {
        $connect = Start-EwJob -ScriptBlock {
            & (Get-Module -Name EvergreenUI) {
                $script:ewNerdioSession.Context = [PSCustomObject]@{
                    SessionId = 'test-session'; AccessToken = 'synthetic-token'
                    TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
                }
            }
            'connected'
        }
        & $waitForJob -Job $connect | Should -Be 'connected'
        InModuleScope EvergreenUI {
            (Get-EwNerdioSessionContext).SessionId | Should -Be 'test-session'
        }
        $occupy = Start-EwJob -ScriptBlock { Start-Sleep -Seconds 2; 'occupied' }
        $read = Start-EwJob -ScriptBlock {
            & (Get-Module -Name EvergreenUI) { (Get-EwNerdioSessionContext).SessionId }
        }
        & $waitForJob -Job $read | Should -Be 'test-session'
        & $waitForJob -Job $occupy | Should -Be 'occupied'
        $clear = Start-EwJob -ScriptBlock {
            & (Get-Module -Name EvergreenUI) { $script:ewNerdioSession.Context = $null }
        }
        $null = & $waitForJob -Job $clear
        InModuleScope EvergreenUI { { Get-EwNerdioSessionContext } | Should -Throw '*not connected*' }
    }

    It 'rejects expired sessions and changed Azure subscriptions' {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{ TokenExpiresAt = [DateTimeOffset]::UtcNow.AddSeconds(-1) }
            { Get-EwNerdioSessionContext } | Should -Throw '*expired*'
            $destination = [PSCustomObject]@{
                SessionId = 'id'; TenantId = 'tenant'; SubscriptionId = 'sub'; NmeHost = 'nme.test'
                ResourceGroupName = 'rg'; StorageAccountName = 'storage'; ContainerName = 'container'
            }
            $script:ewNerdioSession.Context = $destination | Select-Object -Property *
            $script:ewNerdioSession.Context | Add-Member -NotePropertyName TokenExpiresAt -NotePropertyValue ([DateTimeOffset]::UtcNow.AddHours(1))
            Mock Assert-EwModule {}
            Mock Get-AzContext { [PSCustomObject]@{ Tenant = @{ Id = 'tenant' }; Subscription = @{ Id = 'other' } } }
            { Assert-EwNerdioDestination -Destination $destination } | Should -Throw '*subscription*'
        }
    }
}
