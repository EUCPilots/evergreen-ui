Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioRecovery {
    <#
    .SYNOPSIS
        Lists unresolved Nerdio operations for the connected destination.
    .DESCRIPTION
        Returns recovery metadata without credentials for the connected Nerdio and Azure destination.
    .EXAMPLE
        Get-EwNerdioRecovery
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        An unresolved outcome does not establish whether the provider operation succeeded.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $context = Get-EwNerdioSessionContext
    $destination = Get-EwNerdioDestinationIdentity -Context $context
    foreach ($name in $destination.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$destination[$name])) {
            throw 'Connect to the full Nerdio and Azure storage destination before listing recovery records.'
        }
    }
    foreach ($operation in @((Invoke-EwNerdioRecoveryStore -Action Read).Operations)) {
        $matchesDestination = $true
        foreach ($name in $destination.Keys) {
            if ([string]$operation.Destination[$name] -ine [string]$destination[$name]) {
                $matchesDestination = $false
                break
            }
        }
        if ($matchesDestination) { [PSCustomObject]$operation }
    }
}
