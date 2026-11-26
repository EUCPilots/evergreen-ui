Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwM365PackageBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath,

        [Parameter(Mandatory)]
        [string]$ConfigurationRoot,

        [Parameter(Mandatory)]
        [string]$WorkingPath,

        [Parameter(Mandatory)]
        [string]$Channel,

        [Parameter(Mandatory)]
        [string]$CompanyName,

        [Parameter(Mandatory)]
        [ValidateSet('Single session', 'Multi-session')]
        [string]$ImportFor,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [ValidateSet('Intune', 'Nerdio')]
        [string]$Provider,

        [Parameter()]
        [string]$AppJsonTemplatePath,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [psobject]$Plan
    )

    $configuration = Read-EwM365Configuration -Path $ConfigurationPath
    $safeName = [regex]::Replace($configuration.DisplayName, '[\\/:*?"<>|]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'Microsoft365Apps' }
    $buildPath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Builds\$([guid]::NewGuid())"
    $sourcePath = Join-Path -Path $buildPath -ChildPath 'Source'
    $buildOutputPath = Join-Path -Path $buildPath -ChildPath 'Output'
    $outputPath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Output"
    $result = [PSCustomObject]@{
        Succeeded = $false
        Provider = $Provider
        PackagePath = ''
        SetupFile = 'setup.exe'
        Version = ''
        ToolVersion = ''
        SourcePath = $sourcePath
        OutputPath = $outputPath
        Error = ''
    }

    try {
        if ($null -ne $Plan) {
            if (-not $AppJsonTemplatePath) {
                if ($null -eq $Plan.PSObject.Properties['AppJsonTemplatePath']) {
                    throw 'The Microsoft 365 build preview is incomplete. Preview again.'
                }
                $AppJsonTemplatePath = [string]$Plan.AppJsonTemplatePath
            }
            $inputValues = @{
                ConfigurationPath = (Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Stop).Path
                ConfigurationRoot = (Resolve-Path -LiteralPath $ConfigurationRoot -ErrorAction Stop).Path
                Provider = $Provider; Channel = $Channel; CompanyName = $CompanyName
                ImportFor = $ImportFor; TenantId = $TenantId
            }
            if ($AppJsonTemplatePath) {
                $inputValues.AppJsonTemplatePath = (Resolve-Path -LiteralPath $AppJsonTemplatePath -ErrorAction Stop).Path
            }
            foreach ($inputName in $inputValues.Keys) {
                if ($null -eq $Plan.PSObject.Properties[$inputName] -or
                    [string]$Plan.$inputName -cne [string]$inputValues[$inputName]) {
                    throw "Build input '$inputName' does not match the confirmed Microsoft 365 preview."
                }
            }
            Assert-EwM365BuildPlan -Plan $Plan
        }
        $configurationId = [guid]::Empty
        if (-not [guid]::TryParse([string]$configuration.ConfigId, [ref]$configurationId) -or
            $configurationId -eq [guid]::Empty) {
            throw 'The Microsoft 365 configuration must have a valid, non-empty configuration ID.'
        }
        [xml]$xml = Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop
        $add = $xml.SelectSingleNode('/Configuration/Add')
        if ($null -eq $add) {
            throw "The Office Deployment Tool configuration '$ConfigurationPath' has no Configuration.Add element."
        }
        if ($add.HasAttribute('DownloadPath')) {
            throw 'A rolling channel cannot use DownloadPath because Office Deployment Tool requires a pinned version for that setting.'
        }
        $uninstallSource = Join-Path -Path $ConfigurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml'
        if ($Provider -eq 'Nerdio') { Assert-EwM365UninstallConfiguration -Path $uninstallSource }
        if ([string]::IsNullOrWhiteSpace($AppJsonTemplatePath)) {
            $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $AppJsonTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Resources\m365-app.json'
        }
        if (-not (Test-Path -LiteralPath $AppJsonTemplatePath -PathType Leaf)) {
            throw "App.json template was not found: $AppJsonTemplatePath"
        }
        $appJson = Get-Content -LiteralPath $AppJsonTemplatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $versionRules = @($appJson.DetectionRule | Where-Object {
                (Get-EwFirstPropertyValue -InputObject $_ -Name 'ValueName') -eq 'VersionToReport'
            })
        if ($Provider -eq 'Intune' -and ($versionRules.Count -ne 1 -or
                (Get-EwFirstPropertyValue -InputObject $versionRules[0] -Name 'Type') -ne 'Registry')) {
            throw 'The Intune template must contain exactly one registry VersionToReport detection rule.'
        }
        if ($null -eq $Plan) {
            $Plan = Get-EwM365BuildPlan -ConfigurationPath $ConfigurationPath -ConfigurationRoot $ConfigurationRoot `
                -Provider $Provider -Channel $Channel -CompanyName $CompanyName -ImportFor $ImportFor `
                -TenantId $TenantId -AppJsonTemplatePath $AppJsonTemplatePath
            Assert-EwM365BuildPlan -Plan $Plan
        }
        $officeArtifact = Get-EwM365SetupArtifact -Channel $Channel
        $toolArtifact = Get-EwM365DeploymentArtifact
        $result.Version = [string]$officeArtifact.Version
        $result.ToolVersion = [string]$toolArtifact.Version
        if ($null -ne $Plan -and ($result.Version -cne [string]$Plan.OfficeVersion -or
                $result.ToolVersion -cne [string]$Plan.ToolVersion -or
                [string]$toolArtifact.URI -cne [string]$Plan.ToolURI -or
                [string](Get-EwFirstPropertyValue -InputObject $officeArtifact -Name 'URI') -cne [string]$Plan.OfficeURI)) {
            throw 'The resolved Microsoft 365 source changed. Preview and confirm again.'
        }
        $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        $null = New-Item -Path $buildOutputPath -ItemType Directory -Force -ErrorAction Stop
        $toolDownloadPath = Join-Path -Path $buildPath -ChildPath 'Tool'
        $null = New-Item -Path $toolDownloadPath -ItemType Directory -ErrorAction Stop
        $downloaded = @(Invoke-EwArtifactSave -Artifact $toolArtifact -Path $toolDownloadPath)
        if ($downloaded.Count -eq 0) {
            throw 'Evergreen returned no Office Deployment Tool download result.'
        }
        $toolFile = [string](Get-EwFirstPropertyValue -InputObject $downloaded[0] -Name 'FullName', 'Path')
        if ([string]::IsNullOrWhiteSpace($toolFile) -or -not (Test-Path -LiteralPath $toolFile -PathType Leaf)) {
            throw 'The downloaded Office Deployment Tool artifact was not found.'
        }
        $extracted = Expand-EwM365DeploymentTool -Path $toolFile `
            -Destination (Join-Path -Path $buildPath -ChildPath 'Extracted') -ExpectedVersion $result.ToolVersion
        $setupFile = Join-Path -Path $sourcePath -ChildPath 'setup.exe'
        Copy-Item -LiteralPath $extracted -Destination $setupFile -ErrorAction Stop

        $installXmlPath = Join-Path -Path $sourcePath -ChildPath 'Install-Microsoft365Apps.xml'
        $uninstallXmlPath = Join-Path -Path $sourcePath -ChildPath 'Uninstall-Microsoft365Apps.xml'
        if (Test-Path -LiteralPath $uninstallSource -PathType Leaf) {
            Copy-Item -LiteralPath $uninstallSource -Destination $uninstallXmlPath -Force -ErrorAction Stop
        }

        $add.SetAttribute('Channel', $Channel)
        $add.RemoveAttribute('Version')
        $updates = $xml.SelectSingleNode('/Configuration/Updates')
        if ($null -ne $updates) {
            if ($updates.HasAttribute('Channel')) { $updates.SetAttribute('Channel', $Channel) }
            $updates.RemoveAttribute('TargetVersion')
        }
        $sharedLicensing = $xml.SelectSingleNode("/Configuration/Property[@Name='SharedComputerLicensing']")
        if ($null -eq $sharedLicensing) {
            $sharedLicensing = $xml.CreateElement('Property')
            $sharedLicensing.SetAttribute('Name', 'SharedComputerLicensing')
            $null = $xml.DocumentElement.AppendChild($sharedLicensing)
        }
        $sharedLicensing.SetAttribute('Value', $(if ($ImportFor -eq 'Multi-session') { '1' } else { '0' }))
        $tenantProperty = $xml.SelectSingleNode("/Configuration/Property[@Name='TenantId']")
        if ($null -eq $tenantProperty) {
            $tenantProperty = $xml.CreateElement('Property')
            $tenantProperty.SetAttribute('Name', 'TenantId')
            $null = $xml.DocumentElement.AppendChild($tenantProperty)
        }
        $tenantProperty.SetAttribute('Value', $TenantId)
        $setupSettings = $xml.SelectSingleNode("/Configuration/AppSettings/Setup[@Name='Company']")
        if ($null -eq $setupSettings) {
            $setupSettings = $xml.SelectSingleNode('/Configuration/AppSettings/Setup[not(@Name)]')
        }
        if ($null -eq $setupSettings) {
            $appSettings = $xml.SelectSingleNode('/Configuration/AppSettings')
            if ($null -eq $appSettings) {
                $appSettings = $xml.CreateElement('AppSettings')
                $null = $xml.DocumentElement.AppendChild($appSettings)
            }
            $setupSettings = $xml.CreateElement('Setup')
            $null = $appSettings.AppendChild($setupSettings)
        }
        $setupSettings.SetAttribute('Name', 'Company')
        $setupSettings.SetAttribute('Value', $CompanyName)
        $xml.Save($installXmlPath)

        $appJsonPath = Join-Path -Path $sourcePath -ChildPath 'App.json'
        if ($null -ne $appJson.PackageInformation) {
            $appJson.PackageInformation.Version = $result.Version
            $appJson.PackageInformation.SetupFile = 'setup.exe'
        }
        if ($null -ne $appJson.Program) {
            $appJson.Program.InstallCommand = 'setup.exe /configure Install-Microsoft365Apps.xml'
            $appJson.Program.UninstallCommand = 'setup.exe /configure Uninstall-Microsoft365Apps.xml'
        }
        if ($null -ne $appJson.Information) {
            $appJson.Information.DisplayName = (Read-EwM365Configuration -Path $installXmlPath).DisplayName
            $appJson.Information.PSPackageFactoryGuid = $configuration.ConfigId
            $descriptionNote = "Office channel version: $($result.Version) | SharedComputerLicensing: $(if ($ImportFor -eq 'Multi-session') { '1' } else { '0' }) | Configuration XML: $(Split-Path -Path $ConfigurationPath -Leaf)"
            $existingDescription = [string]$appJson.Information.Description
            $appJson.Information.Description = if ([string]::IsNullOrWhiteSpace($existingDescription)) {
                $descriptionNote
            }
            else {
                "$existingDescription`n$descriptionNote"
            }
        }
        if ($null -ne $appJson.RequirementRule) {
            $appJson.RequirementRule.Architecture = $configuration.Architecture
        }
        foreach ($rule in @($appJson.DetectionRule)) {
            switch ([string](Get-EwFirstPropertyValue -InputObject $rule -Name 'ValueName')) {
                'VersionToReport' {
                    $rule.Value = $result.Version
                    $rule | Add-Member -NotePropertyName DetectionMethod -NotePropertyValue 'VersionComparison' -Force
                    $rule | Add-Member -NotePropertyName Operator -NotePropertyValue 'greaterThanOrEqual' -Force
                }
                'ProductReleaseIds' { $rule.Value = ($configuration.Products -split '\s*,\s*' | Where-Object { $_ }) -join ',' }
                'SharedComputerLicensing' { $rule.Value = if ($ImportFor -eq 'Multi-session') { '1' } else { '0' } }
            }
        }
        Write-EwJsonFile -Path $appJsonPath -InputObject $appJson

        if ($Provider -eq 'Nerdio') {
            $zipPath = Join-Path -Path $buildOutputPath -ChildPath 'Microsoft365Apps.zip'
            $filesToZip = @($setupFile, $installXmlPath)
            if (Test-Path -LiteralPath $uninstallXmlPath -PathType Leaf) {
                $filesToZip += $uninstallXmlPath
            }
            Compress-Archive -LiteralPath $filesToZip `
                -DestinationPath $zipPath -Force -ErrorAction Stop
            $result.PackagePath = $zipPath
        }
        else {
            $result.PackagePath = Invoke-EwIntunePackageBuilder -SourceFolder $sourcePath `
                -SetupFile 'setup.exe' -OutputFolder $buildOutputPath
        }
        if (-not (Test-Path -LiteralPath $result.PackagePath -PathType Leaf)) {
            throw "Expected package was not created: $($result.PackagePath)"
        }
        if ($null -ne $Plan) { Assert-EwM365BuildPlan -Plan $Plan }
        $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
        $destination = Join-Path -Path $outputPath -ChildPath ([IO.Path]::GetFileName($result.PackagePath))
        if ((Test-Path -LiteralPath $destination) -and -not $Force) {
            throw "A package already exists at '$destination'. Confirm replacement and use -Force."
        }
        [IO.File]::Move($result.PackagePath, $destination, [bool]$Force)
        $result.PackagePath = $destination
        $result.Succeeded = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}
