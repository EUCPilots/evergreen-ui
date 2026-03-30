#Requires -Version 5.1
<#
.SYNOPSIS
    Merges missing properties from a default config section into a loaded one.

.DESCRIPTION
    If the loaded section is null the default is returned as-is. Otherwise each
    property that exists in Default but is absent (null) in Loaded is added via
    Add-Member, ensuring forward-compatibility when new settings keys are added.

    Used exclusively by Get-UIConfig to populate nested settings objects
    (NerdioSettings, IntuneSettings, M365Settings, etc.) after deserialising
    settings.json.

.PARAMETER Loaded
    The PSCustomObject deserialised from settings.json. May be null.

.PARAMETER Default
    The PSCustomObject containing canonical default values.

.OUTPUTS
    PSCustomObject — the merged section (Loaded with any missing keys added).

.EXAMPLE
    $json.NerdioSettings = Merge-ConfigSection -Loaded $json.NerdioSettings -Default $default.NerdioSettings
#>
function Merge-ConfigSection {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSCustomObject]$Loaded,

        [Parameter(Mandatory)]
        [PSCustomObject]$Default
    )

    if ($null -eq $Loaded) {
        return $Default
    }

    foreach ($prop in $Default.PSObject.Properties.Name) {
        if ($null -eq $Loaded.$prop) {
            $Loaded | Add-Member -NotePropertyName $prop -NotePropertyValue $Default.$prop -Force
        }
    }

    return $Loaded
}
