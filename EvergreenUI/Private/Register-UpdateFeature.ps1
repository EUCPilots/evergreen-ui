function Register-UpdateFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Evergreen app cache update feature.

    .DESCRIPTION
    Wires the Update tab button to run Update-Evergreen in a background runspace
    and writes status/output to the Update tab controls.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Update feature.

    .PARAMETER RegisterBackgroundOperation
    Scriptblock to register background async operations with completion handlers.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls,
        [scriptblock]$RegisterBackgroundOperation
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $runUpdateEvergreenButton = $Controls.RunUpdateEvergreenButton
    $updateOutputTextBox = $Controls.UpdateOutputTextBox
    $updateOutputScrollViewer = $Controls.UpdateOutputScrollViewer
    $updateStatusLabel = $Controls.UpdateStatusLabel

    $SyncHash.RunUpdateEvergreenButton = $runUpdateEvergreenButton
    $SyncHash.UpdateOutputTextBox = $updateOutputTextBox
    $SyncHash.UpdateOutputScrollViewer = $updateOutputScrollViewer
    $SyncHash.UpdateStatusLabel = $updateStatusLabel
    $SyncHash['NewWpfRunspace'] = ${function:New-WpfRunspace}.GetNewClosure()
    $SyncHash['RegisterBackgroundOperation'] = $RegisterBackgroundOperation.GetNewClosure()
    if (-not $SyncHash.ContainsKey('IsRunning')) {
        $SyncHash['IsRunning'] = $false
    }

    if ($null -eq $runUpdateEvergreenButton) {
        Write-Verbose 'EvergreenUI: RunUpdateEvergreenButton not found; Update feature registration skipped.'
        return
    }

    $runUpdateEvergreenButton.add_Click({
            if ($SyncHash.ContainsKey('IsRunning') -and [bool]$SyncHash['IsRunning']) {
                & ($SyncHash['WriteUpdateOutput']) -SyncHash $SyncHash -Message 'Another operation is already running.' -Level Warning
                return
            }

            $SyncHash['IsRunning'] = $true
            $runUpdateEvergreenButton.IsEnabled = $false
            if ($null -ne $updateOutputTextBox) { $updateOutputTextBox.Text = '' }
            if ($null -ne $updateStatusLabel) { $updateStatusLabel.Text = 'Updating Evergreen apps cache...' }

            & ($SyncHash['WriteUpdateOutput']) -SyncHash $SyncHash -Message 'Starting Evergreen apps cache update.' -Level Info
            & ($SyncHash['WriteUpdateOutput']) -SyncHash $SyncHash -Message 'Update-Evergreen' -Level Cmd

            $runspace = & ($SyncHash['NewWpfRunspace']) -SyncHash $SyncHash
            $powershell = [powershell]::Create()
            $powershell.Runspace = $runspace
            [void]$powershell.AddScript({
                    $messages = [System.Collections.Generic.List[string]]::new()
                    try {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                        foreach ($message in @(Update-Evergreen -ErrorAction Stop *>&1)) {
                            if ($null -ne $message) {
                                $messages.Add([string]$message)
                            }
                        }

                        [PSCustomObject]@{
                            Succeeded = $true
                            Messages  = $messages.ToArray()
                            Error     = ''
                        }
                    }
                    catch {
                        [PSCustomObject]@{
                            Succeeded = $false
                            Messages  = $messages.ToArray()
                            Error     = $_.Exception.Message
                        }
                    }
                })

            $updateState = $SyncHash
            $completionAction = {
                param($Operation, $Result, $State)
                [void]$Operation
                [void]$State

                try {
                    if ($Result.Error) {
                        throw $Result.Error
                    }

                    $payload = if ($Result.Output.Count -gt 0) { $Result.Output[-1] } else { $null }
                    if ($null -eq $payload) {
                        throw 'Update-Evergreen did not return a result.'
                    }

                    foreach ($message in @($payload.Messages)) {
                        & ($updateState['WriteUpdateOutput']) -SyncHash $updateState -Message ([string]$message) -Level Info
                    }

                    if ([bool]$payload.Succeeded) {
                        & ($updateState['WriteUpdateOutput']) -SyncHash $updateState -Message 'Evergreen apps cache update completed.' -Level Info
                        if ($null -ne $updateState.UpdateStatusLabel) { $updateState.UpdateStatusLabel.Text = 'Update complete.' }
                    }
                    else {
                        & ($updateState['WriteUpdateOutput']) -SyncHash $updateState -Message "Evergreen apps cache update failed: $($payload.Error)" -Level Error
                        if ($null -ne $updateState.UpdateStatusLabel) { $updateState.UpdateStatusLabel.Text = 'Update failed.' }
                    }
                }
                catch {
                    & ($updateState['WriteUpdateOutput']) -SyncHash $updateState -Message "Evergreen apps cache update failed: $($_.Exception.Message)" -Level Error
                    if ($null -ne $updateState.UpdateStatusLabel) { $updateState.UpdateStatusLabel.Text = 'Update failed.' }
                }
                finally {
                    $updateState['IsRunning'] = $false
                    if ($null -ne $updateState.RunUpdateEvergreenButton) {
                        $updateState.RunUpdateEvergreenButton.IsEnabled = $true
                    }
                }
            }.GetNewClosure()

            & ($SyncHash['RegisterBackgroundOperation']) -Feature 'Update' -OperationId 'Evergreen' `
                -PowerShellInstance $powershell -RunspaceInstance $runspace -CompletionAction $completionAction
        }.GetNewClosure())

    Write-Verbose 'EvergreenUI: Update feature registered.'
}