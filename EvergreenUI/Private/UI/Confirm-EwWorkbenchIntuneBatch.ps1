Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchIntuneBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Window,

        [Parameter(Mandatory)]
        [object[]]$Selection,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter()]
        [switch]$PlanChanged
    )

    $modes = @($Selection | Select-Object -ExpandProperty ImportAsUpdate -Unique)
    if ($modes.Count -ne 1) { throw 'An import batch must use one deployment intent.' }
    $update = [bool]$modes[0]
    $intent = if ($update) { 'updates for existing installations' } else { 'applications for deployment' }
    $blocks = foreach ($item in $Selection) {
        $relationship = if ($item.IntuneAppId) {
            "The new app will supersede '$($item.IntuneDisplayName)', version $($item.IntuneVersion). Predecessor app ID: $($item.IntuneAppId)."
        } else { 'This is the first matching import. No existing app will be superseded.' }
        $assignment = if ($update) {
            'Required for All Devices. File or Registry application-presence requirements restrict eligibility to existing installations. Definition assignments are not copied.'
        } else { "Definition assignments: $($item.AssignmentSummary). Required assignments can install on targeted devices without the application; available assignments offer it to targeted users." }
        "$($item.DefinitionName)`n" +
            "Create a new Win32 app: version $($item.AvailableVersion), artifact $($item.Architecture), allowed devices $($item.RequirementArchitecture).`n" +
            "Stored definition version: $($item.DefinitionVersion).`n$relationship`n$assignment"
    }
    $changed = if ($PlanChanged) { "The plan changed since comparison. Review the refreshed versions, targets and assignments below.`n`n" } else { '' }
    $message = "Tenant: $TenantId`nImport $($Selection.Count) $intent.`n`n$changed$($blocks -join "`n`n")`n`n" +
        'Earlier Intune apps will not be deleted. Other matching apps and existing earlier supersedence links remain unchanged. The selected Definition and Source\Install.json files may be updated on disk. Changes during building will stop the affected import and require a new review.'
    $kind = if ($update) { 'update' } else { 'deployment' }
    $noun = if ($Selection.Count -eq 1) { 'app' } else { 'apps' }
    $button = "Import $($Selection.Count) $kind $noun"
    return Confirm-EwWorkbenchAction -Window $Window -Message $message -Title 'Confirm Intune publishing' -DefaultYes $false -AcceptText $button -DeclineText 'Cancel'
}
