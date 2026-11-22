Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-EwJob {
    <#
    .SYNOPSIS
        Starts a headless operation in the shared runspace pool.
    .DESCRIPTION
        Starts a job in a pool of up to four runspaces. By default, the module
        is imported in the worker. Script blocks are recreated in the worker
        and do not capture caller variables; pass values through ArgumentList.
        Get-EwJob exposes progress and information streams and final output.
    .PARAMETER ScriptBlock
        The operation to run in the worker.
    .PARAMETER ArgumentList
        Positional arguments passed to the operation.
    .PARAMETER Name
        A descriptive name for the job.
    .PARAMETER NoModuleImport
        Does not automatically import EvergreenUI in the worker. A reused
        runspace may still contain modules loaded by earlier jobs.
    .EXAMPLE
        Start-EwJob -ScriptBlock { param($Name) "Hello $Name" } -ArgumentList 'World'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Runspace jobs are in-process and are stopped when the module is removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @(),

        [ValidateNotNullOrEmpty()]
        [string]$Name = 'Evergreen Workbench job',

        [switch]$NoModuleImport
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Start background job')) {
        return
    }

    if ($null -eq $script:ewRunspacePool) {
        Write-Verbose -Message 'EvergreenUI: Creating background runspace pool'
        $pool = [runspacefactory]::CreateRunspacePool(1, 4)
        try {
            $pool.Open()
            $script:ewRunspacePool = $pool
        }
        catch {
            $pool.Dispose()
            throw
        }
    }

    $powerShell = [powershell]::Create()
    $powerShell.RunspacePool = $script:ewRunspacePool
    $powerShell.Streams.Error.BlockingEnumerator = $false
    $powerShell.Streams.Progress.BlockingEnumerator = $false
    $powerShell.Streams.Information.BlockingEnumerator = $false
    $worker = {
        param($ModulePath, $Body, $Arguments, $NerdioSession, $SkipImport)
        $ErrorActionPreference = 'Stop'
        if (-not $SkipImport) {
            Import-Module -Name $ModulePath -ErrorAction Stop
            & (Get-Module -Name EvergreenUI) {
                param($Session)
                $script:ewNerdioSession = $Session
                $script:ewOwnsNerdioSession = $false
            } $NerdioSession
        }
        & ([scriptblock]::Create($Body)) @Arguments
    }
    try {
        $null = $powerShell.AddScript($worker.ToString()).AddArgument($script:ewModulePath).AddArgument($ScriptBlock.ToString()).AddArgument($ArgumentList).AddArgument($script:ewNerdioSession).AddArgument([bool]$NoModuleImport)
        $handle = $powerShell.BeginInvoke()
    }
    catch {
        $powerShell.Dispose()
        throw
    }

    $id = [guid]::NewGuid()
    $job = @{
        Id = $id
        Name = $Name
        PowerShell = $powerShell
        Handle = $handle
        State = 'Running'
        Finalized = $false
        Output = @()
        Errors = $powerShell.Streams.Error
        Progress = $powerShell.Streams.Progress
        Information = $powerShell.Streams.Information
        TerminatingError = $null
    }
    $script:ewJobs[$id.ToString()] = $job
    Write-Verbose -Message "EvergreenUI: Started job $id ($Name)"
    Get-EwJobSnapshot -Job $job
}
