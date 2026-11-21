Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwSetting {
    <#
    .SYNOPSIS
        Changes an Evergreen Workbench setting.
    .DESCRIPTION
        Writes a supported setting to the v2 settings file.
    .PARAMETER Name
        The setting to change.
    .PARAMETER Value
        The new value.
    .EXAMPLE
        Set-EwSetting -Name Theme -Value Dark
    .OUTPUTS
        None.
    .NOTES
        Supports WhatIf and does not read v1 settings.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Theme', 'OutputPath', 'LibraryPath')]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Name -eq 'Theme' -and $Value -notin @('System', 'Light', 'Dark')) {
        throw "Theme must be System, Light, or Dark."
    }
    $settings = Get-EwSetting
    if ($PSCmdlet.ShouldProcess((Get-EwSettingsPath), "Set $Name")) {
        $settings[$Name] = $Value
        Write-EwSetting -Settings $settings
    }
}
