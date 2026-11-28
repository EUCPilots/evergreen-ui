Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwIntuneComparisonTarget {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates an in-memory comparison, without publishing.')]
    param(
        [Parameter(Mandatory)]
        [object]$Row,

        [Parameter()]
        [string]$AppId = ''
    )

    $target = @($Row.MatchingApps | Where-Object IntuneAppId -EQ $AppId)
    if ($AppId -and $target.Count -ne 1) { throw 'The selected predecessor is not a unique match for this definition.' }
    $Row.IntuneAppId = $AppId
    $Row.IntuneDisplayName = if ($target.Count -eq 1) { [string]$target[0].DisplayName } else { 'Not selected' }
    $Row.IntuneVersion = if ($target.Count -eq 1) { [string]$target[0].DisplayVersion } else { 'Not imported' }
    $Row.Readiness = 'Needs review'
    $Row.MatchStatus = 'Matched (needs review)'
    $Row.DeploymentBlocker = [string]$Row.ComparisonError
    $Row.UpdateBlocker = ''
    if (-not $Row.DeploymentBlocker) {
        $latest = ConvertTo-EwComparableVersion -Version $Row.AvailableVersion
        $versions = @($Row.MatchingApps | ForEach-Object { ConvertTo-EwComparableVersion -Version $_.DisplayVersion })
        if (-not $latest.Success -or @($versions | Where-Object Success -EQ $false).Count -gt 0) {
            $Row.DeploymentBlocker = 'An available or imported version is missing or cannot be compared. Review the versions.'
        }
        elseif (@($versions | Where-Object { $_.Parsed -gt $latest.Parsed }).Count -gt 0) {
            $Row.Readiness = 'Newer version in Intune'
            $Row.DeploymentBlocker = 'Intune already contains a newer version. Older imports are blocked.'
        }
        elseif (@($versions | Where-Object { $_.Parsed -eq $latest.Parsed }).Count -gt 0) {
            $Row.Readiness = 'Latest imported'
            $Row.DeploymentBlocker = 'The latest available version is already imported. Duplicate imports are blocked.'
        }
        elseif ($Row.MatchingApps.Count -gt 0 -and -not $AppId) {
            $Row.DeploymentBlocker = 'Choose the matching Intune app to supersede. No single current app was verified.'
        }
        elseif ($Row.MatchingApps.Count -eq 0) {
            $Row.Readiness = 'Not imported'
            $Row.MatchStatus = 'No matching Win32 app'
        }
        else {
            $Row.Readiness = 'Update available'
            $Row.MatchStatus = 'Matched (update required)'
        }
    }
    $Row.UpdateBlocker = if ($Row.DeploymentBlocker) { $Row.DeploymentBlocker }
        elseif (-not $AppId) { 'No existing app to update. Use Import for deployment.' }
        elseif (-not $Row.UpdateRequirement.Succeeded) { [string]$Row.UpdateRequirement.Error }
        else { '' }
    $Row.UpdateEligibilityText = if ($Row.UpdateBlocker) { "Update import blocked: $($Row.UpdateBlocker)" }
        else { 'Update import eligible: application-presence requirements will be enforced with a required All Devices assignment.' }
    Write-Verbose -Message "EvergreenUI: '$($Row.DefinitionName)' readiness '$($Row.Readiness)', predecessor '$AppId'."
}
