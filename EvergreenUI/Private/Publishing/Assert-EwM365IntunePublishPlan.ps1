Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwM365IntunePublishPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Plan)

    if ($Plan.BuildPlan.Provider -ne 'Intune') { throw 'The preview is not for Intune.' }
    Assert-EwM365BuildPlan -Plan $Plan.BuildPlan
    Assert-EwM365UninstallConfiguration -Path (Join-Path -Path $Plan.BuildPlan.ConfigurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml')
    $matchedApps = @(Get-EwM365IntuneMatch -ConfigurationId $Plan.BuildPlan.ConfigurationId)
    $before = ConvertTo-Json -InputObject @($Plan.Matches) -Depth 5 -Compress
    $after = ConvertTo-Json -InputObject $matchedApps -Depth 5 -Compress
    if ($before -cne $after) { throw 'The Intune matches changed. Preview and confirm again.' }
    if ($Plan.PreviousAppId -and @($matchedApps | Where-Object { $_.Id -eq $Plan.PreviousAppId }).Count -ne 1) {
        throw 'The selected supersedence target could not be verified.'
    }
    Assert-EwM365BuildPlan -Plan $Plan.BuildPlan
}
