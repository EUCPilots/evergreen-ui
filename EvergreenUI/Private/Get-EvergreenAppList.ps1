#Requires -Version 5.1
<#
.SYNOPSIS
    Returns a sorted list of all Evergreen-tracked applications for UI binding.

.DESCRIPTION
    Thin wrapper around Find-EvergreenApp. Returns an array of PSCustomObjects
    with Name and FriendlyName properties, suitable for binding to a ComboBox
    or ListView in the Apps and Download views.

    The result is cached in $syncHash.AppList so subsequent calls within the
    same session do not re-query Evergreen.

.PARAMETER SyncHash
    Shared synchronised hashtable. AppList key is written here.

.PARAMETER Force
    If specified, bypasses the in-session cache and re-queries Find-EvergreenApp.

.OUTPUTS
    PSCustomObject[] - each object has:
        Name         : string - internal Evergreen app name (e.g. 'MicrosoftEdge')
        FriendlyName : string - display name returned by Find-EvergreenApp

.EXAMPLE
    $apps = Get-EvergreenAppList -SyncHash $syncHash
    $ComboBox.ItemsSource = $apps
#>
function Get-EvergreenAppList {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash,

        [Parameter()]
        [switch]$Force
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Return cached list unless Force is specified
    if (-not $Force -and $null -ne $SyncHash.AppList -and $SyncHash.AppList.Count -gt 0) {
        return $SyncHash.AppList
    }

    Write-UILog -SyncHash $SyncHash -Message 'Retrieving application list with Evergreen...' -Level Info
    Write-UILog -SyncHash $SyncHash -Message 'Find-EvergreenApp' -Level Cmd

    try {
        $raw = Find-EvergreenApp -ErrorAction Stop

        $list = $raw |
        Sort-Object -Property Name |
        ForEach-Object {
            [PSCustomObject]@{
                Name         = $_.Name
                FriendlyName = if ($_.PSObject.Properties.Name -contains 'Application') {
                    $_.Application
                }
                else {
                    $_.Name
                }
                IsFavourite  = $false
            }
        }

        $SyncHash.AppList = $list
        Write-UILog -SyncHash $SyncHash -Message "Application list loaded - $($list.Count) apps available." -Level Info
        return $list
    }
    catch {
        Write-UILog -SyncHash $SyncHash -Message "Failed to retrieve application list: $_" -Level Error
        $SyncHash.AppList = @()
        return @()
    }
}
