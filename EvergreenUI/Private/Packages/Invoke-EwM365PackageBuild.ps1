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
        [string]$AppJsonTemplatePath
    )

    $configuration = Read-EwM365Configuration -Path $ConfigurationPath
    $name = $configuration.DisplayName
    $safeName = [regex]::Replace($name, '[\\/:*?"<>|]', '_').Trim('_')
    $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Source"
    $outputPath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Output"
    $result = [PSCustomObject]@{
        Succeeded = $false
        Provider = $Provider
        PackagePath = ''
        SetupFile = 'setup.exe'
        Version = ''
        SourcePath = $sourcePath
        OutputPath = $outputPath
        Error = ''
    }

    try {
        $artifact = Get-EwM365SetupArtifact -Channel $Channel
        $result.Version = [string]$artifact.Version
        $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
        $downloaded = @(Invoke-EwArtifactSave -Artifact $artifact -Path $sourcePath -Force)
        if ($downloaded.Count -eq 0) {
            throw 'Evergreen returned no Microsoft 365 setup.exe download result.'
        }

        $setupFile = Join-Path -Path $sourcePath -ChildPath 'setup.exe'
        if (-not (Test-Path -LiteralPath $setupFile -PathType Leaf)) {
            $downloadedSetup = $downloaded | Where-Object { [string]$_.Name -ieq 'setup.exe' } | Select-Object -First 1
            if ($null -eq $downloadedSetup -or -not (Test-Path -LiteralPath $downloadedSetup.FullName -PathType Leaf)) {
                throw "setup.exe was not found in '$sourcePath' after the Evergreen download."
            }
            $setupFile = [string]$downloadedSetup.FullName
        }

        $installXmlPath = Join-Path -Path $sourcePath -ChildPath 'Install-Microsoft365Apps.xml'
        Copy-Item -LiteralPath $ConfigurationPath -Destination $installXmlPath -Force -ErrorAction Stop
        $uninstallSource = Join-Path -Path $ConfigurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml'
        $uninstallXmlPath = Join-Path -Path $sourcePath -ChildPath 'Uninstall-Microsoft365Apps.xml'
        if ($Provider -eq 'Nerdio' -and -not (Test-Path -LiteralPath $uninstallSource -PathType Leaf)) {
            throw "Uninstall-Microsoft365Apps.xml was not found in '$ConfigurationRoot'."
        }
        if (Test-Path -LiteralPath $uninstallSource -PathType Leaf) {
            Copy-Item -LiteralPath $uninstallSource -Destination $uninstallXmlPath -Force -ErrorAction Stop
        }

        [xml]$xml = Get-Content -LiteralPath $installXmlPath -Raw -ErrorAction Stop
        if ($null -eq $xml.Configuration.Add) {
            throw "The Office Deployment Tool configuration '$ConfigurationPath' has no Configuration.Add element."
        }
        $xml.Configuration.Add.Channel = $Channel
        foreach ($property in @($xml.Configuration.Property)) {
            switch ([string]$property.Name) {
                'TenantId' { $property.Value = $TenantId }
                'SharedComputerLicensing' { $property.Value = if ($ImportFor -eq 'Multi-session') { '1' } else { '0' } }
            }
        }
        if ($null -ne $xml.Configuration.AppSettings -and $null -ne $xml.Configuration.AppSettings.Setup) {
            $xml.Configuration.AppSettings.Setup.Value = $CompanyName
        }
        $xml.Save($installXmlPath)

        try {
            $versionInfo = (Get-Item -LiteralPath $setupFile -ErrorAction Stop).VersionInfo
            $fileVersion = if (-not [string]::IsNullOrWhiteSpace([string]$versionInfo.FileVersion)) {
                [string]$versionInfo.FileVersion
            }
            else {
                [string]$versionInfo.ProductVersion
            }
            if (-not [string]::IsNullOrWhiteSpace($fileVersion)) {
                $result.Version = $fileVersion
            }
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Could not read setup.exe file version; using Evergreen version: $($_.Exception.Message)"
        }

        if ([string]::IsNullOrWhiteSpace($AppJsonTemplatePath)) {
            $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $AppJsonTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Resources\m365-app.json'
        }
        if (-not (Test-Path -LiteralPath $AppJsonTemplatePath -PathType Leaf)) {
            throw "App.json template was not found: $AppJsonTemplatePath"
        }
        $appJsonPath = Join-Path -Path $sourcePath -ChildPath 'App.json'
        $appJson = Get-Content -LiteralPath $AppJsonTemplatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $appJson.PackageInformation) {
            $appJson.PackageInformation.Version = $result.Version
            $appJson.PackageInformation.SetupFile = 'setup.exe'
        }
        if ($null -ne $appJson.Program) {
            $appJson.Program.InstallCommand = 'setup.exe /configure Install-Microsoft365Apps.xml'
            $appJson.Program.UninstallCommand = 'setup.exe /configure Uninstall-Microsoft365Apps.xml'
        }
        if ($null -ne $appJson.Information) {
            $appJson.Information.DisplayName = $name
            $appJson.Information.PSPackageFactoryGuid = $configuration.ConfigId
            $descriptionNote = "Setup.exe version: $($result.Version) | SharedComputerLicensing: $(if ($ImportFor -eq 'Multi-session') { '1' } else { '0' }) | Configuration XML: $(Split-Path -Path $ConfigurationPath -Leaf)"
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
            switch ([string]$rule.ValueName) {
                'VersionToReport' { $rule.Value = $result.Version }
                'ProductReleaseIds' { $rule.Value = ($configuration.Products -split '\s*,\s*' | Where-Object { $_ }) -join ',' }
                'SharedComputerLicensing' { $rule.Value = if ($ImportFor -eq 'Multi-session') { '1' } else { '0' } }
            }
        }
        Write-EwJsonFile -Path $appJsonPath -InputObject $appJson

        if ($Provider -eq 'Nerdio') {
            $zipPath = Join-Path -Path $outputPath -ChildPath 'Microsoft365Apps.zip'
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
                -SetupFile 'setup.exe' -OutputFolder $outputPath
        }
        if (-not (Test-Path -LiteralPath $result.PackagePath -PathType Leaf)) {
            throw "Expected package was not created: $($result.PackagePath)"
        }
        $result.Succeeded = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}
