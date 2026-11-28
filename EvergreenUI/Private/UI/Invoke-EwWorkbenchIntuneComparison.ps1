Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchIntuneComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $root = [string]$State.Settings.IntuneDefinitionsPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'Save an Intune Definitions folder in Packages before comparing.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.IntuneTenantId)) {
        throw 'Connect to Intune before comparing.'
    }
    Invoke-EwWorkbenchJob -State $State -Kind 'IntuneCompare' -Name 'Compare Intune apps' `
        -ArgumentList @($root, [string]$State.IntuneTenantId) -ScriptBlock {
        param($DefinitionRoot, $TenantId)
        Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
        $context = Get-MgContext -ErrorAction Stop
        if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
            throw 'The confirmed Intune connection is not available in the background worker.'
        }
        $items = @(Compare-EwIntuneApp -DefinitionPath $DefinitionRoot -DefinitionView)
        [PSCustomObject]@{ DefinitionRoot = $DefinitionRoot; Items = @($items) }
    }
}
