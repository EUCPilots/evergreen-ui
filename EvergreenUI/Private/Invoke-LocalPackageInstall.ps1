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

    $installCommand = [string]$DefinitionObject.Program.InstallCommand
    if ([string]::IsNullOrWhiteSpace($installCommand)) {
        return (& $fail 'Program.InstallCommand is missing from App.json.')
    }

    $appFolderName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($DefinitionPath))
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = [string]$DefinitionObject.Application.Name
    }
    $appFolderName = [System.Text.RegularExpressions.Regex]::Replace($appFolderName, '[^\w\-\.]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($appFolderName)) {
        $appFolderName = 'InstallPackage'
    }

    $sourcePath = Join-Path -Path $WorkingPath -ChildPath "$appFolderName\Source"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        try {
            $null = New-Item -Path $sourcePath -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            return (& $fail "Failed to create source path '$sourcePath': $($_.Exception.Message)")
        }
    }

    try {
        $definitionDir = [System.IO.Path]::GetDirectoryName($DefinitionPath)
        $definitionSourceDir = Join-Path -Path $definitionDir -ChildPath 'Source'
        if (Test-Path -LiteralPath $definitionSourceDir -PathType Container) {
            Write-UILog -SyncHash $SyncHash -Message "Install: copying source content from '$definitionSourceDir'." -Level Info
            Copy-Item -Path "$definitionSourceDir\*" -Destination $sourcePath -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        return (& $fail "Failed to copy source content: $($_.Exception.Message)")
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$LatestVersionResult.URI)) {
        try {
            Write-UILog -SyncHash $SyncHash -Message "Install: downloading latest installer to '$sourcePath'." -Level Info
            [void]@($LatestVersionResult.ResolvedArtifact | Save-EvergreenApp -LiteralPath $sourcePath -ErrorAction Stop)
        }
        catch {
            return (& $fail "Failed to download installer: $($_.Exception.Message)")
        }
    }

    Write-UILog -SyncHash $SyncHash -Message "Install: executing command '$installCommand'." -Level Cmd

    $process = $null
    try {
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $installCommand -WorkingDirectory $sourcePath -Wait -PassThru -ErrorAction Stop
    }
    catch {
        return (& $fail "Failed to execute install command: $($_.Exception.Message)")
    }

    $exitCode = if ($null -eq $process) { -1 } else { [int]$process.ExitCode }
    $succeeded = $exitCode -eq 0 -or $exitCode -eq 3010

    if (-not $succeeded) {
        return (& $fail "Install command returned exit code $exitCode.")
    }

    return [PSCustomObject]@{
        Succeeded         = $true
        ExitCode          = $exitCode
        WorkingDirectory  = $sourcePath
        DownloadedVersion = [string]$LatestVersionResult.Version
        InstallCommand    = $installCommand
        Error             = ''
    }
}
