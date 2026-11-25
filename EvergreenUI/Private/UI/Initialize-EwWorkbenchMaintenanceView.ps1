Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchMaintenanceView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    foreach ($entry in @(
            @{ Control = $State.ReloadAppVersionsButton; Action = 'ReloadVersions' },
            @{ Control = $State.UpdateEvergreenButton; Action = 'Update' },
            @{ Control = $State.ClearWorkbenchCacheButton; Action = 'Clear' },
            @{ Control = $State.OpenCacheFolderButton; Action = 'Open' }
        )) {
        $action = $entry.Action
        $entry.Control.Add_Click({
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchMaintenanceAction' -Parameters @{ State = $State; Action = $action }
        }.GetNewClosure())
    }
}
