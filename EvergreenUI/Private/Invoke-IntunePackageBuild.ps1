#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads the latest installer for an App.json definition and creates the
    .intunewin package using IntuneWin32App's New-IntuneWin32AppPackage.

.DESCRIPTION
    Given a comparison row (containing the DefinitionPath and DefinitionObject)
    plus a working path, this function:
      1. Resolves the latest installer version via Get-IntunePackageLatestVersion
      2. Creates working sub-directories under WorkingPath
      3. Copies the Source folder from the definition directory if it exists
      4. Downloads the installer with Save-EvergreenApp
      5. Calls New-IntuneWin32AppPackage to produce the .intunewin file

    New-IntuneWin32AppPackage requires no remote authentication; it wraps
    IntuneWinAppUtil.exe locally. The IntuneWin32App module must already be
    imported in the calling session.

    All progress messages are written via Write-UILog; pass $SyncHash so
    messages appear in the UI log panel.

.PARAMETER ComparisonRow
    A comparison row object that must contain DefinitionPath (full path to
    App.json) and DefinitionObject (the parsed App.json PSCustomObject).

.PARAMETER WorkingPath
    Root working path under which per-app sub-directories are created.

.PARAMETER SyncHash
    The shared UI synchronised hashtable used by Write-UILog.

.OUTPUTS
    PSCustomObject with:
        Succeeded         : bool
        IntuneWinPath     : string  - full path to the created .intunewin file
        SetupFileUsed     : string  - setup file name passed to New-IntuneWin32AppPackage
        DownloadedVersion : string  - version string of the downloaded artifact
        ResolvedArtifact  : object  - the raw artifact row returned by Evergreen
        AppFolderName     : string  - sanitized folder name used under WorkingPath
        SourcePath        : string  - path to the download/staging folder
        OutputPath        : string  - path to the .intunewin output folder
        Error             : string  - populated on failure
