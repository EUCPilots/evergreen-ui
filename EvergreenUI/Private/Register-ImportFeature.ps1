function Register-ImportFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Import feature (Intune, M365, Nerdio, and authentication).

    .DESCRIPTION
    Sets up event handlers for the Import navigation view and its provider sub-tabs.
    This registration function does not recreate the import logic; it wires the
    already-defined helper scriptblocks and async operations from Start-EvergreenWorkbench
    to the matching WPF controls resolved from XAML.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Import feature.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $importProviderTabControl = $Controls.ImportProviderTabControl
    $importSignInButton = $Controls.ImportSignInButton
    $importSignOutButton = $Controls.ImportSignOutButton
    $importTenantIdBox = $Controls.ImportTenantIdBox
    $nerdioApiSignInButton = $Controls.NerdioApiSignInButton
    $nerdioApiSignOutButton = $Controls.NerdioApiSignOutButton
    $nerdioAzureSignInButton = $Controls.NerdioAzureSignInButton
    $nerdioAzureSignOutButton = $Controls.NerdioAzureSignOutButton
    $nerdioTenantIdBox = $Controls.NerdioTenantIdBox
    $nmeHostBox = $Controls.NmeHostBox
    $nmeClientIdBox = $Controls.NmeClientIdBox
    $nmeApiScopeBox = $Controls.NmeApiScopeBox
    $nmeOAuthTokenUrlBox = $Controls.NmeOAuthTokenUrlBox
    $nmeSubscriptionIdBox = $Controls.NmeSubscriptionIdBox
    $nmeResourceGroupCombo = $Controls.NmeResourceGroupCombo
    $nmeStorageAccountCombo = $Controls.NmeStorageAccountCombo
    $nmeContainerCombo = $Controls.NmeContainerCombo
    $intuneDefinitionsPathBox = $Controls.IntuneDefinitionsPathBox
    $intunePackageOutputPathBox = $Controls.IntunePackageOutputPathBox
    $intuneBrowsePackageOutputButton = $Controls.IntuneBrowsePackageOutputButton
    $browseIntuneDefinitionsButton = $Controls.BrowseIntuneDefinitionsButton
    $intuneLoadDefinitionsButton = $Controls.IntuneLoadDefinitionsButton
    $intuneUpdateDefinitionsButton = $Controls.IntuneUpdateDefinitionsButton
    $intuneRefreshCatalogButton = $Controls.IntuneRefreshCatalogButton
    $intuneApplyImportButton = $Controls.IntuneApplyImportButton
    $intuneApplyUpdateImportButton = $Controls.IntuneApplyUpdateImportButton
    $nerdioDefinitionsPathBox = $Controls.NerdioDefinitionsPathBox
    $browseNerdioDefinitionsButton = $Controls.BrowseNerdioDefinitionsButton
    $nerdioLoadDefinitionsButton = $Controls.NerdioLoadDefinitionsButton
    $nerdioLoadConfigsButton = $Controls.NerdioLoadConfigsButton
    $nerdioListShellAppsButton = $Controls.NerdioListShellAppsButton
    $nerdioAddVersionButton = $Controls.NerdioAddVersionButton
    $nerdioPruneVersionsButton = $Controls.NerdioPruneVersionsButton
    $nerdioImportNewButton = $Controls.NerdioImportNewButton
    $m365ConfigPathBox = $Controls.M365ConfigPathBox
    $browseM365ConfigButton = $Controls.BrowseM365ConfigButton
    $m365LoadConfigsButton = $Controls.M365LoadConfigsButton
    $m365ChannelCombo = $Controls.M365ChannelCombo
    $m365CompanyNameBox = $Controls.M365CompanyNameBox
    $m365ImportForCombo = $Controls.M365ImportForCombo
    $m365ImportIntuneButton = $Controls.M365ImportIntuneButton
    $m365ImportNerdioButton = $Controls.M365ImportNerdioButton

    $getHelperScriptBlock = {
        param([string]$Name)

        foreach ($scopeLevel in 1..3) {
            $candidate = Get-Variable -Name $Name -Scope $scopeLevel -ErrorAction SilentlyContinue
            if ($null -ne $candidate -and $candidate.Value -is [scriptblock]) {
                return $candidate.Value
            }
        }

        return $null
    }

    # Bind the helper scriptblocks to the sync hash so navigation and dynamic updates can access them.
    foreach ($helperName in @(
            'RefreshImportAuthUi',
            'RefreshNerdioApiAuthUi',
            'RefreshNerdioAzureAuthUi',
            'NormalizeImportProvider',
            'SetImportProvider',
            'NormalizeDirectoryPath',
            'SetImportTabVisibility',
            'ApplyImportTenantToConfig',
            'ApplyNerdioTenantToConfig',
            'ApplyNerdioDefinitionsPathToConfig',
            'ApplyIntunePathsToConfig',
            'ApplyM365PathsToConfig',
            'LoadIntuneDefinitions',
            'UpdateIntuneDefinitions',
            'LoadIntuneWin32Apps',
            'LoadNerdioDefinitions',
            'LoadNerdioShellApps',
            'StartNerdioAddVersion',
            'StartNerdioPruneVersions',
            'StartNerdioImportNew',
            'LoadM365Configs',
            'StartM365IntuneImport',
            'StartM365NerdioImport',
            'StartImportSignIn',
            'StartImportSignOut',
            'StartNerdioApiSignIn',
            'StartNerdioApiSignOut',
            'StartNerdioAzureSignIn',
            'StartNerdioAzureSignOut',
            'RequireImportAuth',
            'UpdateIntuneRowActionButtons',
            'UpdateNerdioRowActionButtons',
            'UpdateM365ActionButtons',
            'RefreshIntuneComparison',
            'RefreshNerdioComparison',
            'ApplyNerdioSort',
            'ApplyM365Sort',
            'ApplyIntuneListSort'
        )) {
        $helperScriptBlock = & $getHelperScriptBlock -Name $helperName
        if ($null -ne $helperScriptBlock) {
            $SyncHash[$helperName] = $helperScriptBlock
        }
    }

    if ($null -ne $importProviderTabControl) {
        $importProviderTabControl.add_SelectionChanged({
                param($s, $e)
                [void]$e
                if ($s -ne $importProviderTabControl) { return }
                $provider = switch ($importProviderTabControl.SelectedIndex) {
                    0 { 'Authentication' }
                    1 { 'Intune' }
                    2 { 'Nerdio' }
                    3 { 'M365' }
                    default { 'Authentication' }
                }
                & ($SyncHash['SetImportProvider']) -Provider $provider -Persist
            }.GetNewClosure())
    }

    if ($null -ne $importSignInButton) {
        $importSignInButton.add_Click({
                & ($SyncHash['ApplyImportTenantToConfig'])
                & ($SyncHash['StartImportSignIn'])
            }.GetNewClosure())
    }

    if ($null -ne $importSignOutButton) {
        $importSignOutButton.add_Click({
                & ($SyncHash['StartImportSignOut'])
            }.GetNewClosure())
    }

    if ($null -ne $importTenantIdBox) {
        $importTenantIdBox.add_LostFocus({
                & ($SyncHash['ApplyImportTenantToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioApiSignInButton) {
        $nerdioApiSignInButton.add_Click({
                & ($SyncHash['ApplyNerdioTenantToConfig'])
                & ($SyncHash['StartNerdioApiSignIn'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioApiSignOutButton) {
        $nerdioApiSignOutButton.add_Click({
                & ($SyncHash['StartNerdioApiSignOut'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioAzureSignInButton) {
        $nerdioAzureSignInButton.add_Click({
                & ($SyncHash['ApplyNerdioTenantToConfig'])
                & ($SyncHash['StartNerdioAzureSignIn'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioAzureSignOutButton) {
        $nerdioAzureSignOutButton.add_Click({
                & ($SyncHash['StartNerdioAzureSignOut'])
            }.GetNewClosure())
    }

    if ($null -ne $nmeSubscriptionIdBox) {
        $nmeSubscriptionIdBox.add_TextChanged({
                $notAuthenticated = -not [bool]$SyncHash.NerdioAzureAuthState.IsAuthenticated
                if ($null -ne $nerdioAzureSignInButton) {
                    $nerdioAzureSignInButton.IsEnabled = $notAuthenticated -and (-not [string]::IsNullOrWhiteSpace($nmeSubscriptionIdBox.Text))
                }
                $SyncHash.Config.NerdioSettings.NmeSubscriptionId = [string]$nmeSubscriptionIdBox.Text
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nmeHostBox) {
        $nmeHostBox.add_TextChanged({
                $SyncHash.Config.NerdioSettings.NmeHost = [string]$nmeHostBox.Text
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nmeClientIdBox) {
        $nmeClientIdBox.add_TextChanged({
                $SyncHash.Config.NerdioSettings.NmeClientId = [string]$nmeClientIdBox.Text
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nmeApiScopeBox) {
        $nmeApiScopeBox.add_TextChanged({
                $SyncHash.Config.NerdioSettings.NmeApiScope = [string]$nmeApiScopeBox.Text
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nmeOAuthTokenUrlBox) {
        $nmeOAuthTokenUrlBox.add_TextChanged({
                $SyncHash.Config.NerdioSettings.NmeOAuthTokenUrl = [string]$nmeOAuthTokenUrlBox.Text
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nmeResourceGroupCombo) {
        $nmeResourceGroupCombo.add_SelectionChanged({
                $rg = [string]$nmeResourceGroupCombo.SelectedItem
                $nmeStorageAccountCombo.Items.Clear()
                $nmeContainerCombo.Items.Clear()
                $nmeStorageAccountCombo.IsEnabled = $false
                $nmeContainerCombo.IsEnabled = $false
                if ([string]::IsNullOrWhiteSpace($rg)) { return }

                $existingResourceGroup = [string]$SyncHash.Config.NerdioSettings.NmeResourceGroup
                $SyncHash.Config.NerdioSettings.NmeResourceGroup = $rg
                if ($rg -ne $existingResourceGroup) {
                    $SyncHash.Config.NerdioSettings.NmeStorageAccount = ''
                    $SyncHash.Config.NerdioSettings.NmeContainer = ''
                }
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Loading storage accounts for '$rg'..." -Level Info
                $accounts = Get-NerdioAzureStorageAccount -ResourceGroupName $rg
                foreach ($sa in $accounts) { [void]$nmeStorageAccountCombo.Items.Add($sa) }
                $nmeStorageAccountCombo.IsEnabled = ($nmeStorageAccountCombo.Items.Count -gt 0)
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "$($nmeStorageAccountCombo.Items.Count) storage account(s) loaded." -Level Info
            }.GetNewClosure())
    }

    if ($null -ne $nmeStorageAccountCombo) {
        $nmeStorageAccountCombo.add_SelectionChanged({
                $rg = [string]$nmeResourceGroupCombo.SelectedItem
                $sa = [string]$nmeStorageAccountCombo.SelectedItem
                $nmeContainerCombo.Items.Clear()
                $nmeContainerCombo.IsEnabled = $false
                if ([string]::IsNullOrWhiteSpace($rg) -or [string]::IsNullOrWhiteSpace($sa)) { return }

                $existingStorageAccount = [string]$SyncHash.Config.NerdioSettings.NmeStorageAccount
                $SyncHash.Config.NerdioSettings.NmeResourceGroup = $rg
                $SyncHash.Config.NerdioSettings.NmeStorageAccount = $sa
                if ($sa -ne $existingStorageAccount) {
                    $SyncHash.Config.NerdioSettings.NmeContainer = ''
                }
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config

                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Loading containers for '$sa'..." -Level Info
                $containers = Get-NerdioAzureStorageContainer -ResourceGroupName $rg -StorageAccountName $sa
                foreach ($c in $containers) { [void]$nmeContainerCombo.Items.Add($c) }
                $nmeContainerCombo.IsEnabled = ($nmeContainerCombo.Items.Count -gt 0)
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "$($nmeContainerCombo.Items.Count) container(s) loaded." -Level Info
            }.GetNewClosure())
    }

    if ($null -ne $nmeContainerCombo) {
        $nmeContainerCombo.add_SelectionChanged({
                $rg = [string]$nmeResourceGroupCombo.SelectedItem
                $sa = [string]$nmeStorageAccountCombo.SelectedItem
                $container = [string]$nmeContainerCombo.SelectedItem
                if ([string]::IsNullOrWhiteSpace($rg) -or [string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($container)) { return }

                $SyncHash.Config.NerdioSettings.NmeResourceGroup = $rg
                $SyncHash.Config.NerdioSettings.NmeStorageAccount = $sa
                $SyncHash.Config.NerdioSettings.NmeContainer = $container
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $nerdioTenantIdBox) {
        $nerdioTenantIdBox.add_LostFocus({
                & ($SyncHash['ApplyNerdioTenantToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioDefinitionsPathBox) {
        $nerdioDefinitionsPathBox.add_LostFocus({
                $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $nerdioDefinitionsPathBox.Text
                $nerdioDefinitionsPathBox.Text = $normalised
                & ($SyncHash['ApplyNerdioDefinitionsPathToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $browseNerdioDefinitionsButton) {
        $browseNerdioDefinitionsButton.add_Click({
                $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dlg.Description = 'Select Shell App definitions folder'
                if (-not [string]::IsNullOrWhiteSpace($nerdioDefinitionsPathBox.Text)) {
                    $dlg.SelectedPath = $nerdioDefinitionsPathBox.Text
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $nerdioDefinitionsPathBox.Text = $dlg.SelectedPath
                    & ($SyncHash['ApplyNerdioDefinitionsPathToConfig'])
                }
            }.GetNewClosure())
    }

    if ($null -ne $nerdioLoadDefinitionsButton) {
        $nerdioLoadDefinitionsButton.add_Click({
                & ($SyncHash['LoadNerdioDefinitions'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioLoadConfigsButton) {
        $nerdioLoadConfigsButton.add_Click({
                & ($SyncHash['LoadNerdioDefinitions'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioListShellAppsButton) {
        $nerdioListShellAppsButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'List Shell Apps and compare updates' -Provider 'Nerdio')) { return }
                & ($SyncHash['LoadNerdioShellApps'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioAddVersionButton) {
        $nerdioAddVersionButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'Add Shell App version' -Provider 'Nerdio')) { return }
                & ($SyncHash['StartNerdioAddVersion'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioPruneVersionsButton) {
        $nerdioPruneVersionsButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'Prune Shell App versions' -Provider 'Nerdio')) { return }
                & ($SyncHash['StartNerdioPruneVersions'])
            }.GetNewClosure())
    }

    if ($null -ne $nerdioImportNewButton) {
        $nerdioImportNewButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'Import new Shell App' -Provider 'Nerdio')) { return }
                & ($SyncHash['StartNerdioImportNew'])
            }.GetNewClosure())
    }

    if ($null -ne $browseM365ConfigButton) {
        $browseM365ConfigButton.add_Click({
                $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dlg.Description = 'Select Microsoft 365 Apps configuration files folder'
                if (-not [string]::IsNullOrWhiteSpace($m365ConfigPathBox.Text)) {
                    $dlg.SelectedPath = $m365ConfigPathBox.Text
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $dlg.SelectedPath
                    $m365ConfigPathBox.Text = $normalised
                    & ($SyncHash['ApplyM365PathsToConfig'])
                }
            }.GetNewClosure())
    }

    if ($null -ne $m365LoadConfigsButton) {
        $m365LoadConfigsButton.add_Click({
                & ($SyncHash['LoadM365Configs'])
            }.GetNewClosure())
    }

    if ($null -ne $m365ConfigPathBox) {
        $m365ConfigPathBox.add_LostFocus({
                $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $m365ConfigPathBox.Text
                $m365ConfigPathBox.Text = $normalised
                & ($SyncHash['ApplyM365PathsToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $m365ChannelCombo) {
        $m365ChannelCombo.add_SelectionChanged({
                $selectedChannel = if ($null -ne $m365ChannelCombo.SelectedItem) { [string]$m365ChannelCombo.SelectedItem.Content } else { '' }
                $SyncHash.Config.M365Settings.Channel = $selectedChannel
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $m365CompanyNameBox) {
        $m365CompanyNameBox.add_LostFocus({
                $SyncHash.Config.M365Settings.CompanyName = $m365CompanyNameBox.Text.Trim()
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
            }.GetNewClosure())
    }

    if ($null -ne $m365ImportForCombo) {
        $m365ImportForCombo.add_SelectionChanged({
                $selectedImportFor = if ($null -ne $m365ImportForCombo.SelectedItem) { [string]$m365ImportForCombo.SelectedItem.Content } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($selectedImportFor)) {
                    $SyncHash.Config.M365Settings.ImportFor = $selectedImportFor
                    & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                }
            }.GetNewClosure())
    }

    if ($null -ne $m365ImportIntuneButton) {
        $m365ImportIntuneButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'M365 Intune import')) { return }
                & ($SyncHash['StartM365IntuneImport'])
            }.GetNewClosure())
    }

    if ($null -ne $m365ImportNerdioButton) {
        $m365ImportNerdioButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'M365 Nerdio import' -Provider 'Nerdio')) { return }
                & ($SyncHash['StartM365NerdioImport'])
            }.GetNewClosure())
    }

    if ($null -ne $intuneRefreshCatalogButton) {
        $intuneRefreshCatalogButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'List Intune Win32 apps')) { return }
                & ($SyncHash['LoadIntuneWin32Apps'])
            }.GetNewClosure())
    }

    if ($null -ne $browseIntuneDefinitionsButton) {
        $browseIntuneDefinitionsButton.add_Click({
                $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dlg.Description = 'Select Intune package definitions folder'
                if (-not [string]::IsNullOrWhiteSpace($intuneDefinitionsPathBox.Text)) {
                    $dlg.SelectedPath = $intuneDefinitionsPathBox.Text
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $dlg.SelectedPath
                    $intuneDefinitionsPathBox.Text = $normalised
                    & ($SyncHash['ApplyIntunePathsToConfig'])
                }
            }.GetNewClosure())
    }

    if ($null -ne $intuneLoadDefinitionsButton) {
        $intuneLoadDefinitionsButton.add_Click({
                & ($SyncHash['LoadIntuneDefinitions'])
            }.GetNewClosure())
    }

    if ($null -ne $intuneUpdateDefinitionsButton) {
        $intuneUpdateDefinitionsButton.add_Click({
                & ($SyncHash['UpdateIntuneDefinitions'])
            }.GetNewClosure())
    }

    if ($null -ne $intuneBrowsePackageOutputButton) {
        $intuneBrowsePackageOutputButton.add_Click({
                $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dlg.Description = 'Select Intune package output folder'
                if (-not [string]::IsNullOrWhiteSpace($intunePackageOutputPathBox.Text)) {
                    $dlg.SelectedPath = $intunePackageOutputPathBox.Text
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $dlg.SelectedPath
                    $intunePackageOutputPathBox.Text = $normalised
                    & ($SyncHash['ApplyIntunePathsToConfig'])
                }
            }.GetNewClosure())
    }

    if ($null -ne $intuneDefinitionsPathBox) {
        $intuneDefinitionsPathBox.add_LostFocus({
                $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $intuneDefinitionsPathBox.Text
                $intuneDefinitionsPathBox.Text = $normalised
                & ($SyncHash['ApplyIntunePathsToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $intunePackageOutputPathBox) {
        $intunePackageOutputPathBox.add_LostFocus({
                $normalised = & ($SyncHash['NormalizeDirectoryPath']) -PathValue $intunePackageOutputPathBox.Text
                $intunePackageOutputPathBox.Text = $normalised
                & ($SyncHash['ApplyIntunePathsToConfig'])
            }.GetNewClosure())
    }

    if ($null -ne $intuneApplyImportButton) {
        $intuneApplyImportButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'Intune apply import')) { return }
                & ($SyncHash['StartIntuneImportOperation']) -ImportAsUpdate $false
            }.GetNewClosure())
    }

    if ($null -ne $intuneApplyUpdateImportButton) {
        $intuneApplyUpdateImportButton.add_Click({
                if (-not (& ($SyncHash['RequireImportAuth']) -ActionName 'Intune apply update import')) { return }
                & ($SyncHash['StartIntuneImportOperation']) -ImportAsUpdate $true
            }.GetNewClosure())
    }

    Write-Verbose 'EvergreenUI: Import feature registered.'
}
