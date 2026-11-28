Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}
