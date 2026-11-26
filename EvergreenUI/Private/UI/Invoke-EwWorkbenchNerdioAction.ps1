Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchNerdioAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)]
        [ValidateSet('AzureConnect', 'Disconnect', 'Storage', 'Containers', 'ApiConnect', 'Compare', 'Publish', 'Cancel', 'Save', 'Browse', 'Review', 'Prune', 'PruneExisting', 'PruneSelected')]
        [string]$Action,

        [Parameter()]
        [object[]]$Selection = @()
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
                if ($null -eq $result -or $result.Status -notin @('Pending', 'Unknown') -or
                    -not $result.RecoveryOperationId) { return }
                $answer = Show-EwWorkbenchNerdioReviewDialog -Owner $State.Window -Result $result
                switch ($answer) {
                    ([System.Windows.MessageBoxResult]::Cancel) { return }
                    ([System.Windows.MessageBoxResult]::Yes) { $outcome = 'Completed' }
                    ([System.Windows.MessageBoxResult]::No) { $outcome = 'Failed' }
                    default { throw "Unexpected Nerdio review result: $answer" }
                }
                $body = {
                    param($OperationId, $Outcome)
                    & (Get-Module -Name EvergreenUI) {
                        param($OperationId, $Outcome)
                        Resolve-EwNerdioOperationReview -OperationId $OperationId -Outcome $Outcome
                    } $OperationId $Outcome
                }
                $arguments = @([string]$result.RecoveryOperationId, $outcome)
            }
            'Prune' {
                if (-not (Sync-EwWorkbenchNerdioRecoveryState -State $State)) {
                    throw 'Nerdio recovery state is unavailable; pruning is blocked.'
                }
                if ($State.NerdioBlockedOutcomes.Count -gt 0) {
                    throw 'Review all pending or unknown Nerdio outcomes before pruning.'
                }
                if ($null -eq $State.NerdioDestination) { throw 'Reconnect to the Nerdio destination before pruning.' }
                $offers = @($State.NerdioPruningOffers)
                if ($offers.Count -eq 0) { throw 'There are no successful Nerdio publishes available to prune.' }
                $body = {
                    param($Offers)
                    & (Get-Module -Name EvergreenUI) {
                        param($Offers)
                        $context = Get-EwNerdioSessionContext
                        foreach ($offer in $Offers) {
                            Assert-EwNerdioRecoveryDestination -Context $context -Destination $offer.Destination
                            $plan = Get-EwNerdioShellAppVersionPrunePlan -Id $offer.AppId `
                                -PublishedVersion $offer.PublishedVersion
                            $plan | Add-Member -NotePropertyMembers @{
                                OfferId = [string]$offer.Id
                                Destination = $offer.Destination
                                Name = [string]$offer.Name
                                Publisher = [string]$offer.Publisher
                                DefinitionPath = [string]$offer.DefinitionPath
                            }
                            $plan
                        }
                    } $Offers
                }
                $arguments = ,([object[]]$offers)
            }
            'PruneExisting' {
                if (-not (Sync-EwWorkbenchNerdioRecoveryState -State $State)) {
                    throw 'Nerdio recovery state is unavailable; pruning is blocked.'
                }
                if ($State.NerdioBlockedOutcomes.Count -gt 0) {
                    throw 'Review all pending or unknown Nerdio outcomes before pruning.'
                }
                if ($null -eq $State.NerdioDestination) { throw 'Reconnect to the Nerdio destination before pruning.' }
                $rows = @($State.NerdioComparisonListView.SelectedItems)
                if ($null -eq $State.NerdioPlan -or $rows.Count -ne 1 -or
                    (Get-EwFirstPropertyValue -InputObject $rows[0] -Name 'RowType') -ne 'Definition' -or
                    [string]::IsNullOrWhiteSpace([string]$rows[0].NerdioAppId)) {
                    throw 'Compare and select one matched existing Shell App to prune.'
                }
                $body = {
                    param($Row, $Destination)
                    & (Get-Module -Name EvergreenUI) {
                        param($Row, $Destination)
                        Assert-EwNerdioDestination -Destination $Destination
                        $plan = Get-EwNerdioShellAppVersionPrunePlan -Id $Row.NerdioAppId
                        Assert-EwNerdioDestination -Destination $Destination
                        $plan | Add-Member -NotePropertyMembers @{
                            OfferId = ''
                            Destination = $Destination
                            Name = [string]$Row.NerdioAppName
                            Publisher = [string]$Row.Publisher
                            DefinitionPath = [string]$Row.DefinitionPath
                        }
                        $plan
                    } $Row $Destination
                }
                $arguments = @($rows[0], $State.NerdioPlan.Destination)
            }
            'PruneSelected' {
                if ($Selection.Count -eq 0) { $Selection = @($State.NerdioSelectedPrunePlans) }
                if (-not (Sync-EwWorkbenchNerdioRecoveryState -State $State)) {
                    throw 'Nerdio recovery state is unavailable; pruning is blocked.'
                }
                if ($State.NerdioBlockedOutcomes.Count -gt 0) {
                    throw 'Review all pending or unknown Nerdio outcomes before pruning.'
                }
                if ($Selection.Count -eq 0) { throw 'Select at least one Shell App to prune.' }
                if (@($Selection | Where-Object { -not $_.Eligible -or @($_.Remove).Count -eq 0 }).Count -gt 0) {
                    throw 'The selection contains a Shell App without a safe deletion plan.'
                }
                $body = {
                    param($Plans)
                    & (Get-Module -Name EvergreenUI) {
                        param($Plans)
                        foreach ($plan in $Plans) {
                            $recovery = Invoke-EwNerdioRecoveryStore -Action Read
                            if (@($recovery.Operations).Count -gt 0) {
                                throw 'Review all pending or unknown Nerdio outcomes before pruning.'
                            }
                            if ($plan.OfferId) {
                                Assert-EwNerdioRecoveryDestination -Context (Get-EwNerdioSessionContext) -Destination $plan.Destination
                            }
                            else {
                                Assert-EwNerdioDestination -Destination $plan.Destination
                            }
                            $result = Remove-EwNerdioShellAppVersion -Id $plan.Id `
                                -KeepVersions $plan.KeepVersions -ExpectedVersionNames $plan.VersionNames `
                                -ExpectedRemovalVersions $plan.Remove -OfferId $plan.OfferId -Confirm:$false
                            $result
                            if ($result.PendingVersions.Count -gt 0 -or $result.UnknownVersions.Count -gt 0) { break }
                        }
                    } $Plans
                }
                $arguments = ,([object[]]$Selection)
                $State.NerdioPruneSelectionId = if ($Selection.Count -eq 1 -and -not $Selection[0].OfferId) {
                    [string]$Selection[0].Id
                } else { '' }
                $State.NerdioSelectedPrunePlans = @()
            }
            'AzureConnect' {
                $preserveApiOnly = $null -ne $State.NerdioDestination -and
                    [bool](Get-EwFirstPropertyValue -InputObject $State.NerdioDestination -Name 'ApiOnly')
                Clear-EwWorkbenchNerdioComparison -State $State -AzureChanged $true `
                    -ConnectionChanged (-not $preserveApiOnly)
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
                $apiOnly = [bool]$State.NerdioApiOnlyToggle.IsChecked -or
                    $null -eq $State.NerdioAzureIdentity -or -not $State.NmeContainerCombo.SelectedItem
                $parameters = @{
                    TenantId = [string]$State.NerdioTenantIdBox.Text
                    ClientId = [string]$State.NmeClientIdBox.Text; ClientSecret = $State.NmeClientSecretBox.SecurePassword.Copy()
                    ApiScope = [string]$State.NmeApiScopeBox.Text; NmeHost = [string]$State.NmeHostBox.Text
                    OAuthTokenUrl = [string]$State.NmeOAuthTokenUrlBox.Text
                }
                if ($apiOnly) { $parameters.ApiOnly = $true }
                else {
                    $parameters.SubscriptionId = [string]$State.NmeSubscriptionIdBox.Text
                    $parameters.ResourceGroupName = [string]$State.NmeResourceGroupCombo.SelectedItem
                    $parameters.StorageAccountName = [string]$State.NmeStorageAccountCombo.SelectedItem
                    $parameters.ContainerName = [string]$State.NmeContainerCombo.SelectedItem
                }
                $State.NmeClientSecretBox.Clear()
                $body = {
                    param($Identity, $Parameters)
                    try {
                        if (-not $Parameters.ContainsKey('ApiOnly')) {
                            & (Get-Module -Name EvergreenUI) { param($Value) Assert-EwAzureIdentity -Identity $Value } $Identity
                        }
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
                if (-not (Sync-EwWorkbenchNerdioRecoveryState -State $State)) {
                    throw 'Nerdio recovery state is unavailable; publishing is blocked.'
                }
                if (@($State.NerdioBlockedOutcomes.Values | Where-Object Type -eq 'Publish').Count -gt 0) {
                    throw 'Review and acknowledge the pending or unknown publish outcome before another Nerdio write.'
                }
                $plan = $State.NerdioPlan
                $selection = @($State.NerdioComparisonListView.SelectedItems)
                if ($null -eq $plan -or $selection.Count -eq 0) { throw 'Compare and select eligible apps first.' }
                foreach ($row in $selection) {
                    $deleteBlocked = @($State.NerdioBlockedOutcomes.Values | Where-Object {
                            $_.Type -eq 'Delete' -and $_.AppId -eq [string]$row.NerdioAppId
                        }).Count -gt 0
                    if (-not $row.Eligible) {
                        throw 'An item is ineligible or has an outcome that still needs review.'
                    }
                    if ($deleteBlocked) { throw 'A deletion outcome for a selected Shell App still needs review.' }
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
        $kind = if ($Action -in @('Prune', 'PruneExisting')) { 'NerdioPrunePreview' } else { "Nerdio$Action" }
        Invoke-EwWorkbenchJob -State $State -Kind $kind -Name "Nerdio $Action" -ScriptBlock $body -ArgumentList $arguments
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
