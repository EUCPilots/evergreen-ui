Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchIntunePublish {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [bool]$ImportAsUpdate
    )

    $selection = @($State.IntuneComparison | Where-Object { $_.RowType -eq 'Definition' -and $_.IsSelected })
    if ($selection.Count -eq 0) { throw 'Select at least one definition using its checkbox.' }
    foreach ($item in $selection) {
        $blocker = if ($ImportAsUpdate) { $item.UpdateBlocker } else { $item.DeploymentBlocker }
        if ($blocker) { throw "Cannot import '$($item.DefinitionName)': $blocker" }
    }
    $root = [string]$State.IntuneComparisonRoot
    $working = [string]$State.Settings.PackageOutputPath
    if (-not $working) { $working = [string]$State.Settings.OutputPath }
    if (-not $root -or -not $working) { throw 'Save the Definition and package output paths in Packages first.' }
    if ($root -ne [string]$State.Settings.IntuneDefinitionsPath) { throw 'The saved Definitions folder changed. Compare again before importing.' }
    $State.IntunePendingPublish = [PSCustomObject]@{
        Root = $root; WorkingPath = $working; TenantId = [string]$State.IntuneTenantId; ImportAsUpdate = $ImportAsUpdate
    }
    Invoke-EwWorkbenchJob -State $State -Kind 'IntuneReview' -Name 'Review Intune import plan' `
        -ArgumentList @($root, [object[]]$selection, $ImportAsUpdate, [string]$State.IntuneTenantId) -ScriptBlock {
        param($Root, $Selection, $Update, $TenantId)
        Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
        $context = Get-MgContext -ErrorAction Stop
        if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
            throw 'The confirmed Intune connection is no longer active.'
        }
        & (Get-Module -Name EvergreenUI) {
            param($DefinitionRoot, $Items, $AsUpdate)
            Get-EwIntunePublishReview -DefinitionPath $DefinitionRoot -Selection $Items -ImportAsUpdate $AsUpdate
        } $Root $Selection $Update
    }
}
