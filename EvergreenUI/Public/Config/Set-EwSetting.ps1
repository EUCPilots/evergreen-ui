Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwSetting {
    <#
    .SYNOPSIS
        Changes an Evergreen Workbench setting.
    .DESCRIPTION
        Writes a supported setting to the v2 settings file. Secrets are never
        stored. Use Add-EwFavouriteApp and Remove-EwFavouriteApp to change
        FavouriteApps.
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
        [ValidateSet(
            'Theme', 'OutputPath', 'LibraryPath', 'PackageOutputPath',
            'IntuneDefinitionsPath', 'IntuneTenantId',
            'NerdioDefinitionsPath', 'NerdioTenantId', 'NmeHost', 'NmeClientId', 'NmeApiScope',
            'NmeOAuthTokenUrl', 'NmeSubscriptionId', 'NmeResourceGroup', 'NmeStorageAccount', 'NmeContainer',
            'M365DefinitionsPath', 'M365Channel', 'M365CompanyName', 'M365ImportFor'
        )]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Name -eq 'Theme' -and $Value -notin @('System', 'Light', 'Dark')) {
        throw "Theme must be System, Light, or Dark."
    }
    if ($Name -eq 'M365ImportFor' -and $Value -notin @('Single session', 'Multi-session')) {
        throw "M365ImportFor must be 'Single session' or 'Multi-session'."
    }
    $settings = Get-EwSetting
    if ($PSCmdlet.ShouldProcess((Get-EwSettingsPath), "Set $Name")) {
        $settings[$Name] = $Value
        Write-EwSetting -Settings $settings
    }
}
