#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Register-UIFeatures background operation registration' -Tag 'Unit' {
    It 'Starts the shared polling timer after registering background work' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        InModuleScope EvergreenUI {
            Add-Type -AssemblyName WindowsBase -ErrorAction Stop

            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            $syncHash['InitializeFeatureScopedState'] = ${function:Initialize-FeatureScopedState}.GetNewClosure()
            $syncHash['StartBackgroundOperation'] = ${function:Start-BackgroundOperation}.GetNewClosure()
            $syncHash['InvokeBackgroundOperationPoll'] = ${function:Invoke-BackgroundOperationPoll}.GetNewClosure()
            $syncHash['WriteUILog'] = {
                param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info')
                [void]$SyncHash
                [void]$Message
                [void]$Level
            }
            $syncHash['EnsureBackgroundOperationPolling'] = {
                if (-not $syncHash.ContainsKey('Operations')) {
                    & ($syncHash['InitializeFeatureScopedState']) -SyncHash $syncHash
                }

                if ($null -eq $syncHash.Operations.PollingTimer) {
                    $timer = [System.Windows.Threading.DispatcherTimer]::new()
                    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
                    $timer.add_Tick({
                            [void](& ($syncHash['InvokeBackgroundOperationPoll']) -Operations $syncHash.Operations.Registry)
                            $syncHash.Operations.ActiveCount = $syncHash.Operations.Registry.Count
                            $syncHash.Operations.LastPolledAt = Get-Date
                            if ($syncHash.Operations.Registry.Count -eq 0) {
                                $syncHash.Operations.PollingTimer.Stop()
                            }
                        }.GetNewClosure())
                    $syncHash.Operations.PollingTimer = $timer
                }

                if (-not $syncHash.Operations.PollingTimer.IsEnabled) {
                    $syncHash.Operations.PollingTimer.Start()
                }
            }.GetNewClosure()
            $registerBackgroundOperation = {
                param(
                    [Parameter(Mandatory)]
                    [string]$Feature,

                    [Parameter(Mandatory)]
                    [string]$OperationId,

                    [Parameter(Mandatory)]
                    [System.Management.Automation.PowerShell]$PowerShellInstance,

                    [Parameter(Mandatory)]
                    [System.Management.Automation.Runspaces.Runspace]$RunspaceInstance,

                    [scriptblock]$CompletionAction,

                    [object]$CallbackState
                )

                & ($syncHash['StartBackgroundOperation']) -Operations $syncHash.Operations.Registry -Feature $Feature `
                    -OperationId $OperationId -PowerShell $PowerShellInstance -Runspace $RunspaceInstance `
                    -CompletionAction $CompletionAction -CallbackState $CallbackState
                & ($syncHash['EnsureBackgroundOperationPolling'])
            }.GetNewClosure()

            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $powershell = [powershell]::Create()
            $powershell.Runspace = $runspace
            [void]$powershell.AddScript({ 'done' })

            try {
                & $registerBackgroundOperation -Feature 'Load' -OperationId 'Evergreen' `
                    -PowerShellInstance $powershell -RunspaceInstance $runspace

                $syncHash.Operations.Registry.ContainsKey('Load::Evergreen') | Should -BeTrue
                $syncHash.Operations.PollingTimer | Should -Not -BeNullOrEmpty
                $syncHash.Operations.PollingTimer.IsEnabled | Should -BeTrue
            }
            finally {
                if ($null -ne $syncHash.Operations.PollingTimer) {
                    $syncHash.Operations.PollingTimer.Stop()
                }
                Clear-BackgroundOperation -Operations $syncHash.Operations.Registry
            }
        }
    }
}
