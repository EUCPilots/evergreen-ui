Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwWorkbenchNerdioComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [bool]$AzureChanged = $false,
        [bool]$ConnectionChanged = $true,
        [bool]$StorageChanged = $false
    )

    $State.NerdioPlan = $null
    $State.NerdioPruneSelectionId = ''
    if ($ConnectionChanged) {
        $State.NerdioDestination = $null
        $script:ewNerdioSession.Context = $null
        $script:ewNerdioSession.ApiOnly = $false
    }
    elseif ($StorageChanged -and $null -ne $State.NerdioDestination -and
        -not [bool](Get-EwFirstPropertyValue -InputObject $State.NerdioDestination -Name 'ApiOnly')) {
        $State.NerdioDestination = Sync-EwNerdioStorageContext -Detach
    }
    $State.NerdioComparisonListView.ItemsSource = @()
    if ($AzureChanged) {
        $State.NerdioAzureIdentity = $null
        $State.AllowNerdioEvents = $false
        $State.NmeResourceGroupCombo.ItemsSource = @()
        $State.NmeStorageAccountCombo.ItemsSource = @()
        $State.NmeContainerCombo.ItemsSource = @()
        $State.AllowNerdioEvents = $true
    }
    if ($ConnectionChanged -or $StorageChanged) {
        $State.NerdioConnectionStatusLabel.Text = if ($null -ne $State.NerdioDestination) {
            "Nerdio API connected: $($State.NerdioDestination.NmeHost). Connect Azure and select storage for Shell Apps."
        } elseif ($null -ne $State.NerdioAzureIdentity) {
            'Azure connected; connect Nerdio API.'
        } else { 'Azure and Nerdio not connected' }
        if ($State.Contains('M365Views')) {
            Clear-EwWorkbenchM365Preview -State $State -Provider 'Nerdio'
        }
    }
    Invoke-EwWorkbenchNerdioBusyState -State $State
}
