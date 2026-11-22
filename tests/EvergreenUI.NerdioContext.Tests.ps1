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
