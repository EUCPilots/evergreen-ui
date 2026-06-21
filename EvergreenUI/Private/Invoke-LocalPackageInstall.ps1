#Requires -Version 5.1
<#!
.SYNOPSIS
    Downloads/stages installer content and executes local install command.

.DESCRIPTION
    Uses the same package definition source model as Intune packaging but runs
    Program.InstallCommand locally instead of creating/importing .intunewin.

.PARAMETER DefinitionPath
    Full path to App.json.

.PARAMETER DefinitionObject
    Parsed App.json object.

.PARAMETER WorkingPath
    Root working directory for staging content.

.PARAMETER LatestVersionResult
    Result object from Get-InstallPackageLatestVersion.

.PARAMETER SyncHash
    Shared UI synchronized hashtable for Write-UILog.

.OUTPUTS
    PSCustomObject with:
        Succeeded          : bool
        ExitCode           : int
        WorkingDirectory   : string
        DownloadedVersion  : string
        InstallCommand     : string
        Error              : string
!#>
function Invoke-LocalPackageInstall {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$DefinitionObject,

        [Parameter(Mandatory)]
        [string]$WorkingPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$LatestVersionResult,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    $fail = {
        param([string]$Message)
        return [PSCustomObject]@{
            Succeeded         = $false
            ExitCode          = -1
            WorkingDirectory  = ''
            DownloadedVersion = ''
            InstallCommand    = ''
            Error             = $Message
        }
    }

    if ([string]::IsNullOrWhiteSpace($DefinitionPath) -or -not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition path not found: $DefinitionPath")
    }

    if ($null -eq $DefinitionObject) {
        return (& $fail 'Definition object is null.')
    }

    if ([string]::IsNullOrWhiteSpace($WorkingPath)) {
        return (& $fail 'WorkingPath is empty.')
    }

    if ($null -eq $LatestVersionResult -or -not [bool]$LatestVersionResult.Succeeded) {
        $err = if ($null -eq $LatestVersionResult) { 'Unknown latest version error.' } else { [string]$LatestVersionResult.Error }
        return (& $fail "Latest version resolution failed: $err")
    }

    $appFolderName = Get-SafeFolderName -DefinitionPath $DefinitionPath
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = [string]$DefinitionObject.Application.Name
        $appFolderName = [System.Text.RegularExpressions.Regex]::Replace($appFolderName, '[^\w\-\.]', '_').Trim('_')
    }
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = 'InstallPackage'
    }

    # Working directory for this app: <WorkingPath>\<AppFolderName>
    $appWorkingDir = Join-Path -Path $WorkingPath -ChildPath $appFolderName
    if (-not (Test-Path -LiteralPath $appWorkingDir -PathType Container)) {
        try {
            $null = New-Item -Path $appWorkingDir -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            return (& $fail "Failed to create working directory '$appWorkingDir': $($_.Exception.Message)")
        }
    }

    $definitionDir = [System.IO.Path]::GetDirectoryName($DefinitionPath)
    $definitionParentDir = [System.IO.Path]::GetDirectoryName($definitionDir)
    $definitionSourceDir = Join-Path -Path $definitionDir -ChildPath 'Source'
    $sharedInstallPs1Source = if ([string]::IsNullOrWhiteSpace($definitionParentDir)) {
        ''
    }
    else {
        Join-Path -Path $definitionParentDir -ChildPath 'Install.ps1'
    }

    # Download the latest installer first so we know the exact directory
    # Save-EvergreenApp -Path creates a subdirectory tree; capture the result
    # to resolve where the installer actually landed.
    $downloadDir = $appWorkingDir
    $downloadResults = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$LatestVersionResult.URI)) {
        try {
            Write-UILog -SyncHash $SyncHash -Message "Install: downloading latest installer to '$appWorkingDir'." -Level Info
            $downloadResults = @($LatestVersionResult.ResolvedArtifact | Save-EvergreenApp -Path $appWorkingDir -ErrorAction Stop)
            if ($downloadResults.Count -gt 0) {
                $downloadDir = [System.IO.Path]::GetDirectoryName($downloadResults[0].FullName)
                Write-UILog -SyncHash $SyncHash -Message "Install: installer saved to '$downloadDir'." -Level Info
            }
        }
        catch {
            return (& $fail "Failed to download installer: $($_.Exception.Message)")
        }
    }

    # Copy Install.ps1 to the download directory. Prefer the Source folder,
    # then the package root, then the shared intune template used by
    # evergreen-packages package definitions.
    $installPs1Source = @(
        (Join-Path -Path $definitionSourceDir -ChildPath 'Install.ps1')
        (Join-Path -Path $definitionDir -ChildPath 'Install.ps1')
        $sharedInstallPs1Source
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath $_ -PathType Leaf)
    } | Select-Object -First 1

    $installPs1Target = Join-Path -Path $downloadDir -ChildPath 'Install.ps1'
    if (-not [string]::IsNullOrWhiteSpace([string]$installPs1Source)) {
        try {
            Write-UILog -SyncHash $SyncHash -Message "Install: copying Install.ps1 from '$installPs1Source' to '$installPs1Target'." -Level Info
            Copy-Item -LiteralPath $installPs1Source -Destination $installPs1Target -Force -ErrorAction Stop
        }
        catch {
            return (& $fail "Failed to copy Install.ps1: $($_.Exception.Message)")
        }
    }

    # Copy support files from <Package>\Source\ into the download directory
    if (Test-Path -LiteralPath $definitionSourceDir -PathType Container) {
        try {
            Write-UILog -SyncHash $SyncHash -Message "Install: copying support files from '$definitionSourceDir' to '$downloadDir'." -Level Info
            Copy-Item -Path "$definitionSourceDir\*" -Destination $downloadDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            return (& $fail "Failed to copy source content: $($_.Exception.Message)")
        }
    }

    # Update version fields in the copied Install.json so Install.ps1 finds the
    # correct installer filename and records the correct version.
    $installJsonTarget = Join-Path -Path $downloadDir -ChildPath 'Install.json'
    if (Test-Path -LiteralPath $installJsonTarget -PathType Leaf) {
        try {
            $installJson = Get-Content -LiteralPath $installJsonTarget -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $installJson.PackageInformation.Version = [string]$LatestVersionResult.Version
            if ($downloadResults.Count -gt 0) {
                $installerName = [System.IO.Path]::GetFileName($downloadResults[0].FullName)
                $installJson.PackageInformation.SetupFile = $installerName
            }
            $installJson | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $installJsonTarget -Encoding UTF8 -ErrorAction Stop
            Write-UILog -SyncHash $SyncHash -Message "Install: updated Install.json version to '$([string]$LatestVersionResult.Version)'." -Level Info
        }
        catch {
            # best-effort - failure here must not abort the install
            Write-UILog -SyncHash $SyncHash -Message "Install: failed to update Install.json: $($_.Exception.Message)" -Level Warn
        }
    }

    # Determine install command: prefer Install.ps1, fall back to Program.InstallCommand
    $useInstallPs1 = Test-Path -LiteralPath $installPs1Target -PathType Leaf
    $fallbackCommand = [string]$DefinitionObject.Program.InstallCommand

    if ($useInstallPs1) {
        Write-UILog -SyncHash $SyncHash -Message "Install method: Install.ps1 at '$installPs1Target'." -Level Info
    }
    elseif (-not [string]::IsNullOrWhiteSpace($fallbackCommand)) {
        Write-UILog -SyncHash $SyncHash -Message "Install method: Program.InstallCommand from App.json (no Install.ps1 found)." -Level Info
    }
    else {
        return (& $fail 'No Install.ps1 found in the package directory, Source directory, or shared package template location, and Program.InstallCommand is missing from App.json.')
    }

    $process = $null
    try {
        if ($useInstallPs1) {
            $escapedWorkingDir = $downloadDir.Replace("'", "''")
            $installScriptCommand = "Set-Location -LiteralPath '$escapedWorkingDir'; & '.\\Install.ps1'"
            Write-UILog -SyncHash $SyncHash -Message "Install: running Install.ps1 from '$downloadDir'." -Level Cmd
            $process = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NonInteractive', '-Command', $installScriptCommand `
                -WorkingDirectory $downloadDir -Wait -PassThru -ErrorAction Stop
        }
        else {
            Write-UILog -SyncHash $SyncHash -Message "Install: executing command '$fallbackCommand'." -Level Cmd
            $process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $fallbackCommand `
                -WorkingDirectory $downloadDir -Wait -PassThru -ErrorAction Stop
        }
    }
    catch {
        return (& $fail "Failed to execute install: $($_.Exception.Message)")
    }

    $exitCode = if ($null -eq $process) { -1 } else { [int]$process.ExitCode }
    $succeeded = $exitCode -eq 0 -or $exitCode -eq 3010

    if (-not $succeeded) {
        return (& $fail "Installer exited with code $exitCode.")
    }

    $resolvedCommand = if ($useInstallPs1) { "powershell.exe -Command Set-Location -LiteralPath '$downloadDir'; & '.\\Install.ps1'" } else { $fallbackCommand }

    return [PSCustomObject]@{
        Succeeded         = $true
        ExitCode          = $exitCode
        WorkingDirectory  = $downloadDir
        DownloadedVersion = [string]$LatestVersionResult.Version
        InstallCommand    = $resolvedCommand
        Error             = ''
    }
}
