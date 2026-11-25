Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwLibrary {
    <#
    .SYNOPSIS
        Updates the configured Evergreen library.
    .DESCRIPTION
        Invokes Evergreen's library updater for an initialized local library
        and returns a structured completion record.
    .PARAMETER Path
        Path to the Evergreen library. Defaults to the configured library path.
    .EXAMPLE
        Update-EwLibrary -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm through ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = [string](Get-EwSetting).LibraryPath
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Library path is not configured. Set it with Set-EwSetting -Name LibraryPath.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Evergreen library path does not exist: $Path"
    }
    if (-not (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath 'EvergreenLibrary.json') -PathType Leaf)) {
        throw "Evergreen library manifest was not found in '$Path'."
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Update Evergreen library')) {
        Write-Verbose -Message "EvergreenUI: Updating Evergreen library at $Path"
        $startedAt = [DateTimeOffset]::Now
        $output = @(Invoke-EwLibraryUpdate -Path $Path)
        [PSCustomObject]@{
            Path = $Path
            Succeeded = $true
            StartedAt = $startedAt
            CompletedAt = [DateTimeOffset]::Now
            Output = $output
        }
    }
}
