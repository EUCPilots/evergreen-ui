#Requires -Version 7.6

BeforeDiscovery {
    $graphAvailable = $null -ne (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1)
}

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Intune background context' {
    It 'exposes a process-scoped Graph context to a Workbench job' -Skip:(-not $graphAvailable) {
        Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
        $session = [Microsoft.Graph.PowerShell.Authentication.GraphSession]::Instance
        $original = $session.AuthContext
        $context = [Microsoft.Graph.PowerShell.Authentication.AuthContext]::new()
        $context.TenantId = 'synthetic-tenant'
        $context.Account = 'synthetic-account'
        $context.ContextScope = [Microsoft.Graph.PowerShell.Authentication.ContextScope]::Process
        $job = $null
        $snapshot = $null
        try {
            $session.AuthContext = $context
            $job = Start-EwJob -Name 'Check Graph context' -ScriptBlock {
                Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
                $workerContext = Get-MgContext -ErrorAction Stop
                [PSCustomObject]@{ TenantId = [string]$workerContext.TenantId }
            }
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 100
                $snapshot = Get-EwJob -Id $job.Id
            } while ($snapshot.State -in @('NotStarted', 'Running', 'Stopping') -and [DateTime]::UtcNow -lt $deadline)
            $snapshot.State | Should -Be 'Completed'
            $snapshot.Output[0].TenantId | Should -Be 'synthetic-tenant'
        }
        finally {
            if ($null -ne $job) {
                if ($null -eq $snapshot -or $snapshot.State -in @('NotStarted', 'Running', 'Stopping')) {
                    Stop-EwJob -Id $job.Id -Confirm:$false | Out-Null
                }
                Remove-EwJob -Id $job.Id -Confirm:$false
            }
            $session.AuthContext = $original
        }
    }
}
