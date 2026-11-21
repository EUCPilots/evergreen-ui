Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-EwFavouriteApp {
    <#
    .SYNOPSIS
        Removes Evergreen applications from favourites.
    .DESCRIPTION
        Removes application names from the FavouriteApps setting using a
        case-insensitive match.
    .PARAMETER Name
        Evergreen application names to remove.
    .EXAMPLE
        Remove-EwFavouriteApp -Name MicrosoftEdge
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
        $current = @($settings.FavouriteApps | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $remaining = @($current | Where-Object { $candidate = [string]$_; -not ($requested | Where-Object { $_ -ieq $candidate }) })
        if ($remaining.Count -ne $current.Count -and
            $PSCmdlet.ShouldProcess(($requested -join ', '), 'Remove favourite applications')) {
            $settings.FavouriteApps = @($remaining)
            Write-EwSetting -Settings $settings
            Write-Verbose -Message "EvergreenUI: Removed $($current.Count - $remaining.Count) favourite application(s)"
            foreach ($favourite in $remaining) { $favourite }
            return
        }
        foreach ($favourite in $current) { $favourite }
    }
}
