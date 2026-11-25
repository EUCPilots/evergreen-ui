Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwNerdioRecoveryDestination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Destination
    )

    $current = Get-EwNerdioDestinationIdentity -Context $Context
    foreach ($name in $current.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$Destination[$name]) -or
            [string]::IsNullOrWhiteSpace([string]$current[$name])) {
            throw 'The Nerdio recovery destination is incomplete; reconnect and verify the configured destination.'
        }
        if ([string]$Destination[$name] -ine [string]$current[$name]) {
            throw 'Reconnect to the Nerdio and Azure destination recorded for this operation before resuming it.'
        }
    }
}
