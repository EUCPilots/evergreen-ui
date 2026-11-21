Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet(
            'Apps',
            'Artifacts',
            'Downloads',
            'Library',
            'LibraryUpdate',
            'PackageDefinitions',
            'DefinitionUpdate',
            'InstallDefinitions',
            'InstallVersions',
            'InstallPackages'
        )]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @()
    )

    if ($null -ne $State.ActiveJobId) {
        Write-EwWorkbenchLog -State $State -Message 'Wait for the current operation to finish.' -Level Warning
        return
    }
    $job = Start-EwJob -Name $Name -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $State.ActiveJobId = $job.Id
    $State.ActiveJobKind = $Kind
    $State.ProgressReadIndex = 0
    $State.InformationReadIndex = 0
    $State.ErrorReadIndex = 0
    Invoke-EwWorkbenchBusyState -State $State -IsBusy $true
    Write-EwWorkbenchLog -State $State -Message "$Name started." -Level Cmd
}
