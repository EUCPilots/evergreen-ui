#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop

    function Wait-TestJob {
        param([guid]$Id)

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $job = Get-EwJob -Id $Id
            if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
                return $job
            }
            Start-Sleep -Milliseconds 50
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "Job $Id did not finish in time."
    }
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Workbench jobs' {
    It 'can run a local job without importing Workbench or Evergreen in a fresh worker' {
        $job = Start-EwJob -NoModuleImport -ScriptBlock {
            @(Get-Module -Name EvergreenUI, Evergreen).Count
        }
        try {
            $job = Wait-TestJob -Id $job.Id
            $job.State | Should -Be 'Completed'
            $job.Output | Should -Be 0
        }
        finally {
            Remove-EwJob -Id $job.Id -Confirm:$false
        }
    }

    It 'executes with arguments and exposes progress, information, and output' {
        $job = Start-EwJob -Name 'stream test' -ScriptBlock {
            param($Value)
            Write-Progress -Activity 'Example' -Status 'Running' -PercentComplete 50
            Write-Information -MessageData 'job message' -InformationAction Continue
            $Value * 2
        } -ArgumentList 21
        $job = Wait-TestJob -Id $job.Id
        $job.State | Should -Be 'Completed'
        $job.Output | Should -Be 42
        @($job.Progress | Where-Object Activity -eq 'Example').Count | Should -Be 1
        @($job.Information | Where-Object MessageData -eq 'job message').Count | Should -Be 1
        Remove-EwJob -Id $job.Id
        { Get-EwJob -Id $job.Id } | Should -Throw '*not found*'
    }

    It 'records a terminating error and a failed state' {
        $job = Start-EwJob -ScriptBlock { throw 'job failure example' }
        $job = Wait-TestJob -Id $job.Id
        $job.State | Should -Be 'Failed'
        "$($job.TerminatingError) $($job.Errors)" | Should -Match 'job failure example'
        Remove-EwJob -Id $job.Id
    }

    It 'allows progress and log records to be read while the job is running' {
        $ready = [System.Threading.ManualResetEventSlim]::new($false)
        $gate = [System.Threading.ManualResetEventSlim]::new($false)
        $job = $null
        try {
            $job = Start-EwJob -ScriptBlock {
                param($Ready, $Gate)
                Write-Progress -Activity 'Live progress' -Status 'Running'
                Write-Information -MessageData 'live log' -InformationAction Continue
                $Ready.Set()
                $null = $Gate.Wait([TimeSpan]::FromSeconds(10))
            } -ArgumentList @($ready, $gate)
            $ready.Wait([TimeSpan]::FromSeconds(30)) | Should -BeTrue
            $current = Get-EwJob -Id $job.Id
            $current.State | Should -Be 'Running'
            @($current.Progress | Where-Object Activity -eq 'Live progress').Count | Should -Be 1
            @($current.Information | Where-Object MessageData -eq 'live log').Count | Should -Be 1
        }
        finally {
            $gate.Set()
            if ($null -ne $job) {
                $null = Wait-TestJob -Id $job.Id
                Remove-EwJob -Id $job.Id -Confirm:$false
            }
            $ready.Dispose()
            $gate.Dispose()
        }
    }

    It 'stops a running job and requires stopping before removal' {
        $job = Start-EwJob -ScriptBlock { Start-Sleep -Seconds 30 }
        { Remove-EwJob -Id $job.Id } | Should -Throw '*still running*'
        Stop-EwJob -Id $job.Id -WhatIf | Out-Null
        (Get-EwJob -Id $job.Id).State | Should -Not -Be 'Stopped'
        $job = Stop-EwJob -Id $job.Id
        $job.State | Should -Be 'Stopped'
        Remove-EwJob -Id $job.Id
    }

    It 'exposes a state change event when a job is stopped' {
        $job = Start-EwJob -ScriptBlock { Start-Sleep -Seconds 30 }
        $source = 'EvergreenUI-test-' + [guid]::NewGuid().ToString()
        try {
            Register-ObjectEvent -InputObject $job.StateEventSource -EventName InvocationStateChanged -SourceIdentifier $source | Out-Null
            $job = Stop-EwJob -Id $job.Id
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            do {
                $events = @(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue)
                if (@($events | Where-Object { $_.SourceEventArgs.InvocationStateInfo.State -eq 'Stopped' }).Count -gt 0) {
                    break
                }
                Start-Sleep -Milliseconds 50
            } while ([DateTime]::UtcNow -lt $deadline)
            @($events | Where-Object { $_.SourceEventArgs.InvocationStateInfo.State -eq 'Stopped' }).Count | Should -BeGreaterThan 0
        }
        finally {
            Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event
            Remove-EwJob -Id $job.Id -Confirm:$false
        }
    }

    It 'does not start a job under WhatIf' {
        $before = @(Get-EwJob).Count
        Start-EwJob -ScriptBlock { 'not started' } -WhatIf | Should -BeNullOrEmpty
        @(Get-EwJob).Count | Should -Be $before
    }

    It 'limits active workers to four and starts queued work when a slot is freed' {
        $gate = [System.Threading.ManualResetEventSlim]::new($false)
        $started = [System.Threading.CountdownEvent]::new(4)
        $fifthStarted = [System.Threading.ManualResetEventSlim]::new($false)
        $jobs = @()
        try {
            foreach ($index in 1..4) {
                $jobs += Start-EwJob -ScriptBlock {
                    param($Gate, $Started)
                    $null = $Started.Signal()
                    $Gate.Wait()
                } -ArgumentList @($gate, $started)
            }
            $started.Wait([TimeSpan]::FromSeconds(30)) | Should -BeTrue
            $jobs += Start-EwJob -ScriptBlock {
                param($Started)
                $Started.Set()
            } -ArgumentList @($fifthStarted)
            $fifthStarted.Wait([TimeSpan]::FromSeconds(1)) | Should -BeFalse
            $gate.Set()
            $fifthStarted.Wait([TimeSpan]::FromSeconds(30)) | Should -BeTrue
            foreach ($job in $jobs) {
                (Wait-TestJob -Id $job.Id).State | Should -Be 'Completed'
            }

        }
        finally {
            $gate.Set()
            foreach ($job in $jobs) {
                $current = Get-EwJob -Id $job.Id
                if ($current.State -notin @('Completed', 'Failed', 'Stopped')) {
                    $current = Stop-EwJob -Id $job.Id
                }
                Remove-EwJob -Id $current.Id -Confirm:$false
            }
            $gate.Dispose()
            $started.Dispose()
            $fifthStarted.Dispose()
        }
    }

    It 'cancels a queued job without executing it' {
        $gate = [System.Threading.ManualResetEventSlim]::new($false)
        $started = [System.Threading.CountdownEvent]::new(4)
        $queuedRan = [System.Threading.ManualResetEventSlim]::new($false)
        $jobs = @()
        try {
            foreach ($index in 1..4) {
                $jobs += Start-EwJob -ScriptBlock {
                    param($Gate, $Started)
                    $null = $Started.Signal()
                    $null = $Gate.Wait([TimeSpan]::FromSeconds(15))
                } -ArgumentList @($gate, $started)
            }
            $started.Wait([TimeSpan]::FromSeconds(30)) | Should -BeTrue
            $queued = Start-EwJob -ScriptBlock {
                param($Ran)
                $Ran.Set()
            } -ArgumentList @($queuedRan)
            $jobs += $queued
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $stopped = Stop-EwJob -Id $queued.Id
            $watch.Stop()
            $stopped.State | Should -Be 'Stopped'
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 5
            $queuedRan.IsSet | Should -BeFalse
        }
        finally {
            $gate.Set()
            foreach ($job in $jobs) {
                $null = Wait-TestJob -Id $job.Id
                Remove-EwJob -Id $job.Id -Confirm:$false
            }
            $gate.Dispose()
            $started.Dispose()
            $queuedRan.Dispose()
        }
    }

    It 'stops active jobs when the module is removed' {
        $started = [System.Threading.ManualResetEventSlim]::new($false)
        try {
            $job = Start-EwJob -ScriptBlock {
                param($Started)
                $Started.Set()
                Start-Sleep -Seconds 30
            } -ArgumentList @($started)
            $started.Wait([TimeSpan]::FromSeconds(30)) | Should -BeTrue
            Remove-Module -Name EvergreenUI -ErrorAction Stop
            $job.StateEventSource.InvocationStateInfo.State | Should -Be 'Stopped'
        }
        finally {
            $started.Dispose()
            Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
        }
    }
}

Describe 'Workbench logging' {
    It 'emits a structured information record with the formatted message' {
        InModuleScope EvergreenUI {
            $records = @(Write-EwLog -Message 'Operation complete' -Level Warning 6>&1)
            $entry = $records[0].MessageData
            $entry.Level | Should -Be 'Warning'
            $entry.Message | Should -Be 'Operation complete'
            $entry.Text | Should -Match '^\[\d{2}:\d{2}:\d{2}\] \[WARN\] Operation complete$'
        }
    }
}
