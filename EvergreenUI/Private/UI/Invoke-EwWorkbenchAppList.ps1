Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchAppList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$PreserveCurrentApp
    )

    $searchText = [string]$State.AppSearchBox.Text
    $items = @(if ([string]::IsNullOrWhiteSpace($searchText)) {
        @($State.AppCatalog)
    }
    else {
        @($State.AppCatalog | Where-Object {
                ([string]$_.Name).IndexOf($searchText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ([string]$_.FriendlyName).IndexOf($searchText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            })
    })
    $selectedName = if ($null -ne $State.CurrentApp) { [string]$State.CurrentApp.Name } else { '' }
    $selectedApp = $null
    if (-not [string]::IsNullOrWhiteSpace($selectedName)) {
        $selectedApp = $items | Where-Object Name -eq $selectedName | Select-Object -First 1
        if ($null -eq $selectedApp -and $PreserveCurrentApp) {
            $selectedApp = $State.AppCatalog | Where-Object Name -eq $selectedName | Select-Object -First 1
        }
    }
    $State.SuppressAppSelection = $true
    try {
        $State.AppsListView.ItemsSource = [object[]]$items
        $State.AppsListView.SelectedItem = $selectedApp
        if ($null -ne $selectedApp) {
            $State.CurrentApp = $selectedApp
            $State.FavoriteAppButton.Content = if ($selectedApp.IsFavourite) { 'Remove favourite' } else { 'Add favourite' }
            $State.FavoriteAppButton.IsEnabled = $null -eq $State.ActiveJobId
        }
        elseif (-not [string]::IsNullOrWhiteSpace($selectedName)) {
            $State.CurrentApp = $null
            $State.CurrentAppName = ''
            $State.FavoriteAppButton.IsEnabled = $false
            $State.AllArtifacts = @()
            $State.ArtifactFilterControls = @{}
            $State.ArtifactFiltersPanel.Children.Clear()
            $State.ArtifactsGrid.ItemsSource = @()
            $State.ArtifactCountLabel.Text = '0 artifacts'
            $State.SelectedAppText.Text = 'Select an application to view available versions'
        }
    }
    finally {
        $State.SuppressAppSelection = $false
    }
    $State.AppCountLabel.Text = "$($items.Count) applications"
    if ($State.AppsDisplayStale) { $State.AppCountLabel.Text = "STALE: $($State.AppCountLabel.Text)" }
}
