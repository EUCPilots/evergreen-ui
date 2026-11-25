Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwDependency {
    <#
    .SYNOPSIS
        Reports Evergreen Workbench module dependencies.
    .DESCRIPTION
        Returns the required Evergreen module and the optional provider modules
        with the highest installed version of each. Optional modules are only
        needed for the workflows listed in Purpose.
    .EXAMPLE
        Get-EwDependency
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Does not import or install any module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $dependencies = @(
        @{ Name = 'Evergreen'; Required = $true; MinimumVersion = '2603.2832.0'; Purpose = 'Application catalog, downloads, and library' }
        @{ Name = 'IntuneWin32App'; Required = $false; MinimumVersion = ''; Purpose = 'Intune package builds' }
        @{ Name = 'Microsoft.Graph.Authentication'; Required = $false; MinimumVersion = ''; Purpose = 'Intune sign-in and publishing' }
        @{ Name = 'Az.Accounts'; Required = $false; MinimumVersion = ''; Purpose = 'Azure and Nerdio sign-in' }
        @{ Name = 'Az.Resources'; Required = $false; MinimumVersion = ''; Purpose = 'Azure resource group discovery' }
        @{ Name = 'Az.Storage'; Required = $false; MinimumVersion = ''; Purpose = 'Nerdio package storage' }
    )

    foreach ($dependency in $dependencies) {
        $installed = Get-Module -ListAvailable -Name $dependency.Name -ErrorAction Stop |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        $version = if ($installed) { [string]$installed.Version } else { '' }
        $status = if (-not $installed) {
            'Not installed'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($dependency.MinimumVersion) -and
            [version]$installed.Version -lt [version]$dependency.MinimumVersion) {
            'Update required'
        }
        else {
            'Installed'
        }
        Write-Verbose -Message "EvergreenUI: Dependency $($dependency.Name) status '$status' version '$version'"
        [PSCustomObject]@{
            Name = $dependency.Name
            Required = $dependency.Required
            InstalledVersion = $version
            MinimumVersion = $dependency.MinimumVersion
            Status = $status
            Purpose = $dependency.Purpose
        }
    }
}
