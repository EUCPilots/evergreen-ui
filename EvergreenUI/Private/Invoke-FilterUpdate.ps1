#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the current filter state to the cached app results and refreshes
    the versions ListView on the UI thread.

.DESCRIPTION
    Reads $syncHash.FilterState (a hashtable of property name → HashSet of
    selected values) and filters $syncHash.CurrentAppResults through a chained
    Where-Object. The resulting subset is assigned to the ListView's ItemsSource
    via Dispatcher.Invoke.

    A property with zero selected values is treated as "no filter applied" for
    that property (shows all rows) to prevent users accidentally filtering to an
    empty list.

    The results counter TextBlock ("N of M shown") is updated at the same time.

.PARAMETER SyncHash
    Shared synchronised hashtable. Must contain:
        FilterState        : hashtable - property name → HashSet[string] of selected values
        CurrentAppResults  : PSObject[] - the full unfiltered result from Get-EvergreenApp
        VersionsListView   : System.Windows.Controls.ListView - the target list control
        ResultsCountLabel  : System.Windows.Controls.TextBlock - "N of M shown" label
        Window             : the WPF Window (for Dispatcher access)

.EXAMPLE
    Invoke-FilterUpdate -SyncHash $syncHash
#>
function Invoke-FilterUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    if ($null -eq $SyncHash.CurrentAppResults) { return }

    $filtered = $SyncHash.CurrentAppResults

    $activeFilters = [System.Collections.Generic.List[string]]::new()
    foreach ($prop in $SyncHash.FilterState.Keys) {
        $allowedValues = $SyncHash.FilterState[$prop]

        # Empty set → treat as "all allowed" (no filter for this property)
        if ($allowedValues.Count -eq 0) { continue }

        $activeFilters.Add("$prop=[$($allowedValues -join ', ')]")
        $filtered = $filtered | Where-Object {
            $value = if ($prop -eq '_DerivedType') {
                [System.IO.Path]::GetExtension([string]$_.URI).TrimStart('.').ToLower()
            }
            else {
                [string]$_.$prop
            }

            $allowedValues.Contains($value)
        }
    }

    $filteredArray = @($filtered)
    $totalCount = $SyncHash.CurrentAppResults.Count
    $shownCount = $filteredArray.Count

    if ($activeFilters.Count -gt 0) {
        Write-UILog -Message "Filter applied: $($activeFilters -join '; ') — showing $shownCount of $totalCount result(s)." -Level Info -SyncHash $SyncHash
    }

    $SyncHash.Window.Dispatcher.Invoke([action] {
            $SyncHash.VersionsListView.ItemsSource = $filteredArray
            if ($null -ne $SyncHash.ResultsCountLabel) {
                $SyncHash.ResultsCountLabel.Text = "Showing $shownCount of $totalCount"
            }
        }, 'Normal')
}
