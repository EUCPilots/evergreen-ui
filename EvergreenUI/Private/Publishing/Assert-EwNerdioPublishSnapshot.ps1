Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwNerdioPublishSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Snapshot
    )

    Assert-EwNerdioDestination -Destination $Snapshot.Destination
    $plan = Get-EwNerdioPublishPlan -DefinitionPath $Snapshot.DefinitionRoot
    $rows = @($plan.Items | Where-Object { $_.DefinitionPath -eq $Snapshot.Item.DefinitionPath })
    if ($rows.Count -ne 1 -or -not $rows[0].Eligible) {
        throw 'The selected Nerdio definition is no longer eligible. Compare again.'
    }
    foreach ($name in 'DefinitionHash', 'SourceVersion', 'SourceURI', 'NerdioAppId', 'NerdioVersion', 'Operation', 'Publisher', 'AppName') {
        if ([string]$rows[0].$name -cne [string]$Snapshot.Item.$name) {
            throw "The confirmed Nerdio $name changed. Compare and confirm again."
        }
    }
}
