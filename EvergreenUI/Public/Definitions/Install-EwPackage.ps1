Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-EwPackage {
    <#
    .SYNOPSIS
        Downloads and installs an application described by App.json.
    .DESCRIPTION
        Resolves the latest installer, stages it with definition source files,
        and runs Install.ps1 or Program.InstallCommand after confirmation.
    .PARAMETER DefinitionPath
        Path to an App.json definition.
    .PARAMETER WorkingPath
        Root path used to stage the installer. Defaults to the configured output path.
    .PARAMETER CachePath
        Optional artifact-resolution cache directory.
    .PARAMETER NoCache
        Forces a fresh Evergreen artifact query.
    .PARAMETER AllowMissingArchitectureRequirement
        Explicitly approves installation when the Definition has no architecture requirement.
    .PARAMETER AllowX64OnArm64
        Explicitly approves x64 emulation on Arm64.
    .PARAMETER AllowUnknownArchitectureOnArm64
        Explicitly approves an unknown artifact architecture on Arm64.
    .EXAMPLE
        Install-EwPackage -DefinitionPath .\Definitions\Example\App.json -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Architecture warnings require separate
        approval even when Confirm is disabled. Installer commands execute with
        the current user's permissions.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter()]
        [string]$WorkingPath,

        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [switch]$NoCache,

        [Parameter()]
        [switch]$AllowMissingArchitectureRequirement,

        [Parameter()]
        [switch]$AllowX64OnArm64,

        [Parameter()]
        [switch]$AllowUnknownArchitectureOnArm64,

        [Parameter(DontShow)]
        [ValidatePattern('^[0-9A-Fa-f]{64}$')]
        [string]$ExpectedReviewFingerprint,

        [Parameter(DontShow)]
        [switch]$RequireArchitectureOptIn
    )

    $fail = {
        param(
            [string]$Message,
            [string]$Directory = '',
            [string]$Version = '',
            [string]$Status = 'Failed',
            [bool]$ReviewChanged = $false
        )
        Write-Verbose -Message "EvergreenUI: Local installation returned ${Status}: $Message"
        [PSCustomObject]@{
            Succeeded         = $false
            Status            = $Status
            ExitCode          = -1
            WorkingDirectory  = $Directory
            DownloadedVersion = $Version
            InstallCommand    = ''
            ReviewChanged     = $ReviewChanged
            Error             = $Message
        }
    }

    Write-Verbose -Message "EvergreenUI: Preparing local installation from '$DefinitionPath'."
    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition file was not found: $DefinitionPath")
    }
    try {
        $initialDefinitionHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop
        $definition = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (& $fail "Failed to read definition: $($_.Exception.Message)")
    }

    if ([string]::IsNullOrWhiteSpace($WorkingPath)) {
        $WorkingPath = [string](Get-EwSetting).OutputPath
    }
    if ([string]::IsNullOrWhiteSpace($WorkingPath)) {
        return (& $fail 'WorkingPath is empty and no OutputPath is configured.')
    }
    $folderName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName(
            [System.IO.Path]::GetFullPath($DefinitionPath)
        ))
    $folderName = [regex]::Replace($folderName, '[^\w\-.]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($folderName)) {
        $folderName = 'InstallPackage'
    }
    $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$folderName\Source"

    if (-not $PSCmdlet.ShouldProcess([string]$definition.Information.DisplayName, 'Download and install package')) {
        return
    }

    $reviewParameters = @{ DefinitionPath = $DefinitionPath; NoCache = $NoCache }
    if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
        $reviewParameters.CachePath = $CachePath
    }
    $review = Get-EwInstallReview @reviewParameters
    if ($review.Status -eq 'Changed') {
        return (& $fail $review.Error $sourcePath '' 'Skipped' $true)
    }
    if ($review.Status -in @('Failed', 'Blocked')) {
        return (& $fail $review.Error $sourcePath '' $review.Status)
    }
    if ($initialDefinitionHash -ne $review.DefinitionHash -or
        (-not [string]::IsNullOrWhiteSpace($ExpectedReviewFingerprint) -and
            $ExpectedReviewFingerprint -ne $review.Fingerprint)) {
        return (& $fail 'Definition or Artifact metadata changed after review.' $sourcePath '' 'Skipped' $true)
    }

    $definition = $review.Definition
    $latest = $review.Latest
    $warnings = @(
        if ($review.Compatibility.RequiresMissingRequirementApproval -and -not $AllowMissingArchitectureRequirement) {
            $review.Compatibility.MissingRequirementWarning
        }
        if ($review.Compatibility.RequiresX64OnArm64Approval -and -not $AllowX64OnArm64) {
            $review.Compatibility.X64OnArm64Warning
        }
        if ((Get-EwObjectPropertyValue -Object $review.Compatibility -Name 'RequiresUnknownArchitectureApproval' -Default $false) -and -not $AllowUnknownArchitectureOnArm64) {
            $review.Compatibility.UnknownArchitectureWarning
        }
    )
    if ($warnings.Count -gt 0) {
        if ($RequireArchitectureOptIn) {
            throw 'Architecture approval is required; specify the matching explicit opt-in before installing.'
        }
        if (-not (Confirm-EwInstallArchitecture -Command $PSCmdlet -Name ([string]$definition.Information.DisplayName) `
                    -Warning $warnings -ErrorAction Stop)) {
            return (& $fail 'Architecture approval was declined.' $sourcePath '' 'Skipped')
        }
    }

    try {
        $currentDefinitionHash = Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop
    }
    catch {
        return (& $fail "Could not recheck definition: $($_.Exception.Message)" $sourcePath)
    }
    if ($currentDefinitionHash -ne $review.DefinitionHash) {
        return (& $fail 'Definition changed after architecture review.' $sourcePath '' 'Skipped' $true)
    }

    try {
        Write-Verbose -Message "EvergreenUI: Staging and downloading the installer for '$DefinitionPath'."
        $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        $definitionSource = Join-Path -Path (Split-Path -Path $DefinitionPath -Parent) -ChildPath 'Source'
        if (Test-Path -LiteralPath $definitionSource -PathType Container) {
            Copy-Item -Path (Join-Path -Path $definitionSource -ChildPath '*') `
                -Destination $sourcePath -Recurse -Force -ErrorAction Stop
        }
        $downloaded = @(Invoke-EwArtifactSave -Artifact $latest.ResolvedArtifact -Path $sourcePath -Force)
        if ($downloaded.Count -eq 0) {
            throw 'Evergreen returned no downloaded file.'
        }

        $installJsonPath = Join-Path -Path $sourcePath -ChildPath 'Install.json'
        if (Test-Path -LiteralPath $installJsonPath -PathType Leaf) {
            $installJson = Get-Content -LiteralPath $installJsonPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $installJson.PackageInformation) {
                $installJson.PackageInformation.Version = $latest.Version
                $installJson.PackageInformation.SetupFile = [System.IO.Path]::GetFileName([string]$downloaded[0].FullName)
                Write-EwJsonFile -Path $installJsonPath -InputObject $installJson
            }
        }

        $scriptPath = Join-Path -Path $sourcePath -ChildPath 'Install.ps1'
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $rootInstallScript = Join-Path -Path (Split-Path -Path (Split-Path -Path $DefinitionPath -Parent) -Parent) -ChildPath 'Install.ps1'
            if (Test-Path -LiteralPath $rootInstallScript -PathType Leaf) {
                Copy-Item -LiteralPath $rootInstallScript -Destination $scriptPath -Force -ErrorAction Stop
            }
            else {
                $scriptPath = ''
            }
        }
        $installCommand = [string]$definition.Program.InstallCommand
        if ([string]::IsNullOrWhiteSpace($scriptPath) -and [string]::IsNullOrWhiteSpace($installCommand)) {
            throw 'No Install.ps1 or Program.InstallCommand was found.'
        }

        if ((Get-EwDefinitionFileHash -DefinitionPath $DefinitionPath -ErrorAction Stop) -ne $review.DefinitionHash) {
            return (& $fail 'Definition changed before installation.' $sourcePath $latest.Version 'Skipped' $true)
        }
        $processResult = Invoke-EwInstallerProcess -WorkingDirectory $sourcePath -ScriptPath $scriptPath -Command $installCommand
        $exitCode = [int]$processResult.ExitCode
        if ($exitCode -notin @(0, 3010)) {
            return (& $fail "Installer exited with code $exitCode." $sourcePath $latest.Version)
        }
        Write-Verbose -Message "EvergreenUI: Installed '$DefinitionPath' at version '$($latest.Version)' with exit code $exitCode."
        [PSCustomObject]@{
            Succeeded         = $true
            Status            = 'Installed'
            ExitCode          = $exitCode
            WorkingDirectory  = $sourcePath
            DownloadedVersion = $latest.Version
            InstallCommand    = if (-not [string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath } else { $installCommand }
            ReviewChanged     = $false
            Error             = ''
        }
    }
    catch {
        return (& $fail "Installation failed: $($_.Exception.Message)" $sourcePath $latest.Version)
    }
}
