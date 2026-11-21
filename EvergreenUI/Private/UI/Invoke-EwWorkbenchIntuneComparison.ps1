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
        $items = foreach ($row in Compare-EwIntuneApp -DefinitionPath $DefinitionRoot) {
            $definitionHash = ''
            $installHash = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$row.DefinitionPath) -and
                (Test-Path -LiteralPath $row.DefinitionPath -PathType Leaf)) {
                $definitionHash = (Get-FileHash -LiteralPath $row.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
                $installPath = Join-Path -Path (Split-Path -Path $row.DefinitionPath -Parent) -ChildPath 'Source\Install.json'
                if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                    $installHash = (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
                }
            }
            $row | Add-Member -NotePropertyName DefinitionHash -NotePropertyValue $definitionHash
            $row | Add-Member -NotePropertyName InstallHash -NotePropertyValue $installHash
            $row | Add-Member -NotePropertyName ImportAsUpdate -NotePropertyValue $false
            $row
        }
        [PSCustomObject]@{ DefinitionRoot = $DefinitionRoot; Items = @($items) }
    }
}
