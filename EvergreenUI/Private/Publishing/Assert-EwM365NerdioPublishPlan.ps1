Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwM365NerdioPublishPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Plan)

    if ($Plan.BuildPlan.Provider -ne 'Nerdio') { throw 'The preview is not for Nerdio.' }
    Assert-EwM365BuildPlan -Plan $Plan.BuildPlan
    $target = Get-EwM365NerdioTarget -Destination $Plan.Destination -Operation $Plan.Operation `
        -Name $Plan.Name -ShellAppId $Plan.ShellAppId
    foreach ($name in 'Id', 'Name', 'Publisher') {
        if ([string]$target.$name -cne [string]$Plan.Target.$name) {
            throw "The confirmed Nerdio target $name changed. Preview and confirm again."
        }
    }
    if ((@($target.Versions) | ConvertTo-Json -Compress) -cne (@($Plan.Target.Versions) | ConvertTo-Json -Compress)) {
        throw 'The confirmed Nerdio target versions changed. Preview and confirm again.'
    }
    $officeVersion = [version]'0.0'
    if (-not [version]::TryParse([string]$Plan.BuildPlan.OfficeVersion, [ref]$officeVersion)) {
        throw 'The confirmed Office channel version is invalid.'
    }
    $matchingVersions = @($target.Versions | Where-Object {
            $remoteVersion = [version]'0.0'
            [version]::TryParse([string]$_, [ref]$remoteVersion) -and $remoteVersion -eq $officeVersion
        })
    if ($Plan.Operation -eq 'Add version' -and $matchingVersions.Count -gt 0 -and -not $Plan.SameVersionAttested) {
        throw 'The Office version already exists. Attest that the configuration changed before publishing.'
    }
    Assert-EwM365BuildPlan -Plan $Plan.BuildPlan
}
