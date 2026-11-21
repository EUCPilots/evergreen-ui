Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwDefinition {
    <#
    .SYNOPSIS
        Updates App.json version and setup-file metadata from Evergreen.
    .DESCRIPTION
        Resolves the current artifact, updates PackageInformation and supported
        version-based detection rules, and updates Source\Install.json when present.
    .PARAMETER DefinitionPath
        Path to an App.json file or directory containing App.json files.
    .PARAMETER CachePath
        Optional artifact cache directory passed to Resolve-EwArtifact.
    .PARAMETER NoCache
        Forces a fresh Evergreen query and skips cache reads and writes.
    .EXAMPLE
        Update-EwDefinition -DefinitionPath .\Definitions -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Individual files are written atomically,
        but updating App.json and Install.json is not a transaction. ChangedPaths
        lists files already updated if a later write fails.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [switch]$NoCache
    )

    $definitions = @(Get-EwDefinition -Path $DefinitionPath)
    foreach ($definition in $definitions) {
        $result = [PSCustomObject]@{
            Name           = $definition.Name
            DefinitionPath = $definition.DefinitionPath
            OldVersion     = $definition.Version
            NewVersion     = $definition.Version
            NewSetupFile   = ''
            Succeeded      = $false
            NoUpdateNeeded = $false
            ChangedPaths   = @()
            Error          = ''
        }
        if ($definition.Status -ne 'Valid') {
            $result.Error = "Skipped: definition is not valid ($($definition.Status))."
            $result
            continue
        }

        $resolvedParams = @{ DefinitionPath = $definition.DefinitionPath; NoCache = $NoCache }
        if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
            $resolvedParams.CachePath = $CachePath
        }
        $latest = Resolve-EwArtifact @resolvedParams
        if (-not $latest.Succeeded) {
            $result.Error = $latest.Error
            $result
            continue
        }

        $setupFile = [System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName(([uri]$latest.URI).AbsolutePath))
        if ([string]::IsNullOrWhiteSpace($setupFile)) {
            $setupFile = [string]$definition.DefinitionObject.PackageInformation.SetupFile
        }
        $result.NewVersion = $latest.Version
        $result.NewSetupFile = $setupFile
        $currentSetupFile = [string]$definition.DefinitionObject.PackageInformation.SetupFile
        if ($latest.Version -eq $definition.Version -and $setupFile -eq $currentSetupFile) {
            $result.Succeeded = $true
            $result.NoUpdateNeeded = $true
            $result
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($definition.DefinitionPath, "Update definition to version $($latest.Version)")) {
            $result.Error = 'Update was skipped.'
            $result
            continue
        }

        try {
            Write-Verbose -Message "EvergreenUI: Updating definition '$($definition.DefinitionPath)' to version '$($latest.Version)'"
            $appJson = Get-Content -LiteralPath $definition.DefinitionPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $appJson.PackageInformation.Version = $latest.Version
            $appJson.PackageInformation.SetupFile = $setupFile
            foreach ($rule in @($appJson.DetectionRule)) {
                if ($null -eq $rule) {
                    continue
                }
                if ([string]$rule.Type -ieq 'File' -and [string]$rule.DetectionMethod -ieq 'Version') {
                    $rule.VersionValue = $latest.Version
                }
                elseif ([string]$rule.Type -ieq 'Registry' -and
                    [string]$rule.DetectionMethod -ieq 'VersionComparison') {
                    $rule.Value = $latest.Version
                }
            }
            Write-EwJsonFile -Path $definition.DefinitionPath -InputObject $appJson
            $result.ChangedPaths = @($definition.DefinitionPath)

            $installJsonPath = Join-Path -Path (Split-Path -Path $definition.DefinitionPath -Parent) -ChildPath 'Source\Install.json'
            if (Test-Path -LiteralPath $installJsonPath -PathType Leaf) {
                $installJson = Get-Content -LiteralPath $installJsonPath -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $installJson.PackageInformation) {
                    $installJson.PackageInformation.Version = $latest.Version
                    $installJson.PackageInformation.SetupFile = $setupFile
                    Write-EwJsonFile -Path $installJsonPath -InputObject $installJson
                    $result.ChangedPaths += $installJsonPath
                }
            }

            $result.Succeeded = $true
            Write-Verbose -Message "EvergreenUI: Updated definition files: $($result.ChangedPaths -join ', ')"
        }
        catch {
            $result.Error = "Failed to update definition: $($_.Exception.Message)"
            Write-Verbose -Message "EvergreenUI: $($result.Error)"
        }
        $result
    }
}
