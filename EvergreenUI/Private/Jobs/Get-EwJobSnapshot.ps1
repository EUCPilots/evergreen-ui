Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwJobSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Job
    )

    if (-not $Job.Finalized -and $Job.Handle.IsCompleted) {
        try {
            $Job.Output = @($Job.PowerShell.EndInvoke($Job.Handle))
        }
        catch {
            $Job.TerminatingError = $_
        }
        finally {
            $Job.State = [string]$Job.PowerShell.InvocationStateInfo.State
            $Job.Finalized = $true
            $Job.PowerShell.Dispose()
        }
    }

    $state = if ($Job.Finalized) { $Job.State } else { [string]$Job.PowerShell.InvocationStateInfo.State }
    if (-not $Job.Finalized -and $state -in @('Completed', 'Failed', 'Stopped', 'Disconnected')) {
        # PowerShell can report a terminal state before the async handle completes; output is not yet available.
        Write-Verbose -Message "EvergreenUI: Job $($Job.Id) reports $state before its handle completed; awaiting finalization."
        $state = if ($state -eq 'Stopped') { 'Stopping' } else { 'Running' }
    }

    [PSCustomObject]@{
        Id = $Job.Id
        Name = $Job.Name
        State = $state
        Output = $Job.Output
        Errors = $Job.Errors
        TerminatingError = $Job.TerminatingError
        Progress = $Job.Progress
        Information = $Job.Information
        StateEventSource = $Job.PowerShell
    }
}
