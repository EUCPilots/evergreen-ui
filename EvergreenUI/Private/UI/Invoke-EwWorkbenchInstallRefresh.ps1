Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInstallRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$Force
    )

    if (-not $State.Contains('InstallDefinitionsStale') -or -not $State.InstallDefinitionsStale) {
        return
    }
    if (-not $Force -and (-not $State.InstallTab.IsSelected -or
            $State.PackagesPanel.Visibility -ne [System.Windows.Visibility]::Visible)) {
        return
    }
    if ($null -ne $State.ActiveJobId -or $State.InstallBatchActive) {
        $State.InstallRefreshPending = $true
        $State.InstallActionStatusLabel.Text = 'Local detection refresh pending. Waiting for the current operation to finish.'
        return
    }
    $State.InstallRefreshPending = $false
    if ([string]::IsNullOrWhiteSpace([string]$State.IntuneDefinitionsPathBox.Text)) {
        $State.InstallActionStatusLabel.Text = 'Set the definitions folder on the Definitions tab, then reload.'
        return
    }
    $State.InstallRefreshRevision = $State.InstallDefinitionsRevision
    $State.InstallActionStatusLabel.Text = 'Refreshing definitions and local detection...'
    Write-Verbose -Message 'EvergreenUI: Refreshing local install definitions and detection'
    & $State.LoadInstallDefinitions
}
