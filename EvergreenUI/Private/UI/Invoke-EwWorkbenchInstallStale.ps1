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
    $State.ResolveInstallVersionsButton.IsEnabled = $false
    $State.InstallSelectedPackagesButton.IsEnabled = $false
    $State.InstallRefreshPending = $State.InstallTab.IsSelected -and
        $State.PackagesPanel.Visibility -eq [System.Windows.Visibility]::Visible
    Write-Verbose -Message 'EvergreenUI: Invalidated local install definitions and Artifact assessments'
}
