Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365IntunePublishPlan {
    <#
    .SYNOPSIS
        Previews a Microsoft 365 Intune app creation.
    .DESCRIPTION
        Checks the confirmed build inputs, existing configuration-ID matches,
        optional supersedence target and unresolved recovery records.
    .PARAMETER BuildPlan
        Intune preview from Get-EwM365BuildPlan.
    .PARAMETER PreviousAppId
        Optional existing matching Intune app to supersede with an update relationship.
    .EXAMPLE
        Get-EwM365IntunePublishPlan -BuildPlan $buildPlan
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Matching is rechecked but is not an atomic Graph lock.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][psobject]$BuildPlan,
        [string]$PreviousAppId
    )

    if ($BuildPlan.Provider -ne 'Intune') { throw 'The build preview must target Intune.' }
    Assert-EwM365BuildPlan -Plan $BuildPlan
    Assert-EwM365UninstallConfiguration -Path (Join-Path -Path $BuildPlan.ConfigurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml')
    $recovery = Invoke-EwM365IntuneRecoveryStore -Action Read
    if (@($recovery.Operations | Where-Object {
                $_.TenantId -ieq $BuildPlan.TenantId -and $_.ConfigurationId -ieq $BuildPlan.ConfigurationId
            }).Count -gt 0) {
        throw 'A previous Microsoft 365 Intune outcome needs explicit review before another write.'
    }
    $matchedApps = @(Get-EwM365IntuneMatch -ConfigurationId $BuildPlan.ConfigurationId)
    if ($PreviousAppId -and @($matchedApps | Where-Object { $_.Id -eq $PreviousAppId }).Count -ne 1) {
        throw 'Select an existing matching Intune app to supersede.'
    }
    $plan = [PSCustomObject]@{ BuildPlan = $BuildPlan; Matches = $matchedApps; PreviousAppId = [string]$PreviousAppId }
    Assert-EwM365IntunePublishPlan -Plan $plan
    return $plan
}
