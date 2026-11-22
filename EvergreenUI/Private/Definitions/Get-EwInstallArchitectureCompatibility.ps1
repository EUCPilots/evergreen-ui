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
            MissingRequirementWarning = ''
            X64OnArm64Warning = ''
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

    $parseArchitecture = {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq '-') {
            return [PSCustomObject]@{ Kind = 'Missing'; Values = [string[]]@() }
        }

        $values = @($Value -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique)
        if (@($values | Where-Object { $_ -notin @('all', 'x86', 'x64', 'arm64') }).Count -gt 0) {
            return [PSCustomObject]@{ Kind = 'Invalid'; Values = [string[]]$values }
        }
        if ('all' -in $values -or
            ('x86' -in $values -and 'x64' -in $values -and 'arm64' -in $values)) {
            return [PSCustomObject]@{ Kind = 'All'; Values = [string[]]@('x86', 'x64', 'arm64') }
        }
        return [PSCustomObject]@{ Kind = 'Specific'; Values = [string[]]$values }
    }
    $getDecision = {
        param([string]$Architecture, [string]$HostArchitecture)
        if ($Architecture -eq 'x86' -or $Architecture -eq $HostArchitecture) {
            return 'Allowed'
        }
        if ($Architecture -eq 'x64' -and $HostArchitecture -eq 'arm64') {
            return 'Approval'
        }
        return 'Blocked'
    }

    $requirement = & $parseArchitecture -Value $requirementText
    if ($requirement.Kind -eq 'Invalid') {
        return (& $fail "Unrecognized Definition architecture requirement '$requirementText'.")
    }
    $artifactArchitecture = & $parseArchitecture -Value $artifactText
    if ($artifactArchitecture.Kind -eq 'Invalid') {
        Write-Verbose -Message "EvergreenUI: Artifact architecture '$artifactText' is not recognized; using the Definition requirement."
    }

    $requiresMissingApproval = $requirement.Kind -eq 'Missing'
    $requiresEmulationApproval = $false
    if ($requirement.Kind -eq 'Specific') {
        $requirementValues = @($requirement.Values)
        if ($artifactArchitecture.Kind -eq 'Specific' -and
            $artifactArchitecture.Values.Count -eq 1 -and
            $artifactArchitecture.Values[0] -in $requirementValues) {
            $requirementValues = @($artifactArchitecture.Values[0])
        }
        $decisions = @($requirementValues | ForEach-Object {
                & $getDecision -Architecture $_ -HostArchitecture $OperatingSystemArchitecture
            })
        if ('Allowed' -notin $decisions -and 'Approval' -notin $decisions) {
            return (& $fail "Definition architecture requirement '$requirementText' is incompatible with $OperatingSystemArchitecture Windows.")
        }
        $requiresEmulationApproval = 'Approval' -in $decisions
    }

    if ($artifactArchitecture.Kind -eq 'Specific') {
        $decisions = @($artifactArchitecture.Values | ForEach-Object {
                & $getDecision -Architecture $_ -HostArchitecture $OperatingSystemArchitecture
            })
        if ('Allowed' -notin $decisions -and 'Approval' -notin $decisions) {
            return (& $fail "Artifact architecture '$artifactText' is incompatible with $OperatingSystemArchitecture Windows.")
        }
        if ('Approval' -in $decisions) {
            $requiresEmulationApproval = $true
        }
    }

    $missingWarning = if ($requiresMissingApproval) { 'The Definition has no architecture requirement.' } else { '' }
    $emulationWarning = if ($requiresEmulationApproval) {
        'The installation may use x64 emulation on Arm64. Windows 10 on Arm does not support x64 emulation.'
    }
    else {
        ''
    }
    $warnings = @($missingWarning, $emulationWarning | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $status = if ($warnings.Count -gt 0) { 'NeedsApproval' } else { 'Allowed' }
    Write-Verbose -Message "EvergreenUI: Local install architecture assessment for $OperatingSystemArchitecture is $status."
    [PSCustomObject]@{
        Status = $status
        OperatingSystemArchitecture = $OperatingSystemArchitecture
        RequirementArchitecture = $requirementText
        ArtifactArchitecture = $artifactText
        RequiresMissingRequirementApproval = $requiresMissingApproval
        RequiresX64OnArm64Approval = $requiresEmulationApproval
        MissingRequirementWarning = $missingWarning
        X64OnArm64Warning = $emulationWarning
        Warnings = [string[]]$warnings
        Error = ''
    }
}
