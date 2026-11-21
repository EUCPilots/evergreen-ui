Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Save-EwArtifact {
    <#
    .SYNOPSIS
        Downloads a resolved Evergreen artifact.
    .DESCRIPTION
        Saves an artifact under OutputPath\AppName, or under a specified root
        path. The artifact should come from Get-EwApp -Name. Returns one result
        per downloaded file.
    .PARAMETER AppName
        Evergreen application name used for the destination subfolder.
    .PARAMETER Artifact
        A resolved artifact object with a URI and version.
    .PARAMETER Path
        Destination root. Defaults to the configured output path.
    .PARAMETER Force
        Downloads even when the destination file already exists.
    .PARAMETER VerifyChecksum
        Verifies available checksums after download.
    .EXAMPLE
        Get-EwApp -Name MicrosoftEdge | Select-Object -First 1 | Save-EwArtifact -AppName MicrosoftEdge
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm through ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject]$Artifact,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$VerifyChecksum
    )

    process {
        if ([System.IO.Path]::GetFileName($AppName) -cne $AppName -or $AppName -in @('.', '..')) {
            throw "AppName '$AppName' is not a valid folder name."
        }
        if ($null -eq $Artifact.PSObject.Properties['URI'] -or [string]::IsNullOrWhiteSpace([string]$Artifact.URI)) {
            throw 'Artifact must have a non-empty URI property.'
        }
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = [string](Get-EwSetting).OutputPath
        }
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Output path is not configured. Set it with Set-EwSetting -Name OutputPath.'
        }

        $targetPath = Join-Path -Path $Path -ChildPath $AppName
        if ($PSCmdlet.ShouldProcess($targetPath, "Download $AppName artifact")) {
            Write-Verbose -Message "EvergreenUI: Saving $AppName artifact to $targetPath"
            $saved = @(Invoke-EwArtifactSave -Artifact $Artifact -Path $targetPath -Force:$Force -VerifyChecksum:$VerifyChecksum)
            if ($saved.Count -eq 0) {
                throw "Evergreen returned no saved-file result for '$AppName'."
            }
            foreach ($file in $saved) {
                [PSCustomObject]@{
                    AppName = $AppName
                    Version = if ($null -ne $Artifact.PSObject.Properties['Version']) { [string]$Artifact.Version } else { '' }
                    Path = if ($null -ne $file.PSObject.Properties['FullName']) { [string]$file.FullName } else { $targetPath }
                    Artifact = $Artifact
                    SavedFile = $file
                }
            }
            Write-Verbose -Message "EvergreenUI: Saved $($saved.Count) file(s) for $AppName"
        }
    }
}
