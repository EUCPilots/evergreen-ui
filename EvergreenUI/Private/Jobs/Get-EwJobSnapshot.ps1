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

    [PSCustomObject]@{
        Id = $Job.Id
        Name = $Job.Name
        State = if ($Job.Finalized) { $Job.State } else { [string]$Job.PowerShell.InvocationStateInfo.State }
        Output = $Job.Output
        Errors = $Job.Errors
        TerminatingError = $Job.TerminatingError
        Progress = $Job.Progress
        Information = $Job.Information
        StateEventSource = $Job.PowerShell
    }
}
