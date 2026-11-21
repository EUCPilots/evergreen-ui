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
    .EXAMPLE
        Install-EwPackage -DefinitionPath .\Definitions\Example\App.json -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Installer commands execute with the current user's permissions.
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
        [switch]$NoCache
    )

    $fail = {
        param([string]$Message, [string]$Directory = '', [string]$Version = '')
        [PSCustomObject]@{
            Succeeded         = $false
            ExitCode          = -1
            WorkingDirectory  = $Directory
            DownloadedVersion = $Version
            InstallCommand    = ''
            Error             = $Message
        }
    }

    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition file was not found: $DefinitionPath")
    }
    try {
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

    $resolveParameters = @{ DefinitionPath = $DefinitionPath; NoCache = $NoCache }
    if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
        $resolveParameters.CachePath = $CachePath
    }
    $latest = Resolve-EwArtifact @resolveParameters
    if (-not $latest.Succeeded) {
        return (& $fail "Artifact resolution failed: $($latest.Error)" $sourcePath)
    }

    try {
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

        $processResult = Invoke-EwInstallerProcess -WorkingDirectory $sourcePath -ScriptPath $scriptPath -Command $installCommand
        $exitCode = [int]$processResult.ExitCode
        if ($exitCode -notin @(0, 3010)) {
            return (& $fail "Installer exited with code $exitCode." $sourcePath $latest.Version)
        }
        [PSCustomObject]@{
            Succeeded         = $true
            ExitCode          = $exitCode
            WorkingDirectory  = $sourcePath
            DownloadedVersion = $latest.Version
            InstallCommand    = if (-not [string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath } else { $installCommand }
            Error             = ''
        }
    }
    catch {
        return (& $fail "Installation failed: $($_.Exception.Message)" $sourcePath $latest.Version)
    }
}
