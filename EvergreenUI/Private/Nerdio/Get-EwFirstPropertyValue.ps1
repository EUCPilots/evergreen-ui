Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwFirstPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    foreach ($propertyName in $Name) {
        $property = $InputObject.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $null -eq $property.Value) {
            continue
        }
        if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)) {
            continue
        }
        return $property.Value
    }
    return $null
}
