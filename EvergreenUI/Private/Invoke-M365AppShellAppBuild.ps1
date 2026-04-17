#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads setup.exe for Microsoft 365 Apps via Evergreen, updates the
    configuration XML, and creates a zip archive for Nerdio Shell App import.

.DESCRIPTION
    Uses Get-EvergreenApp -Name Microsoft365Apps to retrieve the latest setup.exe
    for the specified channel. Copies the configuration XML (renamed to
    Install-Microsoft365Apps.xml) and Uninstall-Microsoft365Apps.xml to a working
    source folder, updates the XML with Channel, TenantId, and CompanyName, then
    calls Compress-Archive to produce a zip containing setup.exe,
    Install-Microsoft365Apps.xml, and Uninstall-Microsoft365Apps.xml.

    No IntuneWin32App module dependency.

.PARAMETER ConfigRow
    A configuration row object returned by Get-M365AppConfigurations, containing
    FileName, FilePath, DisplayName, and ConfigId.

.PARAMETER ConfigDirectoryPath
    Path to the directory containing the M365 XML configuration files. Must
    include Uninstall-Microsoft365Apps.xml.

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
    PSCustomObject with properties: Succeeded, ZipPath, Version, SourcePath, Error.
#>
function Invoke-M365AppShellAppBuild {
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

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $fail = {
        param([string]$Msg)
        Write-UILog -SyncHash $SyncHash -Message "M365 Shell App build: $Msg" -Level Error
        return [PSCustomObject]@{
            Succeeded  = $false
            ZipPath    = ''
            Version    = ''
            SourcePath = ''
            Error      = $Msg
        }
    }

    try {
        # Resolve latest Evergreen entry for the requested channel
        Write-UILog -SyncHash $SyncHash -Message "M365: Querying Evergreen for Microsoft365Apps channel '$Channel'..." -Level Info
        $evergreenRows = Get-EvergreenApp -Name 'Microsoft365Apps' -ErrorAction Stop
        $channelRow    = $evergreenRows |
            Where-Object { $_.Channel -eq $Channel } |
            Sort-Object -Property { [System.Version]$_.Version } -Descending |
            Select-Object -First 1

        if ($null -eq $channelRow) {
            return (& $fail "No Evergreen entry found for Microsoft365Apps channel '$Channel'.")
        }

        $version = [string]$channelRow.Version
        Write-UILog -SyncHash $SyncHash -Message "M365: Latest version for '$Channel': $version" -Level Info

        # Sanitise display name for use as a folder name
        $safeName   = ($ConfigRow.DisplayName -replace '[\\/:*?"<>|]', '_').Trim('_')
        $sourcePath = Join-Path -Path $WorkingPath -ChildPath ($safeName + '\Source')

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        }

        # Download setup.exe via Evergreen
        Write-UILog -SyncHash $SyncHash -Message 'M365: Downloading setup.exe via Evergreen...' -Level Info
        $null = $channelRow | Save-EvergreenApp -CustomPath $sourcePath -ErrorAction Stop

        $setupFile = Join-Path -Path $sourcePath -ChildPath 'setup.exe'
        if (-not (Test-Path -LiteralPath $setupFile -PathType Leaf)) {
            return (& $fail "setup.exe was not found in '$sourcePath' after download.")
        }
        Write-UILog -SyncHash $SyncHash -Message "M365: setup.exe downloaded to '$sourcePath'." -Level Info

        # Copy and rename the install config XML
        $installXmlDest = Join-Path -Path $sourcePath -ChildPath 'Install-Microsoft365Apps.xml'
        Copy-Item -LiteralPath $ConfigRow.FilePath -Destination $installXmlDest -Force -ErrorAction Stop

        # Copy the uninstall XML -- required for zip
        $uninstallSrc = Join-Path -Path $ConfigDirectoryPath -ChildPath 'Uninstall-Microsoft365Apps.xml'
        if (-not (Test-Path -LiteralPath $uninstallSrc -PathType Leaf)) {
            return (& $fail "Uninstall-Microsoft365Apps.xml not found in '$ConfigDirectoryPath'.")
        }
        $uninstallDest = Join-Path -Path $sourcePath -ChildPath 'Uninstall-Microsoft365Apps.xml'
        Copy-Item -LiteralPath $uninstallSrc -Destination $uninstallDest -Force -ErrorAction Stop

        # Update Install-Microsoft365Apps.xml with caller-supplied values
        Write-UILog -SyncHash $SyncHash -Message 'M365: Updating configuration XML with channel, tenant ID, and company name...' -Level Info
        [xml]$xml = Get-Content -LiteralPath $installXmlDest -Raw -ErrorAction Stop

        $xml.Configuration.Add.Channel = $Channel

        $tenantProp = $xml.Configuration.Property |
            Where-Object { $_.Name -eq 'TenantId' } |
            Select-Object -First 1
        if ($null -ne $tenantProp) {
            $tenantProp.Value = $TenantId
        }

        if ($null -ne $xml.Configuration.AppSettings -and $null -ne $xml.Configuration.AppSettings.Setup) {
            $xml.Configuration.AppSettings.Setup.Value = $CompanyName
        }

        $xml.Save($installXmlDest)
        Write-UILog -SyncHash $SyncHash -Message 'M365: Configuration XML updated.' -Level Info

        # Build zip archive containing setup.exe and both XMLs
        $zipPath = Join-Path -Path $WorkingPath -ChildPath ($safeName + '\Microsoft365Apps.zip')
        $zipDir  = Split-Path -Path $zipPath -Parent
        if (-not (Test-Path -LiteralPath $zipDir -PathType Container)) {
            $null = New-Item -Path $zipDir -ItemType Directory -Force -ErrorAction Stop
        }

        if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop
        }

        Write-UILog -SyncHash $SyncHash -Message 'M365: Creating zip archive...' -Level Info

        $filesToZip = @(
            $setupFile
            $installXmlDest
            $uninstallDest
        )
        Compress-Archive -Path $filesToZip -DestinationPath $zipPath -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
            return (& $fail "Zip archive was not created at '$zipPath'.")
        }

        Write-UILog -SyncHash $SyncHash -Message "M365: Zip archive created: $zipPath" -Level Info

        return [PSCustomObject]@{
            Succeeded  = $true
            ZipPath    = $zipPath
            Version    = $version
            SourcePath = $sourcePath
            Error      = ''
        }
    }
    catch {
        return (& $fail $_.Exception.Message)
    }
}
