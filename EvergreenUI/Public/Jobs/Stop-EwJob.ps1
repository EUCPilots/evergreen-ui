Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-EwJob {
    <#
    .SYNOPSIS
        Stops a Workbench background job.
    .DESCRIPTION
        Requests cancellation of a running or queued job and returns its state.
    .PARAMETER Id
        The ID of the job to stop.
    .EXAMPLE
        Stop-EwJob -Id $job.Id
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Cancellation does not roll back external changes already made by the job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [guid]$Id
    )

    process {
        $key = $Id.ToString()
        if (-not $script:ewJobs.ContainsKey($key)) {
            throw "Job '$Id' was not found in this module session."
        }
        $job = $script:ewJobs[$key]
        if (-not $job.Handle.IsCompleted -and $PSCmdlet.ShouldProcess($Id.ToString(), 'Stop background job')) {
            Write-Verbose -Message "EvergreenUI: Stopping job $Id"
            $job.PowerShell.Stop()
        }
        Get-EwJobSnapshot -Job $job
    }
}
