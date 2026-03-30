#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads setup.exe for Microsoft 365 Apps via Evergreen, updates the configuration XML,
    and builds an .intunewin package.

.DESCRIPTION
    Uses Get-EvergreenApp -Name Microsoft365Apps to retrieve the latest setup.exe for the
    specified channel. Copies the configuration XML (renamed to Install-Microsoft365Apps.xml)
    and Uninstall-Microsoft365Apps.xml to a working source folder, updates the XML with the
    caller-supplied Channel, TenantId, and CompanyName, then calls New-IntuneWin32AppPackage
    to produce the .intunewin file.

.PARAMETER ConfigRow
    A configuration row object returned by Get-M365AppConfigurations, containing FileName,
    FilePath, DisplayName, and ConfigId.

.PARAMETER ConfigDirectoryPath
    Path to the directory containing the M365 XML configuration files (must include
    Uninstall-Microsoft365Apps.xml for the uninstall command to function).

.PARAMETER Channel
    The update channel to set in the XML (e.g. MonthlyEnterprise, Current).

.PARAMETER CompanyName
    The company name written to the AppSettings/Setup element in the XML.

.PARAMETER TenantId
    The Entra ID tenant ID written to the TenantId Property element in the XML.

.PARAMETER WorkingPath
    Root working directory. A subdirectory named after the package is created here.

.PARAMETER SyncHash
    Synchronized hashtable used by Write-UILog for thread-safe UI log output.

.OUTPUTS
    PSCustomObject with properties: Succeeded, IntuneWinPath, SetupFileUsed, Version,
    SourcePath, OutputPath, Error.
