Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Open-EwWorkbenchLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri)

    if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -notin @('http', 'https')) {
        throw 'Only HTTP and HTTPS links can be opened.'
    }
    Write-Verbose -Message "EvergreenUI: Opening Workbench link '$Uri'"
    Start-Process -FilePath $Uri.AbsoluteUri -ErrorAction Stop
    Write-Verbose -Message 'EvergreenUI: Opened Workbench link'
}
