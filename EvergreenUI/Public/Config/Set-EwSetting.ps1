Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwSetting {
    <#
    .SYNOPSIS
        Changes an Evergreen Workbench setting.
    .DESCRIPTION
        Writes a supported setting to the v2 settings file. Secrets are never
        stored. Use Add-EwFavouriteApp and Remove-EwFavouriteApp to change
        FavouriteApps. StartupView, LastAppName, WindowWidth, WindowHeight and
        WindowMaximized hold UI state that Start-EvergreenWorkbench saves and
        restores; StartupView must name a Workbench view, window sizes must be
        positive whole numbers and WindowMaximized must be True or False.
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
            'M365DefinitionsPath', 'M365Channel', 'M365CompanyName', 'M365ImportFor',
            'StartupView', 'LastAppName', 'WindowWidth', 'WindowHeight', 'WindowMaximized'
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
    $views = @('Apps', 'Download', 'Library', 'Packages', 'Intune', 'Nerdio', 'Install', 'Settings', 'About')
    [object]$storedValue = $Value
    switch ($Name) {
        'StartupView' {
            $match = $views | Where-Object { $_ -eq $Value } | Select-Object -First 1
            if ($null -eq $match) {
                throw "StartupView must be one of: $($views -join ', ')."
            }
            $storedValue = [string]$match
        }
        { $_ -in @('WindowWidth', 'WindowHeight') } {
            $size = 0
            if (-not [int]::TryParse($Value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$size) -or $size -le 0) {
                throw "$Name must be a positive whole number."
            }
            $storedValue = $size
        }
        'WindowMaximized' {
            $flag = $false
            if (-not [bool]::TryParse($Value, [ref]$flag)) {
                throw 'WindowMaximized must be True or False.'
            }
            $storedValue = $flag
        }
    }
    $settings = Get-EwSetting
    if ($PSCmdlet.ShouldProcess((Get-EwSettingsPath), "Set $Name")) {
        $settings[$Name] = $storedValue
        Write-EwSetting -Settings $settings
    }
}
