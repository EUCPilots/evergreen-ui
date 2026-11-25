Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwJob {
    <#
    .SYNOPSIS
        Gets Workbench background jobs.
    .DESCRIPTION
        Returns job state, output and errors. Progress and Information are live
        PSDataCollection streams, whose DataAdded events can be subscribed to.
        StateEventSource exposes InvocationStateChanged, including cancellation.
        Output is available after a job finishes. Calls finalize finished jobs.
    .PARAMETER Id
        The ID of a job to retrieve. Omit to retrieve all jobs in this module session.
    .EXAMPLE
        Get-EwJob -Id $job.Id
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Jobs exist only for the lifetime of the imported module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [guid]$Id
    )

    process {
        if ($PSBoundParameters.ContainsKey('Id')) {
            $key = $Id.ToString()
            if (-not $script:ewJobs.ContainsKey($key)) {
                throw "Job '$Id' was not found in this module session."
            }
            Get-EwJobSnapshot -Job $script:ewJobs[$key]
        }
        else {
            foreach ($job in $script:ewJobs.Values) {
                Get-EwJobSnapshot -Job $job
            }
        }
    }
}
