Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-EwFavouriteApp {
    <#
    .SYNOPSIS
        Marks Evergreen applications as favourites.
    .DESCRIPTION
        Adds application names to the FavouriteApps setting. Favourites are
        listed first by Get-EwApp. Existing favourites are not duplicated.
    .PARAMETER Name
        Evergreen application names to add.
    .EXAMPLE
        Add-EwFavouriteApp -Name MicrosoftEdge
    .OUTPUTS
        System.String
    .NOTES
        Returns the updated favourite list. Supports WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name
    )

    begin {
        $requested = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($item in $Name) {
            $requested.Add($item.Trim())
        }
    }
    end {
        $settings = Get-EwSetting
        $favourites = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in @($settings.FavouriteApps)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$existing)) {
                $favourites.Add([string]$existing)
            }
        }
        $added = @($requested | Where-Object { $candidate = $_; -not ($favourites | Where-Object { $_ -ieq $candidate }) } |
            Select-Object -Unique)
        if ($added.Count -gt 0 -and $PSCmdlet.ShouldProcess(($added -join ', '), 'Add favourite applications')) {
            foreach ($item in $added) {
                $favourites.Add($item)
            }
            $settings.FavouriteApps = @($favourites)
            Write-EwSetting -Settings $settings
            Write-Verbose -Message "EvergreenUI: Added $($added.Count) favourite application(s)"
        }
        foreach ($favourite in $favourites) { $favourite }
    }
}
