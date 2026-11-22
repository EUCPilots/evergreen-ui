Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-EwPackage {
    <#
    .SYNOPSIS
        Builds an Intune Win32 or Nerdio Microsoft 365 Apps package.
    .DESCRIPTION
        Builds .intunewin packages from App.json definitions using IntuneWin32App,
        or builds Intune/Nerdio packages from an Office Deployment Tool XML file.
    .PARAMETER DefinitionPath
        App.json path for an Intune Win32 package.
    .PARAMETER M365ConfigurationPath
        Office Deployment Tool XML configuration to package.
    .PARAMETER ConfigurationRoot
        Directory containing the M365 configuration and optional uninstall XML.
    .PARAMETER Provider
        Target provider. App.json definitions support Intune; M365 configurations
        support Intune and Nerdio.
    .PARAMETER WorkingPath
        Root path used for package source and output files.
    .PARAMETER Channel
        Microsoft 365 Apps update channel.
    .PARAMETER CompanyName
        Company name written into the ODT configuration.
    .PARAMETER ImportFor
        Whether to enable shared computer licensing for a single or multi-session host.
    .PARAMETER TenantId
        Entra tenant ID written into the ODT configuration.
    .PARAMETER CachePath
        Optional artifact-resolution cache directory.
    .PARAMETER NoCache
        Forces a fresh Evergreen query for App.json package definitions.
    .PARAMETER AppJsonTemplatePath
        Optional App.json template copied into a Microsoft 365 package.
    .PARAMETER Force
        Replaces an existing Microsoft 365 output package after confirmation by the caller.
    .PARAMETER M365Plan
        Optional confirmed build preview. If omitted, one is created automatically.
        Inputs and the active matching provider session are rechecked.
    .EXAMPLE
        New-EwPackage -DefinitionPath .\Definitions\Example\App.json -WorkingPath .\Packages
    .EXAMPLE
        New-EwPackage -M365ConfigurationPath .\M365\Install.xml -Provider Nerdio `
            -Channel MonthlyEnterprise -CompanyName Contoso -ImportFor 'Multi-session' `
            -TenantId '00000000-0000-0000-0000-000000000000'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Intune package building requires IntuneWin32App.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Definition')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Definition')]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter(Mandatory, ParameterSetName = 'M365')]
        [ValidateNotNullOrEmpty()]
        [string]$M365ConfigurationPath,

        [Parameter(ParameterSetName = 'M365')]
        [string]$ConfigurationRoot,

        [Parameter(ParameterSetName = 'Definition')]
        [Parameter(ParameterSetName = 'M365')]
        [ValidateSet('Intune', 'Nerdio')]
        [string]$Provider = 'Intune',

        [Parameter()]
        [string]$WorkingPath,

        [Parameter(Mandatory, ParameterSetName = 'M365')]
        [ValidateNotNullOrEmpty()]
        [string]$Channel,

        [Parameter(Mandatory, ParameterSetName = 'M365')]
        [ValidateNotNullOrEmpty()]
        [string]$CompanyName,

        [Parameter(Mandatory, ParameterSetName = 'M365')]
        [ValidateSet('Single session', 'Multi-session')]
        [string]$ImportFor,

        [Parameter(Mandatory, ParameterSetName = 'M365')]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Definition')]
        [string]$CachePath,

        [Parameter(ParameterSetName = 'Definition')]
        [switch]$NoCache,

        [Parameter(ParameterSetName = 'M365')]
        [string]$AppJsonTemplatePath,

        [Parameter(ParameterSetName = 'M365')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'M365')]
        [psobject]$M365Plan
    )

    if ([string]::IsNullOrWhiteSpace($WorkingPath)) {
        $WorkingPath = [string](Get-EwSetting).OutputPath
    }
    if ([string]::IsNullOrWhiteSpace($WorkingPath)) {
        throw 'WorkingPath is empty and no OutputPath is configured.'
    }
    if ($PSCmdlet.ParameterSetName -eq 'Definition' -and $Provider -ne 'Intune') {
        throw "Provider '$Provider' is supported only for Microsoft 365 package builds."
    }

    if ($PSCmdlet.ParameterSetName -eq 'Definition') {
        $name = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName(
                [System.IO.Path]::GetFullPath($DefinitionPath)
            ))
        $target = Join-Path -Path $WorkingPath -ChildPath $name
    }
    else {
        if ([string]::IsNullOrWhiteSpace($ConfigurationRoot)) {
            $ConfigurationRoot = Split-Path -Path $M365ConfigurationPath -Parent
        }
        $target = $M365ConfigurationPath
    }

    if (-not $PSCmdlet.ShouldProcess($target, "Build $Provider package")) {
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'M365') {
        return Invoke-EwM365PackageBuild -ConfigurationPath $M365ConfigurationPath `
            -ConfigurationRoot $ConfigurationRoot -WorkingPath $WorkingPath -Channel $Channel `
            -CompanyName $CompanyName -ImportFor $ImportFor -TenantId $TenantId `
            -Provider $Provider -AppJsonTemplatePath $AppJsonTemplatePath -Force:$Force -Plan $M365Plan
    }

    $fail = {
        param([string]$Message, [string]$Source = '', [string]$Output = '')
        [PSCustomObject]@{
            Succeeded = $false
            Provider = $Provider
            PackagePath = ''
            SetupFile = ''
            Version = ''
            SourcePath = $Source
            OutputPath = $Output
            Error = $Message
        }
    }
    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition file was not found: $DefinitionPath")
    }
    $definition = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $folderName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($DefinitionPath)))
    $folderName = [regex]::Replace($folderName, '[^\w\-.]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($folderName)) { $folderName = 'IntunePackage' }
    $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$folderName\Source"
    $outputPath = Join-Path -Path $WorkingPath -ChildPath "$folderName\Output"

    try {
        $resolvedParams = @{ DefinitionPath = $DefinitionPath; NoCache = $NoCache }
        if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
            $resolvedParams.CachePath = $CachePath
        }
        $latest = Resolve-EwArtifact @resolvedParams
        if (-not $latest.Succeeded) {
            return (& $fail "Artifact resolution failed: $($latest.Error)" $sourcePath $outputPath)
        }
        $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
        $definitionSource = Join-Path -Path (Split-Path -Path $DefinitionPath -Parent) -ChildPath 'Source'
        if (Test-Path -LiteralPath $definitionSource -PathType Container) {
            Copy-Item -Path (Join-Path -Path $definitionSource -ChildPath '*') `
                -Destination $sourcePath -Recurse -Force -ErrorAction Stop
        }
        $psadtScript = Join-Path -Path $sourcePath -ChildPath 'Invoke-AppDeployToolkit.ps1'
        $installScript = Join-Path -Path $sourcePath -ChildPath 'Install.ps1'
        if (-not (Test-Path -LiteralPath $psadtScript -PathType Leaf) -and
            -not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $sharedInstallScript = Join-Path -Path $moduleRoot -ChildPath 'Resources\Install.ps1'
            if (-not (Test-Path -LiteralPath $sharedInstallScript -PathType Leaf)) {
                throw "The shared Install.ps1 resource was not found: $sharedInstallScript"
            }
            Copy-Item -LiteralPath $sharedInstallScript -Destination $installScript -ErrorAction Stop
        }
        $downloads = @(Invoke-EwArtifactSave -Artifact $latest.ResolvedArtifact -Path $sourcePath -Force)
        if ($downloads.Count -eq 0) {
            throw 'Evergreen returned no downloaded installer.'
        }
        $setupFile = [System.IO.Path]::GetFileName([string]$downloads[0].FullName)
        if ([string]::IsNullOrWhiteSpace($setupFile)) {
            $setupFile = [string]$definition.PackageInformation.SetupFile
        }
        $definition.PackageInformation.Version = $latest.Version
        $definition.PackageInformation.SetupFile = $setupFile
        Write-EwJsonFile -Path (Join-Path -Path $sourcePath -ChildPath 'App.json') -InputObject $definition

        $packagePath = Invoke-EwIntunePackageBuilder -SourceFolder $sourcePath `
            -SetupFile $setupFile -OutputFolder $outputPath
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
            throw "Expected Intune package was not created: $packagePath"
        }
        [PSCustomObject]@{
            Succeeded = $true
            Provider = 'Intune'
            PackagePath = $packagePath
            SetupFile = $setupFile
            Version = $latest.Version
            SourcePath = $sourcePath
            OutputPath = $outputPath
            Error = ''
        }
    }
    catch {
        return (& $fail "Package build failed: $($_.Exception.Message)" $sourcePath $outputPath)
    }
}
