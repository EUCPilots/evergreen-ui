Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwLibrary {
    <#
    .SYNOPSIS
        Gets applications and versions in an Evergreen library.
    .DESCRIPTION
        Reads a local library inventory and returns one record per application,
        including the application folder, version count, and source inventory
        entry. Defaults to the configured LibraryPath.
    .PARAMETER Path
        Path to the Evergreen library. Defaults to the configured library path.
    .EXAMPLE
        Get-EwLibrary
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        The library must be initialized and maintained by Evergreen.
    #>
    [CmdletBinding()]
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

    Write-Verbose -Message "EvergreenUI: Reading library inventory from $Path"
    $library = Get-EwLibraryInventory -Path $Path
    $inventory = if ($null -ne $library.PSObject.Properties['Inventory']) {
        @($library.Inventory)
    }
    else {
        @($library)
    }
    foreach ($entry in $inventory) {
        $appName = if ($null -ne $entry.PSObject.Properties['ApplicationName']) {
            [string]$entry.ApplicationName
        }
        elseif ($null -ne $entry.PSObject.Properties['Name']) {
            [string]$entry.Name
        }
        else {
            throw 'Evergreen library inventory entry has no ApplicationName or Name property.'
        }
        $versionCount = if ($null -ne $entry.PSObject.Properties['Versions']) { @($entry.Versions).Count } else { 0 }
        [PSCustomObject]@{
            Name = $appName
            VersionCount = $versionCount
            Path = Join-Path -Path $Path -ChildPath $appName
            SourceItem = $entry
        }
    }
}
