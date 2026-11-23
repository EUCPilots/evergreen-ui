Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInstallStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    if (-not $State.Contains('InstallDefinitionsStale')) {
        return
    }
    if (-not $State.InstallDefinitionsStale) {
        $State.InstallSelectedDefinitionPaths = @($State.InstallDefinitionsListView.SelectedItems |
            ForEach-Object DefinitionPath)
    }
    $State.InstallDefinitionsStale = $true
    $State.InstallDefinitionsRevision++
    $State.InstallDefinitions.Clear()
    $State.InstallDefinitionsCountLabel.Text = 'Definitions need refresh'
    $State.InstallActionStatusLabel.Text = 'Local detection needs refresh. Open Install or reload definitions.'
    $State.ResolveInstallVersionsButton.IsEnabled = $false
    $State.InstallSelectedPackagesButton.IsEnabled = $false
    $State.InstallRefreshPending = $State.InstallTab.IsSelected -and
        $State.PackagesPanel.Visibility -eq [System.Windows.Visibility]::Visible
    if ($State.InstallRefreshPending -and $null -ne $State.ActiveJobId) {
        $State.InstallActionStatusLabel.Text = 'Local detection refresh pending. Waiting for the current operation to finish.'
    }
    Write-Verbose -Message 'EvergreenUI: Invalidated local install definitions and Artifact assessments'
}
