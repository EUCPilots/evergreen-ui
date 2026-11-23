Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwEvergreen {
    <#
    .SYNOPSIS
        Updates the Evergreen application manifests and cache.
    .DESCRIPTION
        Runs Update-Evergreen to refresh the local Evergreen apps cache, then
        clears the Workbench application catalog and application version
        caches. Information and verbose
        output from Evergreen flow through normally.
    .EXAMPLE
        Update-EwEvergreen
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Run within Start-EwJob for background use.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param()

    if (-not $PSCmdlet.ShouldProcess('Evergreen', 'Update application manifests')) {
        return
    }
    Write-Verbose -Message 'EvergreenUI: Evergreen update started'
    try {
        Invoke-EwEvergreenUpdate
        $script:ewAppCatalogCache.Items = @()
        $script:ewAppCatalogCache.RetrievedAt = $null
        try {
            $appClear = Invoke-EwAppVersionCache -Action Clear -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Application version cache cleared after Evergreen update; removed $($appClear.RemovedCount) files"
        }
        catch {
            # Best effort: the update itself succeeded and cached versions expire after 24 hours.
            Write-Verbose -Message "EvergreenUI: Application version cache could not be cleared after Evergreen update: $($_.Exception.Message)"
        }
        Write-Verbose -Message 'EvergreenUI: Evergreen update completed; application catalog cache cleared'
        return [PSCustomObject]@{ Succeeded = $true; Error = '' }
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Evergreen update failed: $($_.Exception.Message)"
        return [PSCustomObject]@{ Succeeded = $false; Error = $_.Exception.Message }
    }
}
