#Requires -Version 5.1
<#
.SYNOPSIS
    Inspects Get-EvergreenApp output and returns metadata for each property
    that can be used as a filter control in the UI.

.DESCRIPTION
    Given an array of PSObjects returned by Get-EvergreenApp, this function:
      1. Enumerates the property names from the first object
      2. Excludes properties that are display-only (Version, URI, Date, etc.)
      3. For each remaining property, collects unique values and determines the
         appropriate WPF control type based on cardinality:
           2–6 unique values  → CheckBoxStrip  (horizontal checkbox row)
           7–20 unique values → MultiListBox   (scrollable multi-select listbox)
           21+ unique values  → TextBox        (free-text contains-match)

    Also performs URI-based Type derivation: if the result set has no Type
    property but all rows have a URI, a synthetic 'Type (derived)' property is
    created by extracting the file extension from each URI.

.PARAMETER AppResults
    The PSObject array returned by Get-EvergreenApp. Must contain at least one
    object. Version and URI are always required on each object.

.OUTPUTS
    PSCustomObject[] - one object per filterable property with:
        Name         : string  - property name as returned by Evergreen
        DisplayName  : string  - friendly label for the UI
        UniqueValues : string[] - sorted distinct values
        Count        : int    - number of unique values
        ControlType  : string - 'CheckBoxStrip' | 'MultiListBox' | 'TextBox'
        IsSynthetic  : bool   - true if derived from URI rather than a real property

.EXAMPLE
    $results = Get-EvergreenApp -Name 'MicrosoftEdge'
    $props   = Get-FilterableProperties -AppResults $results
    # Returns objects for Architecture, Channel, Release, Type
#>
function Get-FilterableProperties {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSObject[]]$AppResults
    )

    $appResultsArray = @($AppResults)

    if ($appResultsArray.Count -eq 0) {
        return @()
    }

    # Guard against double-wrapped data: if element 0 is itself an array (e.g. Object[]{ Object[]{...} }),
    # flatten one level so the actual PSCustomObjects are used instead of the Array's own properties.
    if ($appResultsArray[0] -is [System.Array]) {
        $appResultsArray = @($appResultsArray[0])
        if ($appResultsArray.Count -eq 0) { return @() }
    }

    # Properties that are never filterable - display in the grid only
    [string[]]$displayOnly = @(
        'Version', 'URI', 'Date', 'Expiry',
        'Sha', 'Sha1', 'Sha256', 'Hash',
        'Checksum', 'Size', 'JavaVersion'
    )

    # Friendly display names for well-known properties
    $friendlyNames = @{
        Architecture = 'Architecture'
        Type         = 'File type'
        Channel      = 'Channel'
        Ring         = 'Ring / Channel'
        Release      = 'Release'
        Language     = 'Language'
        Platform     = 'Platform'
        Track        = 'Track'
        Product      = 'Product variant'
    }

    $filterableProps = $appResultsArray[0].PSObject.Properties.Name |
    Where-Object { $_ -notin $displayOnly -and $_ -notlike '*Date*' }

    $output = foreach ($propName in $filterableProps) {
        $allValues = @(
            $appResultsArray.$propName |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
        )

        $controlType = if ($allValues.Count -le 6) { 'CheckBoxStrip' }
        elseif ($allValues.Count -le 20) { 'MultiListBox' }
        else { 'TextBox' }

        [PSCustomObject]@{
            Name         = $propName
            DisplayName  = if ($friendlyNames.ContainsKey($propName)) { $friendlyNames[$propName] } else { $propName }
            UniqueValues = [string[]]$allValues
            Count        = $allValues.Count
            ControlType  = $controlType
            IsSynthetic  = $false
        }
    }

    # URI-based Type derivation - add synthetic 'File type' if Type is absent
    $hasTypeProperty = ($appResultsArray[0].PSObject.Properties.Name) -contains 'Type'
    $hasUriProperty = ($appResultsArray[0].PSObject.Properties.Name) -contains 'URI'

    if (-not $hasTypeProperty -and $hasUriProperty) {
        $derivedTypes = @(
            $appResultsArray.URI |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [System.IO.Path]::GetExtension($_).TrimStart('.').ToLower() } |
            Where-Object { $_ -ne '' } |
            Sort-Object -Unique
        )

        if ($derivedTypes.Count -gt 0) {
            $output = @($output) + [PSCustomObject]@{
                Name         = '_DerivedType'
                DisplayName  = 'File type (derived)'
                UniqueValues = [string[]]$derivedTypes
                Count        = $derivedTypes.Count
                ControlType  = if ($derivedTypes.Count -le 6) { 'CheckBoxStrip' } else { 'MultiListBox' }
                IsSynthetic  = $true
            }
        }
    }

    return @($output)
}
