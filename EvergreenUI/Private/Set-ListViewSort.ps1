#Requires -Version 5.1

function Set-ListViewSort {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Property,

        [string]$Direction = 'Ascending'
    )

    if ($null -eq $ListView -or $null -eq $ListView.ItemsSource -or
        [string]::IsNullOrWhiteSpace($Property)) {
        return $false
    }

    $firstItem = $null
    foreach ($item in $ListView.ItemsSource) {
        if ($null -ne $item) {
            $firstItem = $item
            break
        }
    }

    if ($null -eq $firstItem -or $null -eq $firstItem.PSObject.Properties[$Property]) {
        return $false
    }

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($ListView.ItemsSource)
    if ($null -eq $view) {
        return $false
    }

    $sortDirection = if ($Direction -ieq 'Descending') {
        [System.ComponentModel.ListSortDirection]::Descending
    }
    else {
        [System.ComponentModel.ListSortDirection]::Ascending
    }

    if (-not $PSCmdlet.ShouldProcess($Property, 'Apply ListView sort')) {
        return $false
    }

    $view.SortDescriptions.Clear()
    $view.SortDescriptions.Add(
        [System.ComponentModel.SortDescription]::new($Property, $sortDirection)
    )
    $view.Refresh()
    return $true
}