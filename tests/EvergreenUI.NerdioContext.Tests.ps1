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
