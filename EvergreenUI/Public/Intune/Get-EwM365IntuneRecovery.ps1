Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365IntuneRecovery {
    <#
    .SYNOPSIS
        Lists unresolved Microsoft 365 Intune publishing outcomes.
    .DESCRIPTION
        Returns non-secret records for the currently connected Graph tenant.
    .EXAMPLE
        Get-EwM365IntuneRecovery
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Assert-EwModule -Name Microsoft.Graph.Authentication
    $context = Get-MgContext -ErrorAction Stop
    if ($null -eq $context -or [string]::IsNullOrWhiteSpace([string]$context.TenantId)) {
        throw 'An active Intune tenant is required to review outcomes.'
    }
    $state = Invoke-EwM365IntuneRecoveryStore -Action Read
    foreach ($record in @($state.Operations)) {
        if ([string]$record.TenantId -ieq [string]$context.TenantId) {
            [PSCustomObject]$record
        }
    }
}
