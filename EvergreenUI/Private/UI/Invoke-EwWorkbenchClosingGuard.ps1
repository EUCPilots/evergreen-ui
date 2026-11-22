Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchClosingGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][System.ComponentModel.CancelEventArgs]$ClosingArgs
    )

    if ($State.ActiveJobKind -in @('EvergreenUpdate', 'CacheClear') -or $State.MaintenancePromptActive) {
        $ClosingArgs.Cancel = $true
        Write-EwWorkbenchLog -State $State -Message 'Wait for Workbench maintenance to finish before closing.' -Level Warning
    }
    elseif ($State.ActiveJobKind -in @('IntunePublish', 'IntuneRetry', 'NerdioPublish')) {
        $ClosingArgs.Cancel = $true
        Write-EwWorkbenchLog -State $State -Message 'Wait for the current provider write to finish before closing. A batch can be cancelled between items.' -Level Warning
    }
}
