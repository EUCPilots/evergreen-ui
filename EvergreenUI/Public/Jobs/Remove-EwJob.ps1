Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-EwJob {
    <#
    .SYNOPSIS
        Removes a completed Workbench job from the session.
    .DESCRIPTION
        Releases the stored output and stream records of a finished job.
        Running jobs must be stopped before they can be removed.
    .PARAMETER Id
        The ID of the finished job to remove.
    .EXAMPLE
        Remove-EwJob -Id $job.Id
    .OUTPUTS
        None.
    .NOTES
        This does not undo changes made by the job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
        if (-not $job.Handle.IsCompleted) {
            throw "Job '$Id' is still running. Stop it before removing it."
        }
        if ($PSCmdlet.ShouldProcess($Id.ToString(), 'Remove background job')) {
            $null = Get-EwJobSnapshot -Job $job
            $script:ewJobs.Remove($key)
            Write-Verbose -Message "EvergreenUI: Removed job $Id"
        }
    }
}
