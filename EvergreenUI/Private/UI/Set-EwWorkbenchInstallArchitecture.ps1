Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwWorkbenchInstallArchitecture {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates only an in-memory view row.')]
    param(
        [Parameter(Mandatory)]
        [psobject]$Row,

        [Parameter(Mandatory)]
        [psobject]$Compatibility,

        [Parameter()]
        [switch]$ArtifactResolved
    )

    $Row.RequirementArchitecture = if ([string]::IsNullOrWhiteSpace($Compatibility.RequirementArchitecture)) {
        'Missing'
    }
    else { [string]$Compatibility.RequirementArchitecture }
    $Row.ArtifactArchitecture = if (-not $ArtifactResolved) { 'Not checked' }
        elseif ([string]::IsNullOrWhiteSpace($Compatibility.ArtifactArchitecture)) { 'Unknown' }
        else { [string]$Compatibility.ArtifactArchitecture }
    $Row.ArchitectureAssessment = [string]$Compatibility.Status
    $Row.ArchitectureStatus = switch ($Compatibility.Status) {
        'Blocked' { 'Blocked' }
        'NeedsApproval' {
            if ($ArtifactResolved) { 'Approval required' } else { 'Approval may be required' }
        }
        default { if ($ArtifactResolved) { 'Allowed' } else { 'Artifact not checked' } }
    }
    $Row.ArchitectureError = if ($Compatibility.Status -eq 'Blocked') { [string]$Compatibility.Error }
        else { $Compatibility.Warnings -join ' ' }
}
