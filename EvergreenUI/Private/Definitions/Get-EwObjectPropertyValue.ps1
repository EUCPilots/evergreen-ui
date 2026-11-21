Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [object]$Default = $null
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}
