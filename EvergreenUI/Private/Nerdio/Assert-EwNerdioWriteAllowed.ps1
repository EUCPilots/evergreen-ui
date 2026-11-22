Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwNerdioWriteAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter()]
        [string]$ShellAppId
    )

    $destination = Get-EwNerdioDestinationIdentity -Context $Context
    $state = Invoke-EwNerdioRecoveryStore -Action Read
    foreach ($operation in @($state.Operations)) {
        $matchesDestination = $true
        foreach ($name in $destination.Keys) {
            if ([string]$operation.Destination[$name] -ine [string]$destination[$name]) {
                $matchesDestination = $false
                break
            }
        }
        if (-not $matchesDestination) { continue }
        if ($operation.Type -eq 'Publish' -or
            ($operation.Type -eq 'Delete' -and $ShellAppId -and [string]$operation.AppId -eq $ShellAppId)) {
            throw "A Nerdio $($operation.Type.ToLowerInvariant()) outcome for '$($operation.Name)' version '$($operation.Version)' needs review before another write."
        }
    }
}
