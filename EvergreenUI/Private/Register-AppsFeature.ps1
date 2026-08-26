function Register-AppsFeature {
    <#
    .SYNOPSIS
    Registers event handlers and initializes state for the Apps browsing feature.

    .DESCRIPTION
    Sets up event handlers for the Apps navigation view, including app search, filtering,
    version loading, and library operations. This includes all scriptblocks related to app
    catalog browsing, filtering by properties, and version retrieval via Get-EvergreenApp.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Apps feature.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls for readability
    $refreshAppsButton = $Controls.RefreshAppsButton
    $appSearchBox = $Controls.AppSearchBox
    $appsListBox = $Controls.AppsListBox
    $loadAppVersionsButton = $Controls.LoadAppVersionsButton
    $filterWrapPanel = $Controls.FilterWrapPanel
    $clearFiltersButton = $Controls.ClearFiltersButton
    $exportCsvButton = $Controls.ExportCsvButton
    $addToLibraryButton = $Controls.AddToLibraryButton
    $appsActionStatusLabel = $Controls.AppsActionStatusLabel
    $addToQueueButton = $Controls.AddToQueueButton
    $appCountLabel = $Controls.AppCountLabel
    $appDetailEmpty = $Controls.AppDetailEmpty
    $appDetailLoading = $Controls.AppDetailLoading
    $appDetailLoadingLabel = $Controls.AppDetailLoadingLabel
    $appDetailContent = $Controls.AppDetailContent
    $appDetailTitle = $Controls.AppDetailTitle

    # Helper scriptblock: Update app combo box source with search filtering
    $updateAppsComboSource = {
        param([string]$SearchText = '')

        $allApps = @($SyncHash.AppList)
        if ($allApps.Count -eq 0) {
            $appsListBox.ItemsSource = @()
            $appCountLabel.Text = ''
            return
        }

        # Stamp IsFavourite on each item based on current config
        $favouriteSet = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($SyncHash.Config.FavouriteApps),
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($app in $allApps) {
            $app.IsFavourite = $favouriteSet.Contains($app.Name)
        }

        $source = if ([string]::IsNullOrWhiteSpace($SearchText)) {
            $allApps
        }
        else {
            $needle = $SearchText.Trim()
            @($allApps | Where-Object { $_.Name -like "*$needle*" -or $_.FriendlyName -like "*$needle*" })
        }

        # Favourites first (descending), then alphabetical by FriendlyName
        $sorted = @($source | Sort-Object -Property @(
                @{ Expression = 'IsFavourite'; Descending = $true },
                @{ Expression = 'FriendlyName' }
            ))

        $appsListBox.ItemsSource = $sorted
        $appCountLabel.Text = " $($sorted.Count) of $($allApps.Count)"
    }
    $SyncHash.UpdateAppsComboSource = $updateAppsComboSource

    # Helper scriptblock: Load app catalog from Evergreen module
    $loadAppCatalog = {
        param([switch]$Force)

        $refreshAppsButton.IsEnabled = $false
        try {
            [void](Get-EvergreenAppList -SyncHash $SyncHash -Force:$Force)
            & $updateAppsComboSource -SearchText $appSearchBox.Text
        }
        finally {
            $refreshAppsButton.IsEnabled = $true
        }
    }
    $SyncHash.LoadAppCatalog = $loadAppCatalog

    # TODO: Extract remaining Apps feature helpers from Start-EvergreenWorkbench (lines 2454-2677):
    # - $rebuildVersionColumns
    # - $getAppCacheFile
    # - $displayAppResults
    # - $updateAddToLibraryButtonState
    # - $loadAppVersions

    # TODO: Register event handlers for Apps feature:
    # - RefreshAppsButton.add_Click
    # - AppSearchBox.add_TextChanged
    # - AppsListBox.add_SelectionChanged
    # - LoadAppVersionsButton.add_Click
    # - ClearFiltersButton.add_Click
    # - ExportCsvButton.add_Click
    # - AddToLibraryButton.add_Click
    # - AddToQueueButton.add_Click

    Write-Verbose 'EvergreenUI: Apps feature registered.'
}
