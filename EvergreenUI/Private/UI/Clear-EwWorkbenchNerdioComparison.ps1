Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwWorkbenchNerdioComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [bool]$AzureChanged = $false,
        [bool]$ConnectionChanged = $true
    )

    $State.NerdioPlan = $null
    if ($ConnectionChanged) {
        $State.NerdioDestination = $null
        $script:ewNerdioSession.Context = $null
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
    if ($ConnectionChanged) {
        $State.NerdioConnectionStatusLabel.Text = if ($null -ne $State.NerdioAzureIdentity) {
            'Azure connected; connect Nerdio API after reviewing setup.'
        } else { 'Azure and Nerdio not connected' }
    }
    Invoke-EwWorkbenchNerdioBusyState -State $State
}
