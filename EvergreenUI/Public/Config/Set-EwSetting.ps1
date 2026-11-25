Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwSetting {
    <#
    .SYNOPSIS
        Changes an Evergreen Workbench setting.
    .DESCRIPTION
        Writes a supported setting to the Workbench settings file. Secrets are never
        stored. Use Add-EwFavouriteApp and Remove-EwFavouriteApp to change
        FavouriteApps. StartupView, LastAppName, WindowWidth, WindowHeight,
        DownloadTrayHeight, AppsListWidth and WindowMaximized hold UI state
        that Start-EvergreenWorkbench saves and restores. StartupView must name
        a Workbench view, window sizes must be positive whole numbers,
        DownloadTrayHeight must be between 120 and 600 and AppsListWidth must
        be at least 160, both in device-independent pixels. WindowMaximized
        must be True or False. ArtifactHiddenColumns is a comma-separated list
        of optional Apps grid property names to hide, including app-specific
        properties. An empty value shows all columns; Version and
        URI cannot be hidden. Saving a non-empty LibraryPath also records it at
        the top of LibraryPathHistory, which keeps the 10 most recent distinct
        library paths.
    .PARAMETER Name
        The setting to change.
    .PARAMETER Value
        The new value.
    .EXAMPLE
        Set-EwSetting -Name Theme -Value Dark
    .OUTPUTS
        None.
    .NOTES
        Supports WhatIf.
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
            'StartupView', 'LastAppName', 'WindowWidth', 'WindowHeight', 'DownloadTrayHeight',
            'AppsListWidth', 'ArtifactHiddenColumns', 'WindowMaximized'
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
    $views = @('Apps', 'Library', 'Packages', 'Intune', 'Nerdio', 'Install', 'Settings', 'About')
    [object]$storedValue = $Value
    switch ($Name) {
        'ArtifactHiddenColumns' {
            $optionalColumns = @('Architecture', 'Channel', 'Release', 'Type', 'Language', 'Date')
            $seenColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $hiddenColumns = @(
                foreach ($columnName in ($Value -split ',')) {
                    $columnName = $columnName.Trim()
                    if ([string]::IsNullOrEmpty($columnName)) {
                        continue
                    }
                    if ($columnName -in @('Version', 'URI')) {
                        throw "ArtifactHiddenColumns cannot hide '$columnName'. Version and URI must remain visible."
                    }
                    $match = $optionalColumns | Where-Object { $_ -eq $columnName } | Select-Object -First 1
                    if ($seenColumns.Add($columnName)) {
                        if ($null -ne $match) { $match } else { $columnName }
                    }
                }
            )
            $storedValue = $hiddenColumns -join ','
        }
        'StartupView' {
            $match = $views | Where-Object { $_ -eq $Value } | Select-Object -First 1
            if ($null -eq $match) {
                throw "StartupView must be one of: $($views -join ', ')."
            }
            $storedValue = [string]$match
        }
        { $_ -in @('WindowWidth', 'WindowHeight', 'DownloadTrayHeight', 'AppsListWidth') } {
            $size = 0
            if (-not [int]::TryParse($Value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$size)) {
                throw "$Name must be a whole number."
            }
            if ($Name -eq 'DownloadTrayHeight' -and ($size -lt 120 -or $size -gt 600)) {
                throw 'DownloadTrayHeight must be between 120 and 600.'
            }
            if ($Name -eq 'AppsListWidth' -and $size -lt 160) {
                throw 'AppsListWidth must be at least 160.'
            }
            if ($Name -in @('WindowWidth', 'WindowHeight') -and $size -le 0) {
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
        if ($Name -eq 'LibraryPath' -and -not [string]::IsNullOrWhiteSpace($Value)) {
            $path = $Value.Trim()
            $previous = @($settings['LibraryPathHistory'] | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_) -and
                    -not [string]::Equals(([string]$_).Trim(), $path, [System.StringComparison]::OrdinalIgnoreCase)
                })
            $settings['LibraryPathHistory'] = @(@($path) + $previous | Select-Object -First 10)
            Write-Verbose -Message "EvergreenUI: Recorded library path history ($(@($settings['LibraryPathHistory']).Count) entries)"
        }
        Write-EwSetting -Settings $settings
    }
}
