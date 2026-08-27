#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Register-UpdateFeature' -Tag 'Unit' {
    It 'Starts Update-Evergreen from the delayed button callback' {
        $syncHash = InModuleScope EvergreenUI {
            function Get-MockWpfControl {
                param([hashtable]$Property = @{})

                $control = [PSCustomObject]$Property
                $control | Add-Member -MemberType ScriptMethod -Name add_Click -Value {
                    param($Handler)
                    $this.ClickHandler = $Handler
                } -Force
                return $control
            }

            $updateButton = Get-MockWpfControl -Property @{ IsEnabled = $true; ClickHandler = $null }
            $syncHash = [hashtable]::Synchronized(@{
                    RunUpdateEvergreenButton         = $updateButton
                    TestCompletionAction             = $null
                    TestBackgroundOperationRegistered = $false
                    UpdateOutputScrollViewer         = $null
                    UpdateOutputTextBox              = Get-MockWpfControl -Property @{ Text = 'previous output' }
                    UpdateStatusLabel                = Get-MockWpfControl -Property @{ Text = 'Ready' }
                    Window                           = $null
                })
            $syncHash['WriteUpdateOutput'] = {
                param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info')
                [void]$SyncHash
                [void]$Message
                [void]$Level
            }

            $controls = @{
                RunUpdateEvergreenButton = $updateButton
                UpdateOutputScrollViewer = $syncHash.UpdateOutputScrollViewer
                UpdateOutputTextBox      = $syncHash.UpdateOutputTextBox
                UpdateStatusLabel        = $syncHash.UpdateStatusLabel
            }

            $registerBackgroundOperation = {
                param(
                    [string]$Feature,
                    [string]$OperationId,
                    [System.Management.Automation.PowerShell]$PowerShellInstance,
                    [System.Management.Automation.Runspaces.Runspace]$RunspaceInstance,
                    [scriptblock]$CompletionAction,
                    [object]$CallbackState
                )
                [void]$CallbackState
                $SyncHash.TestBackgroundOperationRegistered = $true
                    $SyncHash.TestCompletionAction = $CompletionAction
                $PowerShellInstance.Dispose()
                $RunspaceInstance.Dispose()
                throw ('REGISTERED:{0}:{1}' -f $Feature, $OperationId)
            }

            Register-UpdateFeature -SyncHash $syncHash -Controls $controls -RegisterBackgroundOperation $registerBackgroundOperation
            return $syncHash
        }

        { & $syncHash.RunUpdateEvergreenButton.ClickHandler } | Should -Throw '*REGISTERED:Update:Evergreen*'
        $syncHash.TestBackgroundOperationRegistered | Should -BeTrue
        $syncHash['IsRunning'] | Should -BeTrue
        $syncHash.RunUpdateEvergreenButton.IsEnabled | Should -BeFalse
        $syncHash.UpdateOutputTextBox.Text | Should -Be ''
        $syncHash.UpdateStatusLabel.Text | Should -Be 'Updating Evergreen apps cache...'

        $result = [PSCustomObject]@{
            Error  = $null
            Output = @([PSCustomObject]@{
                    Succeeded = $true
                    Messages  = @('updated')
                    Error     = ''
                })
        }
        { & $syncHash.TestCompletionAction -Operation $null -Result $result -State $null } | Should -Not -Throw
        $syncHash['IsRunning'] | Should -BeFalse
        $syncHash.RunUpdateEvergreenButton.IsEnabled | Should -BeTrue
        $syncHash.UpdateStatusLabel.Text | Should -Be 'Update complete.'
    }
}
