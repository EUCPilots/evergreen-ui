Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwApp {
    <#
    .SYNOPSIS
        Lists Evergreen applications or resolves an application's artifacts.
    .DESCRIPTION
        Without Name, returns the cached application catalog. With Name,
        resolves its artifacts using Evergreen. Filter values are exact
        case-insensitive matches; each filter value may be one value or a set
        of alternatives. Use Force to refresh the catalog cache.
    .PARAMETER Name
        The Evergreen application name to resolve. Omit to list applications.
    .PARAMETER Filter
        Property-value constraints to apply to resolved artifacts.
    .PARAMETER Force
        Bypasses the application catalog cache.
    .EXAMPLE
        Get-EwApp
    .EXAMPLE
        Get-EwApp -Name MicrosoftEdge -Filter @{ Architecture = 'x64'; Type = 'msi' }
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Evergreen performs vendor lookups when resolving named applications.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [object[]])]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [System.Collections.IDictionary]$Filter,

        [Parameter()]
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $cache = $script:ewAppCatalogCache
        if (-not $Force -and $null -ne $cache.RetrievedAt) {
            $age = [DateTimeOffset]::Now - $cache.RetrievedAt
            Write-Verbose -Message ('EvergreenUI: Application catalog cache hit; age {0:n0} seconds' -f $age.TotalSeconds)
            return $cache.Items
        }

        Write-Verbose -Message 'EvergreenUI: Application catalog cache miss; querying Evergreen'
        $items = @(
            Invoke-EwAppCatalogQuery |
                Sort-Object -Property Name |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name = [string]$_.Name
                        FriendlyName = if ($_.PSObject.Properties.Name -contains 'Application' -and -not [string]::IsNullOrWhiteSpace([string]$_.Application)) {
                            [string]$_.Application
                        }
                        else {
                            [string]$_.Name
                        }
                        Link = if ($_.PSObject.Properties.Name -contains 'Link') { [string]$_.Link } else { '' }
                    }
                }
        )
        $script:ewAppCatalogCache.Items = $items
        $script:ewAppCatalogCache.RetrievedAt = [DateTimeOffset]::Now
        Write-Verbose -Message "EvergreenUI: Application catalog loaded; $($items.Count) applications"
        return $items
    }

    Write-Verbose -Message "EvergreenUI: Resolving artifacts for '$Name'"
    $artifacts = @(Get-EwAppVersion -Name $Name)
    if ($Filter -and $Filter.Count -gt 0) {
        $validProperties = if ($artifacts.Count -gt 0) { @($artifacts[0].PSObject.Properties.Name) } else { @() }
        foreach ($key in $Filter.Keys) {
            if ($key -ne '_DerivedType' -and $key -notin $validProperties) {
                throw "Filter property '$key' is not available for application '$Name'."
            }
        }
        $artifacts = @($artifacts | Where-Object { Test-EwArtifactFilter -Artifact $_ -Filter $Filter })
    }
    Write-Verbose -Message "EvergreenUI: Resolved $($artifacts.Count) matching artifacts for '$Name'"
    return $artifacts
}
