Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwInstallArchitectureCompatibility {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$DefinitionObject,

        [Parameter()]
        [AllowNull()]
        [object]$Artifact,

        [Parameter()]
        [AllowEmptyString()]
        [string]$OperatingSystemArchitecture
    )

    $requirementRule = Get-EwObjectPropertyValue -Object $DefinitionObject -Name 'RequirementRule'
    $requirementValue = if ($null -ne $requirementRule) {
        Get-EwObjectPropertyValue -Object $requirementRule -Name 'Architecture'
    }
    else {
        $null
    }
    $artifactValue = if ($null -ne $Artifact) {
        Get-EwObjectPropertyValue -Object $Artifact -Name 'Architecture'
    }
    else {
        $null
    }
    $requirementText = [string]$requirementValue
    $artifactText = [string]$artifactValue

    $fail = {
        param([string]$Message)
        Write-Verbose -Message "EvergreenUI: Local install architecture assessment blocked: $Message"
        [PSCustomObject]@{
            Status = 'Blocked'
            OperatingSystemArchitecture = [string]$OperatingSystemArchitecture
            RequirementArchitecture = $requirementText
            ArtifactArchitecture = $artifactText
            RequiresMissingRequirementApproval = $false
            RequiresX64OnArm64Approval = $false
            RequiresUnknownArchitectureApproval = $false
            MissingRequirementWarning = ''
            X64OnArm64Warning = ''
            UnknownArchitectureWarning = ''
            Warnings = [string[]]@()
            Error = $Message
        }
    }

    if (-not $PSBoundParameters.ContainsKey('OperatingSystemArchitecture')) {
        try {
            $OperatingSystemArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        }
        catch {
            return (& $fail "Could not determine the operating system architecture: $($_.Exception.Message)")
        }
    }
    $OperatingSystemArchitecture = $OperatingSystemArchitecture.Trim().ToLowerInvariant()
    if ($OperatingSystemArchitecture -notin @('x86', 'x64', 'arm64')) {
        return (& $fail "Unsupported or unknown operating system architecture '$OperatingSystemArchitecture'.")
    }

    $requirement = ConvertFrom-EwArchitectureRequirement -Architecture $requirementText
    if ($requirement.Kind -eq 'Invalid') {
        return (& $fail $requirement.Error)
    }
    if ($requirement.Kind -ne 'Missing' -and $OperatingSystemArchitecture -notin $requirement.Values) {
        return (& $fail "Definition architecture requirement '$requirementText' excludes $OperatingSystemArchitecture Windows.")
    }

    $requiresMissingApproval = $requirement.Kind -eq 'Missing'
    $requiresEmulationApproval = $false
    $requiresUnknownApproval = $false
    if ($PSBoundParameters.ContainsKey('Artifact')) {
        $artifactArchitecture = $artifactText.Trim().ToLowerInvariant()
        if (($artifactArchitecture -eq 'x64' -and $OperatingSystemArchitecture -eq 'x86') -or
            ($artifactArchitecture -eq 'arm64' -and $OperatingSystemArchitecture -ne 'arm64')) {
            return (& $fail "Artifact architecture '$artifactText' is incompatible with $OperatingSystemArchitecture Windows.")
        }
        if ($OperatingSystemArchitecture -eq 'arm64' -and $artifactArchitecture -eq 'x64') {
            $requiresEmulationApproval = $true
        }
        elseif ($OperatingSystemArchitecture -eq 'arm64' -and $artifactArchitecture -notin @('x86', 'x64', 'arm64')) {
            $application = Get-EwObjectPropertyValue -Object $DefinitionObject -Name 'Application'
            $declared = if ($null -ne $application) {
                ([string](Get-EwObjectPropertyValue -Object $application -Name 'Architecture' -Default '')).Trim().ToLowerInvariant()
            } else { '' }
            if ($declared -eq 'x64') {
                $requiresEmulationApproval = $true
            }
            elseif ($declared -notin @('x86', 'arm64')) {
                $requiresUnknownApproval = $true
            }
        }
    }

    $missingWarning = if ($requiresMissingApproval) { 'The Definition has no architecture requirement.' } else { '' }
    $emulationWarning = if ($requiresEmulationApproval) {
        'The installation may use x64 emulation on Arm64. Application and driver compatibility is not guaranteed.'
    }
    else {
        ''
    }
    $unknownWarning = if ($requiresUnknownApproval) { 'The Artifact architecture is unknown on Arm64; compatibility and emulation requirements cannot be determined.' } else { '' }
    $warnings = @($missingWarning, $emulationWarning, $unknownWarning | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $status = if ($warnings.Count -gt 0) { 'NeedsApproval' } else { 'Allowed' }
    Write-Verbose -Message "EvergreenUI: Local install architecture assessment for $OperatingSystemArchitecture is $status."
    [PSCustomObject]@{
        Status = $status
        OperatingSystemArchitecture = $OperatingSystemArchitecture
        RequirementArchitecture = $requirementText
        ArtifactArchitecture = $artifactText
        RequiresMissingRequirementApproval = $requiresMissingApproval
        RequiresX64OnArm64Approval = $requiresEmulationApproval
        RequiresUnknownArchitectureApproval = $requiresUnknownApproval
        MissingRequirementWarning = $missingWarning
        X64OnArm64Warning = $emulationWarning
        UnknownArchitectureWarning = $unknownWarning
        Warnings = [string[]]$warnings
        Error = ''
    }
}
