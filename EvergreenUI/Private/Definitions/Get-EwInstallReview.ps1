Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwInstallReview {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [switch]$NoCache
    )

    $definition = $null
    $definitionHash = ''
    $latest = $null
    $compatibility = $null
    $fail = {
        param([string]$Message, [string]$Status = 'Failed')
        Write-Verbose -Message "EvergreenUI: Installation review for '$DefinitionPath' returned ${Status}: $Message"
        [PSCustomObject]@{
            Status = $Status
            Definition = $definition
            DefinitionHash = $definitionHash
            Latest = $latest
            Compatibility = $compatibility
            Fingerprint = ''
            Error = $Message
        }
    }

    Write-Verbose -Message "EvergreenUI: Reviewing installation inputs for '$DefinitionPath'."
    try {
        $definitionHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop
        $definition = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $readHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop
    }
    catch {
        return (& $fail "Failed to read definition: $($_.Exception.Message)")
    }
    if ($readHash -ne $definitionHash) {
        return (& $fail 'Definition changed while it was being read.' 'Changed')
    }

    $compatibility = Get-EwInstallArchitectureCompatibility -DefinitionObject $definition
    if ($compatibility.Status -eq 'Blocked') {
        return (& $fail $compatibility.Error 'Blocked')
    }

    $resolveParameters = @{ DefinitionPath = $DefinitionPath; NoCache = $NoCache; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
        $resolveParameters.CachePath = $CachePath
    }
    try {
        Write-Verbose -Message "EvergreenUI: Resolving the Artifact for '$DefinitionPath'."
        $latest = Resolve-EwArtifact @resolveParameters
    }
    catch {
        return (& $fail "Artifact resolution failed: $($_.Exception.Message)")
    }
    if (-not $latest.Succeeded) {
        return (& $fail "Artifact resolution failed: $($latest.Error)")
    }

    try {
        $resolvedHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop
        if ($resolvedHash -ne $definitionHash) {
            return (& $fail 'Definition changed during Artifact resolution.' 'Changed')
        }
        $compatibility = Get-EwInstallArchitectureCompatibility -DefinitionObject $definition `
            -Artifact $latest.ResolvedArtifact -ErrorAction Stop
        if ($compatibility.Status -eq 'Blocked') {
            return (& $fail $compatibility.Error 'Blocked')
        }
        $reviewedInput = [PSCustomObject]@{
            DefinitionHash = $definitionHash
            Version = [string]$latest.Version
            URI = [string]$latest.URI
            Artifact = $latest.ResolvedArtifact
        }
        $json = ConvertTo-Json -InputObject $reviewedInput -Depth 100 -Compress -ErrorAction Stop -WarningAction Stop
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $fingerprint = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
    }
    catch {
        return (& $fail "Could not review install inputs: $($_.Exception.Message)")
    }

    Write-Verbose -Message "EvergreenUI: Reviewed installation inputs for '$DefinitionPath'; architecture status is $($compatibility.Status)."
    [PSCustomObject]@{
        Status = [string]$compatibility.Status
        Definition = $definition
        DefinitionHash = $definitionHash
        Latest = $latest
        Compatibility = $compatibility
        Fingerprint = $fingerprint
        Error = ''
    }
}
