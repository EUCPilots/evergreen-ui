Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchNerdioAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)]
        [ValidateSet('AzureConnect', 'Disconnect', 'Storage', 'Containers', 'ApiConnect', 'Compare', 'Publish', 'Cancel', 'Save', 'Browse', 'Review')]
        [string]$Action
    )
    try {
        if ($Action -eq 'Cancel') {
            if ($null -ne $State.NerdioCancellation) {
                $State.NerdioCancellation.Cancel()
                Write-EwWorkbenchLog -State $State -Message 'Nerdio cancellation requested; the current item will finish first.' -Level Warning
                Invoke-EwWorkbenchNerdioBusyState -State $State
            }
            return
        }
        if ($null -ne $State.ActiveJobId) { throw 'Wait for the current operation to finish.' }
        switch ($Action) {
            'Save' {
                foreach ($name in $State.NerdioSettingControls.Keys) {
                    $control = $State.NerdioSettingControls[$name]
                    $value = if ($control -is [System.Windows.Controls.ComboBox]) { [string]$control.SelectedItem } else { [string]$control.Text }
                    Set-EwSetting -Name $name -Value $value
                    $State.Settings[$name] = $value
                }
                Write-EwWorkbenchLog -State $State -Message 'Saved Nerdio setup without credentials.'
                return
            }
            'Browse' {
                $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
                if ($dialog.ShowDialog($State.Window)) { $State.NerdioDefinitionsPathBox.Text = $dialog.FolderName }
                return
            }
            'Review' {
                $result = $State.NerdioPublishResultsListView.SelectedItem
                if ($null -eq $result -or $result.Status -notin @('Pending', 'Unknown')) { return }
                $answer = [System.Windows.MessageBox]::Show($State.Window,
                    "Nerdio host: $($result.OutcomeKey.Split('|')[0])`nApp: $($result.Name)`nApp ID: $($result.AppId)`nJob ID: $($result.JobId)`n`n" +
                    'Have you inspected this operation in Nerdio and established its final outcome? This only acknowledges your review; it does not retry or delete anything.',
                    'Acknowledge Nerdio outcome review', [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
                if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                    $State.NerdioBlockedOutcomes.Remove($result.OutcomeKey)
                    $State.NerdioPlan = $null
                    $State.NerdioComparisonListView.ItemsSource = @()
                    Write-EwWorkbenchLog -State $State -Message 'Outcome review acknowledged. Compare again before any further publishing.' -Level Warning
                    Invoke-EwWorkbenchNerdioBusyState -State $State
                }
                return
            }
            'AzureConnect' {
                Clear-EwWorkbenchNerdioComparison -State $State -AzureChanged $true
                $body = {
                    param($Tenant, $Subscription, $Device)
                    $result = Connect-EwAzure -TenantId $Tenant -SubscriptionId $Subscription -UseDeviceAuthentication:([bool]$Device)
                    if (-not $result.Succeeded) { throw $result.Error }
                    & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwAzureIdentity -Identity $Value } $result
                    [PSCustomObject]@{ Identity = $result; Items = @(Get-EwAzureResourceGroup) }
                }
                $arguments = @([string]$State.NerdioTenantIdBox.Text, [string]$State.NmeSubscriptionIdBox.Text, [bool]$State.UseNerdioDeviceCodeToggle.IsChecked)
            }
            'Disconnect' {
                Clear-EwWorkbenchNerdioComparison -State $State -AzureChanged $true
                $body = { Disconnect-EwNerdio }
                $arguments = @()
            }
            'Storage' {
                $body = {
                    param($Identity, $Group)
                    & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwAzureIdentity -Identity $Value } $Identity
                    [PSCustomObject]@{ Items = @(Get-EwAzureStorageAccount -ResourceGroupName $Group) }
                }
                $arguments = @($State.NerdioAzureIdentity, [string]$State.NmeResourceGroupCombo.SelectedItem)
            }
            'Containers' {
                $body = {
                    param($Identity, $Group, $Storage)
                    & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwAzureIdentity -Identity $Value } $Identity
                    [PSCustomObject]@{ Items = @(Get-EwAzureStorageContainer -ResourceGroupName $Group -StorageAccountName $Storage) }
                }
                $arguments = @($State.NerdioAzureIdentity, [string]$State.NmeResourceGroupCombo.SelectedItem, [string]$State.NmeStorageAccountCombo.SelectedItem)
            }
            'ApiConnect' {
                if ($null -eq $State.NerdioAzureIdentity -or -not $State.NmeContainerCombo.SelectedItem) { throw 'Connect Azure and select storage first.' }
                $parameters = @{
                    TenantId = [string]$State.NerdioTenantIdBox.Text; SubscriptionId = [string]$State.NmeSubscriptionIdBox.Text
                    ClientId = [string]$State.NmeClientIdBox.Text; ClientSecret = $State.NmeClientSecretBox.SecurePassword.Copy()
                    ApiScope = [string]$State.NmeApiScopeBox.Text; NmeHost = [string]$State.NmeHostBox.Text
                    OAuthTokenUrl = [string]$State.NmeOAuthTokenUrlBox.Text
                    ResourceGroupName = [string]$State.NmeResourceGroupCombo.SelectedItem
                    StorageAccountName = [string]$State.NmeStorageAccountCombo.SelectedItem
                    ContainerName = [string]$State.NmeContainerCombo.SelectedItem
                }
                $State.NmeClientSecretBox.Clear()
                $body = {
                    param($Identity, $Parameters)
                    try {
                        & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwAzureIdentity -Identity $Value } $Identity
                        Connect-EwNerdio @Parameters
                    }
                    finally { $Parameters.ClientSecret.Dispose() }
                }
                $arguments = @($State.NerdioAzureIdentity, $parameters)
            }
            'Compare' {
                if ($null -eq $State.NerdioDestination) { throw 'Connect to Nerdio before comparing.' }
                $root = [string]$State.Settings.NerdioDefinitionsPath
                if (-not $root -or $root -ne $State.NerdioDefinitionsPathBox.Text) { throw 'Save the Shell App definitions path before comparing.' }
                $State.NerdioPlan = $null
                $State.NerdioComparisonListView.ItemsSource = @()
                $body = {
                    param($Root, $Destination)
                    & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwNerdioDestination -Destination $Value } $Destination
                    $plan = Get-EwNerdioPublishPlan -DefinitionPath $Root
                    & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwNerdioDestination -Destination $Value } $Destination
                    $plan
                }
                $arguments = @($root, $State.NerdioDestination)
            }
            'Publish' {
                if ($State.NerdioBlockedOutcomes.Count -gt 0) { throw 'Review and acknowledge all pending or unknown outcomes before another Nerdio write.' }
                $plan = $State.NerdioPlan
                $selection = @($State.NerdioComparisonListView.SelectedItems)
                if ($null -eq $plan -or $selection.Count -eq 0) { throw 'Compare and select eligible apps first.' }
                foreach ($row in $selection) {
                    if (-not $row.Eligible -or $State.NerdioBlockedOutcomes.ContainsKey("$($plan.Destination.NmeHost)|$($row.DefinitionPath)")) {
                        throw 'An item is ineligible or has an outcome that still needs review.'
                    }
                }
                if (-not (Confirm-EwWorkbenchNerdioBatch -Window $State.Window -Selection $selection -Destination $plan.Destination)) { return }
                $State.NerdioInFlightSelections = $selection
                $State.NerdioCancellation = [System.Threading.CancellationTokenSource]::new()
                $body = {
                    param($Plan, $Selection, $Working, $Token)
                    Publish-EwNerdioBatch -Plan $Plan -Selection $Selection -WorkingPath $Working -CancellationToken $Token -Confirm:$false
                }
                $arguments = [object[]]::new(4)
                $arguments[0] = $plan
                $arguments[1] = [object[]]$selection
                $arguments[2] = [string]$State.Settings.OutputPath
                $arguments[3] = $State.NerdioCancellation.Token
            }
        }
        Invoke-EwWorkbenchJob -State $State -Kind "Nerdio$Action" -Name "Nerdio $Action" -ScriptBlock $body -ArgumentList $arguments
    }
    catch {
        if ($Action -eq 'Publish' -and $null -ne $State.NerdioCancellation) {
            $State.NerdioCancellation.Dispose()
            $State.NerdioCancellation = $null
        }
        if ($Action -eq 'ApiConnect' -and $null -ne (Get-Variable -Name parameters -ValueOnly -ErrorAction SilentlyContinue)) {
            $parameters.ClientSecret.Dispose()
        }
        Write-EwWorkbenchLog -State $State -Message ("Nerdio $Action failed: " + ($_.Exception.Message -replace 'https?://\S+', '[URL omitted]')) -Level Error
    }
}
