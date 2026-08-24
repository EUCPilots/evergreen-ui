#Requires -Version 5.1

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Background operation lifecycle' -Tag 'Unit' {
    InModuleScope EvergreenUI {
        BeforeEach {
            $script:operations = [hashtable]::Synchronized(@{})
        }

        AfterEach {
            Clear-BackgroundOperation -Operations $script:operations
        }

        It 'Completes an operation and passes callback state' {
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $powershell = [powershell]::Create()
            $powershell.Runspace = $runspace
            [void]$powershell.AddScript({ 'completed output' })
            $callbackState = [PSCustomObject]@{ Called = $false; Value = '' }
            $completionAction = {
                param($Operation, $Result, $State)
                $State.Called = $true
                $State.Value = $Result.Output[0]
            }

            $operation = Start-BackgroundOperation -Operations $script:operations -Feature 'Update' -OperationId 'Evergreen' -PowerShell $powershell -Runspace $runspace -CompletionAction $completionAction -CallbackState $callbackState
            [void]$operation.AsyncResult.AsyncWaitHandle.WaitOne(5000)
            $result = Complete-BackgroundOperation -Operations $script:operations -Key $operation.Key

            $result.Status | Should -Be 'Completed'
            $callbackState.Called | Should -BeTrue
            $callbackState.Value | Should -Be 'completed output'
            $script:operations.Count | Should -Be 0
        }

        It 'Rejects a second active operation for the same feature' {
            $firstRunspace = [runspacefactory]::CreateRunspace()
            $firstRunspace.Open()
            $firstPowerShell = [powershell]::Create()
            $firstPowerShell.Runspace = $firstRunspace
            [void]$firstPowerShell.AddScript({ while ($true) { Start-Sleep -Milliseconds 50 } })
            [void](Start-BackgroundOperation -Operations $script:operations -Feature 'Install' -OperationId 'First' -PowerShell $firstPowerShell -Runspace $firstRunspace)

            $secondRunspace = [runspacefactory]::CreateRunspace()
            $secondRunspace.Open()
            $secondPowerShell = [powershell]::Create()
            $secondPowerShell.Runspace = $secondRunspace
            [void]$secondPowerShell.AddScript({ 'unused' })

            { Start-BackgroundOperation -Operations $script:operations -Feature 'Install' -OperationId 'Second' -PowerShell $secondPowerShell -Runspace $secondRunspace } | Should -Throw '*already has an active background operation*'
            $secondPowerShell.Dispose()
            $secondRunspace.Dispose()
        }

        It 'Allows unrelated features to run concurrently and clears both' {
            foreach ($feature in @('Download', 'Update')) {
                $runspace = [runspacefactory]::CreateRunspace()
                $runspace.Open()
                $powershell = [powershell]::Create()
                $powershell.Runspace = $runspace
                [void]$powershell.AddScript({ while ($true) { Start-Sleep -Milliseconds 50 } })
                [void](Start-BackgroundOperation -Operations $script:operations -Feature $feature -OperationId 'Run' -PowerShell $powershell -Runspace $runspace)
            }

            $script:operations.Count | Should -Be 2
            Clear-BackgroundOperation -Operations $script:operations
            $script:operations.Count | Should -Be 0
        }

        It 'Polls completed operations while leaving running operations registered' {
            $completedRunspace = [runspacefactory]::CreateRunspace()
            $completedRunspace.Open()
            $completedPowerShell = [powershell]::Create()
            $completedPowerShell.Runspace = $completedRunspace
            [void]$completedPowerShell.AddScript({ 'done' })
            $completedOperation = Start-BackgroundOperation -Operations $script:operations -Feature 'Update' -OperationId 'Completed' -PowerShell $completedPowerShell -Runspace $completedRunspace

            $runningRunspace = [runspacefactory]::CreateRunspace()
            $runningRunspace.Open()
            $runningPowerShell = [powershell]::Create()
            $runningPowerShell.Runspace = $runningRunspace
            [void]$runningPowerShell.AddScript({ while ($true) { Start-Sleep -Milliseconds 50 } })
            $runningOperation = Start-BackgroundOperation -Operations $script:operations -Feature 'Download' -OperationId 'Running' -PowerShell $runningPowerShell -Runspace $runningRunspace

            [void]$completedOperation.AsyncResult.AsyncWaitHandle.WaitOne(5000)
            $results = @(Invoke-BackgroundOperationPoll -Operations $script:operations)

            $results | Should -HaveCount 1
            $results[0].OperationId | Should -Be 'Completed'
            $script:operations.ContainsKey($completedOperation.Key) | Should -BeFalse
            $script:operations.ContainsKey($runningOperation.Key) | Should -BeTrue
        }
    }
}