#>
function Invoke-IntunePackageBuild {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ComparisonRow,

        [Parameter(Mandatory)]
        [string]$WorkingPath,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    $fail = {
        param([string]$Msg)
        return [PSCustomObject]@{
            Succeeded         = $false
            IntuneWinPath     = ''
            SetupFileUsed     = ''
            DownloadedVersion = ''
            ResolvedArtifact  = $null
            AppFolderName     = ''
            SourcePath        = ''
            OutputPath        = ''
            Error             = $Msg
        }
    }

    # Resolve definition path and object
    $definitionPath = [string]$ComparisonRow.DefinitionPath
    $definitionObject = $ComparisonRow.DefinitionObject

    if ($null -eq $definitionObject -and -not [string]::IsNullOrWhiteSpace($definitionPath) -and
        (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        $readResult = Read-PackageDefinition -Path $definitionPath
        if (-not $readResult.Succeeded) {
            return (& $fail $readResult.Error)
        }
        $definitionObject = $readResult.Definition
    }

    if ($null -eq $definitionObject) {
        return (& $fail 'No definition object available and no valid definition path provided.')
    }

    # Resolve latest version
    Write-UILog -Message "Resolving latest version from: $([string]$definitionObject.Application.Filter)" -Level Cmd -SyncHash $SyncHash
    $latestResult = Get-IntunePackageLatestVersion -DefinitionObject $definitionObject
    if (-not $latestResult.Succeeded) {
        return (& $fail "Version resolution failed: $($latestResult.Error)")
    }
    Write-UILog -Message "Resolved version: $($latestResult.Version) - $($latestResult.URI)" -Level Info -SyncHash $SyncHash

    # Build a safe folder name from the definition file path
    $appFolderName = ''
    if (-not [string]::IsNullOrWhiteSpace($definitionPath)) {
        $appFolderName = Get-SafeFolderName -DefinitionPath $definitionPath
    }
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = [string]$definitionObject.Application.Name
        $appFolderName = [System.Text.RegularExpressions.Regex]::Replace($appFolderName, '[^\w\-\.]', '_').Trim('_')
    }
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = 'IntunePackage'
    }

    $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$appFolderName\Source"
    $outputPath = Join-Path -Path $WorkingPath -ChildPath "$appFolderName\Output"

    # Create working directories
    foreach ($dir in @($sourcePath, $outputPath)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
            Write-UILog -Message "Created working directory: $dir" -Level Info -SyncHash $SyncHash
        }
    }

    # Remove any stale .intunewin files from the output folder
    $staleFiles = @(Get-ChildItem -LiteralPath $outputPath -Filter '*.intunewin' -ErrorAction SilentlyContinue)
    if ($staleFiles.Count -gt 0) {
        Write-UILog -Message "Removing $($staleFiles.Count) stale .intunewin file(s) from output folder." -Level Info -SyncHash $SyncHash
        $staleFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Copy Source folder content from the definition directory if it exists
    if (-not [string]::IsNullOrWhiteSpace($definitionPath)) {
        $definitionDir = [System.IO.Path]::GetDirectoryName($definitionPath)
        $definitionSrcDir = Join-Path -Path $definitionDir -ChildPath 'Source'
        if (Test-Path -LiteralPath $definitionSrcDir -PathType Container) {
            Write-UILog -Message "Copying source content from '$definitionSrcDir'..." -Level Info -SyncHash $SyncHash
            $null = Copy-Item -Path "$definitionSrcDir\*" -Destination $sourcePath -Recurse -Force -ErrorAction Stop
        }
    }

    # Copy Install.ps1 from module Resources into the staging source path.
    if (Test-Path -Path (Join-Path -Path $sourcePath -ChildPath 'Install.ps1') -PathType Leaf) {
        Write-UILog -Message "Warning: Install.ps1 already exists in source path; skip copy." -Level Warning -SyncHash $SyncHash
    }
    else {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $resourceInstallPs1 = Join-Path -Path $moduleRoot -ChildPath 'Resources\Install.ps1'
        if (Test-Path -LiteralPath $resourceInstallPs1 -PathType Leaf) {
            try {
                Copy-Item -Path $resourceInstallPs1 -Destination $sourcePath -Force -ErrorAction Stop
                Write-UILog -Message "Copied Install.ps1 from module Resources to '$sourcePath'." -Level Info -SyncHash $SyncHash
            }
            catch {
                Write-UILog -Message "Failed to copy Install.ps1 from module Resources: $($_.Exception.Message)" -Level Warning -SyncHash $SyncHash
            }
        }
        else {
            Write-UILog -Message "Install.ps1 not found in module Resources at '$resourceInstallPs1'." -Level Warning -SyncHash $SyncHash
        }
    }

    # Download the latest installer
    $artifact = $latestResult.ResolvedArtifact
    $downloadResults = @()
    if (-not [string]::IsNullOrWhiteSpace($latestResult.URI)) {
        Write-UILog -Message "Downloading installer to '$sourcePath'..." -Level Info -SyncHash $SyncHash
        Write-UILog -Message "Save-EvergreenApp -LiteralPath '$sourcePath'" -Level Cmd -SyncHash $SyncHash
        try {
            $downloadResults = @($artifact | Save-EvergreenApp -LiteralPath $sourcePath -ErrorAction Stop)
            if ($downloadResults.Count -eq 0) {
                return (& $fail 'Save-EvergreenApp completed but returned no results.')
            }
            Write-UILog -Message "Downloaded: $($downloadResults[0].FullName)" -Level Info -SyncHash $SyncHash
        }
        catch {
            return (& $fail "Download failed: $($_.Exception.Message)")
        }
    }
    else {
        Write-UILog -Message 'Artifact has no URI; skipping download (expected pre-staged source).' -Level Warning -SyncHash $SyncHash
    }

    # Copy App.json to the staging source path and update version + SetupFile so the
    # packaged .intunewin contains current metadata.
    if (-not [string]::IsNullOrWhiteSpace($definitionPath) -and (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        $appJsonTarget = Join-Path -Path $sourcePath -ChildPath 'App.json'
        try {
            $readResult = Read-PackageDefinition -Path $definitionPath
            if (-not $readResult.Succeeded) {
                throw $readResult.Error
            }
            $appJson = $readResult.Definition
            $appJson.PackageInformation.Version = [string]$latestResult.Version
            if ($downloadResults.Count -gt 0) {
                $installerName = [System.IO.Path]::GetFileName($downloadResults[0].FullName)
                if (-not [string]::IsNullOrWhiteSpace($installerName)) {
                    $appJson.PackageInformation.SetupFile = $installerName
                }
            }
            $appJson | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $appJsonTarget -Encoding UTF8 -ErrorAction Stop
            Write-UILog -Message "Copied App.json to staging path and updated version to '$([string]$latestResult.Version)'." -Level Info -SyncHash $SyncHash
        }
        catch {
            # best-effort - failure here must not abort packaging
            Write-UILog -Message "Failed to copy/update App.json to staging path: $($_.Exception.Message)" -Level Warn -SyncHash $SyncHash
        }
    }

    # Determine setup file.
    # Prefer the actual downloaded filename; fall back to App.json then SetupType default.
    $setupFile = ''
    if ($downloadResults.Count -gt 0) {
        $setupFile = [System.IO.Path]::GetFileName($downloadResults[0].FullName)
    }
    if ([string]::IsNullOrWhiteSpace($setupFile)) {
        $setupFile = [string]$definitionObject.PackageInformation.SetupFile
    }
    if ([string]::IsNullOrWhiteSpace($setupFile)) {
        $setupType = [string]$definitionObject.PackageInformation.SetupType
        $setupFile = switch ($setupType.ToUpper()) {
            'MSI' { 'Setup.msi' }
            'MSIX' { 'Setup.msix' }
            default { 'Setup.exe' }
        }
        Write-UILog -Message "SetupFile not specified; defaulting to '$setupFile'." -Level Warning -SyncHash $SyncHash
    }

    # Verify IntuneWin32App module is available for packaging
    if (-not (Get-Command -Name 'New-IntuneWin32AppPackage' -ErrorAction SilentlyContinue)) {
        return (& $fail 'New-IntuneWin32AppPackage is not available. Ensure IntuneWin32App module is loaded.')
    }

    Write-UILog -Message "Creating .intunewin: source='$sourcePath' setup='$setupFile' output='$outputPath'" -Level Info -SyncHash $SyncHash
    Write-UILog -Message "New-IntuneWin32AppPackage -SourceFolder `"$sourcePath`" -SetupFile `"$setupFile`" -OutputFolder `"$outputPath`"" -Level Cmd -SyncHash $SyncHash

    $intuneWinPath = ''
    try {
        $packageResult = New-IntuneWin32AppPackage -SourceFolder $sourcePath -SetupFile $setupFile `
            -OutputFolder $outputPath -Force -ErrorAction Stop

        # Different module versions return either:
        # - a plain string path
        # - an object with .Path
        # - an object where .Path can itself be FileInfo-like
        if ($null -ne $packageResult) {
            if ($packageResult -is [string]) {
                $candidatePath = [string]$packageResult
                if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
                    $intuneWinPath = $candidatePath
                }
            }
            elseif ($packageResult.PSObject.Properties.Name -contains 'Path' -and $null -ne $packageResult.Path) {
                $candidatePath = [string]$packageResult.Path
                if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
                    $intuneWinPath = $candidatePath
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($intuneWinPath)) {
            $intuneWinFiles = @(Get-ChildItem -LiteralPath $outputPath -Filter '*.intunewin' -ErrorAction SilentlyContinue)
            if ($intuneWinFiles.Count -eq 0) {
                return (& $fail 'New-IntuneWin32AppPackage completed but no .intunewin file was found in the output folder.')
            }

            # Pick the newest package if multiple files exist.
            $intuneWinPath = @($intuneWinFiles | Sort-Object -Property LastWriteTimeUtc -Descending)[0].FullName
        }
    }
    catch {
        return (& $fail "Packaging failed: $($_.Exception.Message)")
    }

    if (-not (Test-Path -LiteralPath $intuneWinPath -PathType Leaf)) {
        return (& $fail "Expected .intunewin file not found at: $intuneWinPath")
    }

    Write-UILog -Message "Package created successfully: $intuneWinPath" -Level Info -SyncHash $SyncHash

    return [PSCustomObject]@{
        Succeeded         = $true
        IntuneWinPath     = $intuneWinPath
        SetupFileUsed     = $setupFile
        DownloadedVersion = $latestResult.Version
        ResolvedArtifact  = $latestResult.ResolvedArtifact
        AppFolderName     = $appFolderName
        SourcePath        = $sourcePath
        OutputPath        = $outputPath
        Error             = ''
    }
}


