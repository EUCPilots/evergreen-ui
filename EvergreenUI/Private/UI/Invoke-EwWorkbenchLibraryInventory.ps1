Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchLibraryInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$State,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Item,
        [Parameter(Mandatory)][string]$Path,
        [string]$SelectedName = ''
    )

    $State.LoadedLibraryPath = $Path
    $State.LibraryListView.ItemsSource = $Item
    $State.LibraryListView.SelectedItem = $null
    $State.LibraryDetailsText.Text = 'Select an application to view its library versions'
    $State.LibraryVersionsListView.ItemsSource = @()
    if ($SelectedName) {
        $State.LibraryListView.SelectedItem = $Item |
            Where-Object { $_.Name -ceq $SelectedName -and $_.VersionCount -gt 0 } | Select-Object -First 1
    }
    Invoke-EwWorkbenchLibraryActionState -State $State
}