#>
function Invoke-M365AppPackageBuild {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ConfigRow,

        [Parameter(Mandatory)]
        [string]$ConfigDirectoryPath,

        [Parameter(Mandatory)]
        [string]$Channel,

        [Parameter(Mandatory)]
        [string]$CompanyName,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$WorkingPath,

        [Parameter()]
        [string]$AppJsonTemplatePath = '',

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $result = [PSCustomObject]@{
        Succeeded     = $false
        IntuneWinPath = ''
        SetupFileUsed = 'setup.exe'
        Version       = ''
        SourcePath    = ''
        OutputPath    = ''
        AppJsonPath   = ''
        Error         = ''
    }

    try {
        # Resolve latest Evergreen entry for the requested channel
        Write-UILog -SyncHash $SyncHash -Message "M365: Querying Evergreen for Microsoft365Apps channel '$Channel'..." -Level Info
        $evergreenRows = Get-EvergreenApp -Name 'Microsoft365Apps' -ErrorAction Stop
        $channelRow    = $evergreenRows | Where-Object { $_.Channel -eq $Channel } |
            Sort-Object -Property { [System.Version]$_.Version } -Descending |
            Select-Object -First 1

        if ($null -eq $channelRow) {
            throw "No Evergreen entry found for Microsoft365Apps channel '$Channel'."
        }

        $version = [string]$channelRow.Version
        Write-UILog -SyncHash $SyncHash -Message "M365: Latest version for '$Channel': $version" -Level Info

        # Sanitise display name for use as a folder name
        $safeName  = ($ConfigRow.DisplayName -replace '[\\/:*?"<>|]', '_').Trim('_')
        $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Source"
        $outputPath = Join-Path -Path $WorkingPath -ChildPath "$safeName\Output"

        foreach ($dir in @($sourcePath, $outputPath)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                $null = New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop
            }
        }

        $result.SourcePath = $sourcePath
        $result.OutputPath = $outputPath

        # Download setup.exe via Evergreen
        Write-UILog -SyncHash $SyncHash -Message 'M365: Downloading setup.exe via Evergreen...' -Level Info
        $null = $channelRow | Save-EvergreenApp -CustomPath $sourcePath -ErrorAction Stop

        # Verify setup.exe was downloaded
        $setupFile = Join-Path -Path $sourcePath -ChildPath 'setup.exe'
        if (-not (Test-Path -LiteralPath $setupFile -PathType Leaf)) {
            throw "setup.exe was not found in '$sourcePath' after download."
        }
        Write-UILog -SyncHash $SyncHash -Message "M365: setup.exe downloaded to '$sourcePath'." -Level Info

        # Copy and rename the install config XML
        $installXmlDest = Join-Path -Path $sourcePath -ChildPath 'Install-Microsoft365Apps.xml'
        Copy-Item -LiteralPath $ConfigRow.FilePath -Destination $installXmlDest -Force -ErrorAction Stop

        # Copy the uninstall XML if present
        $uninstallSrc = Join-Path -Path $ConfigDirectoryPath -ChildPath 'Uninstall-Microsoft365Apps.xml'
        if (Test-Path -LiteralPath $uninstallSrc -PathType Leaf) {
            $uninstallDest = Join-Path -Path $sourcePath -ChildPath 'Uninstall-Microsoft365Apps.xml'
            Copy-Item -LiteralPath $uninstallSrc -Destination $uninstallDest -Force -ErrorAction Stop
        }

        # Update Install-Microsoft365Apps.xml with caller-supplied values
        Write-UILog -SyncHash $SyncHash -Message 'M365: Updating configuration XML with channel, tenant ID, and company name...' -Level Info
        [xml]$xml = Get-Content -LiteralPath $installXmlDest -Raw -ErrorAction Stop

        # Channel
        $xml.Configuration.Add.Channel = $Channel

        # TenantId Property
        $tenantProp = $xml.Configuration.Property | Where-Object { $_.Name -eq 'TenantId' } | Select-Object -First 1
        if ($null -ne $tenantProp) {
            $tenantProp.Value = $TenantId
        }

        # CompanyName via AppSettings/Setup
        if ($null -ne $xml.Configuration.AppSettings -and $null -ne $xml.Configuration.AppSettings.Setup) {
            $xml.Configuration.AppSettings.Setup.Value = $CompanyName
        }

        $xml.Save($installXmlDest)
        Write-UILog -SyncHash $SyncHash -Message 'M365: Configuration XML updated.' -Level Info

        # Build .intunewin package
        Write-UILog -SyncHash $SyncHash -Message 'M365: Building .intunewin package...' -Level Info
        $null = New-IntuneWin32AppPackage `
            -SourceFolder $sourcePath `
            -SetupFile    'setup.exe' `
            -OutputFolder $outputPath `
            -Force        `
            -ErrorAction  Stop

        # Locate the produced .intunewin file
        $intuneWinFile = Get-ChildItem -LiteralPath $outputPath -Filter '*.intunewin' -File |
            Select-Object -First 1

        if ($null -eq $intuneWinFile) {
            throw "No .intunewin file was found in '$outputPath' after packaging."
        }

        Write-UILog -SyncHash $SyncHash -Message "M365: Package built: $($intuneWinFile.Name)" -Level Info

        $result.IntuneWinPath = $intuneWinFile.FullName
        $result.Version       = $version

        # Copy and update App.json from the template
        if (-not [string]::IsNullOrWhiteSpace($AppJsonTemplatePath) -and
            (Test-Path -LiteralPath $AppJsonTemplatePath -PathType Leaf)) {

            Write-UILog -SyncHash $SyncHash -Message 'M365: Writing App.json from template...' -Level Info
            $appJsonDest = Join-Path -Path $sourcePath -ChildPath 'App.json'
            Copy-Item -LiteralPath $AppJsonTemplatePath -Destination $appJsonDest -Force -ErrorAction Stop

            $appJson = Get-Content -LiteralPath $appJsonDest -Raw -ErrorAction Stop | ConvertFrom-Json

            # Package information
            $appJson.PackageInformation.Version = $version

            # App information
            $appJson.Information.DisplayName         = $ConfigRow.DisplayName
            $appJson.Information.PSPackageFactoryGuid = $ConfigRow.ConfigId

            # Program commands
            $appJson.Program.InstallCommand   = 'setup.exe /configure Install-Microsoft365Apps.xml'
            $appJson.Program.UninstallCommand = 'setup.exe /configure Uninstall-Microsoft365Apps.xml'

            # Requirement rule architecture
            $appJson.RequirementRule.Architecture = $ConfigRow.Architecture

            # Detection rules - normalise product IDs (strip spaces around commas)
            $normalizedProducts = (([string]$ConfigRow.Products) -split '\s*,\s*' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne '' }) -join ','
            $sclValue = if ([bool]$ConfigRow.IsVdi) { '1' } else { '0' }

            foreach ($rule in $appJson.DetectionRule) {
                switch ([string]$rule.ValueName) {
                    'VersionToReport'        { $rule.Value = $version }
                    'ProductReleaseIds'      { $rule.Value = $normalizedProducts }
                    'SharedComputerLicensing' { $rule.Value = $sclValue }
                }
            }

            $appJson | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $appJsonDest -Encoding UTF8 -ErrorAction Stop

            $result.AppJsonPath = $appJsonDest
            Write-UILog -SyncHash $SyncHash -Message "M365: App.json written to '$appJsonDest'." -Level Info
        }

        $result.Succeeded = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-UILog -SyncHash $SyncHash -Message "M365: Package build failed: $($_.Exception.Message)" -Level Error
    }

    return $result
}
