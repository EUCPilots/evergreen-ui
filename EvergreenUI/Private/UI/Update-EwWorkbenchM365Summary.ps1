Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwWorkbenchM365Summary {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates only an in-memory summary card.')]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State, [Parameter(Mandatory)][string]$Provider)

    $view = $State.M365Views[$Provider]
    $card = $State["${Provider}M365SummaryCard"]
    if ($null -eq $card) { return }
    $visibility = { param([bool]$Condition) if ($Condition) { 'Visible' } else { 'Collapsed' } }
    $row = {
        param([string]$Label, [string]$Value, [string]$Note = '')
        [PSCustomObject]@{
            Label = $Label; Value = $Value; Note = $Note
            NoteVisibility = & $visibility (-not [string]::IsNullOrWhiteSpace($Note))
        }
    }
    $model = [ordered]@{
        EmptyVisibility = 'Collapsed'; DetailsVisibility = 'Collapsed'; WarningVisibility = 'Collapsed'; WarningText = ''
        Title = ''; Description = ''; DescriptionVisibility = 'Collapsed'; FileName = ''
        IncludedApps = [string[]]@(); IncludedVisibility = 'Collapsed'; NoIncludedVisibility = 'Collapsed'
        ExcludedApps = [string[]]@(); ExcludedVisibility = 'Collapsed'
        AdditionalProducts = [string[]]@(); AdditionalVisibility = 'Collapsed'
        DeploymentRows = @(); BehaviourRows = @(); UserSettingsText = ''
    }

    $selected = $view.ConfigurationCombo.SelectedItem
    if ($null -eq $selected) {
        $model.EmptyVisibility = 'Visible'
        $card.Content = [PSCustomObject]$model
        return
    }
    $status = [string]$selected.Status
    $model.FileName = [string]$selected.FileName
    $model.WarningText = switch ($status) {
        'No ID' { 'This configuration has no ID attribute. Add a GUID ID to the Configuration element before building.' }
        'Invalid ID' { 'The configuration ID is not a valid GUID. Correct the ID attribute before building.' }
        'Invalid XML' { 'This file could not be read as an Office Deployment Tool configuration.' }
        default { '' }
    }
    $model.WarningVisibility = & $visibility (-not [string]::IsNullOrWhiteSpace($model.WarningText))
    $summary = if ($selected.PSObject.Properties.Name -contains 'Summary') { $selected.Summary } else { $null }
    if ($null -eq $summary) {
        $model.Title = [string]$selected.DisplayName
        $card.Content = [PSCustomObject]$model
        return
    }

    $model.DetailsVisibility = 'Visible'
    $model.Title = if ([string]::IsNullOrWhiteSpace($summary.PrimaryProduct)) { [string]$selected.DisplayName } else { $summary.PrimaryProduct }
    $model.Description = $summary.Description
    $model.DescriptionVisibility = & $visibility (-not [string]::IsNullOrWhiteSpace($summary.Description))
    $model.IncludedApps = [string[]]@($summary.IncludedApps)
    $model.IncludedVisibility = & $visibility ($model.IncludedApps.Count -gt 0)
    $model.NoIncludedVisibility = & $visibility ($model.IncludedApps.Count -eq 0)
    $model.ExcludedApps = [string[]]@($summary.ExcludedApps)
    $model.ExcludedVisibility = & $visibility ($model.ExcludedApps.Count -gt 0)
    $model.AdditionalProducts = [string[]]@($summary.AdditionalProducts)
    $model.AdditionalVisibility = & $visibility ($model.AdditionalProducts.Count -gt 0)

    $fromForm = 'From form'
    $formChannel = [string]$view.ChannelCombo.SelectedItem
    $channelNote = ''
    $channel = $summary.Channel
    if (-not [string]::IsNullOrWhiteSpace($formChannel) -and $formChannel -ne $summary.Channel) {
        $channel = $formChannel
        $channelNote = $fromForm
    }
    $session = [string]$view.SessionCombo.SelectedItem
    $licensing = $summary.Licensing
    $licensingNote = ''
    if (-not [string]::IsNullOrWhiteSpace($session)) {
        $isVdi = $session -eq 'Multi-session'
        if ($isVdi -ne [bool]$summary.IsVdi) {
            $licensing = if ($isVdi) { 'Shared computer activation' }
            elseif ($summary.DeviceBasedLicensing) { 'Device-based licensing' }
            else { 'User-based licensing' }
            $licensingNote = $fromForm
        }
    }
    $company = [string]$view.CompanyBox.Text
    $companyNote = ''
    if (-not [string]::IsNullOrWhiteSpace($company)) {
        if ($company -ne $summary.CompanyName) { $companyNote = $fromForm }
    }
    elseif ([string]::IsNullOrWhiteSpace($summary.CompanyName) -or $summary.CompanyName.StartsWith('#')) {
        $company = 'Not set'
    }
    else {
        $company = $summary.CompanyName
    }
    $languages = if (@($summary.Languages).Count -gt 0) { @($summary.Languages) -join [System.Environment]::NewLine } else { 'Not specified' }
    $model.DeploymentRows = @(
        & $row 'Channel' (ConvertTo-EwM365ChannelName -Channel $channel) $channelNote
        & $row 'Architecture' $summary.Architecture
        & $row 'Licensing' $licensing $licensingNote
        & $row 'Languages' $languages
        & $row 'Company' $company $companyNote
        & $row 'Tenant' 'Connected tenant, set at build time'
    )
    $yesNo = { param([bool]$Value, [string]$Yes, [string]$No) if ($Value) { $Yes } else { $No } }
    $display = if ($summary.DisplayLevel -eq 'None') { 'Silent' } else { 'Shows setup progress' }
    if ($summary.AcceptEula) { $display += ', licence terms accepted' }
    $model.BehaviourRows = @(
        & $row 'Existing MSI Office' (& $yesNo $summary.RemoveMsi 'Removed before install' 'Left in place')
        & $row 'Existing bitness' (& $yesNo $summary.MigrateArchitecture "Changed to $($summary.Architecture)" 'Left unchanged')
        & $row 'Updates' (& $yesNo $summary.UpdatesEnabled 'Automatic updates enabled' 'Automatic updates disabled')
        & $row 'Open apps' (& $yesNo $summary.ForceAppShutdown 'Closed automatically during install' 'Not closed; install can fail while they are open')
        & $row 'Setup display' $display
    )
    $model.UserSettingsText = switch ($summary.UserSettingCount) {
        0 { 'No user settings applied.' }
        1 { '1 user setting applied.' }
        default { "$_ user settings applied." }
    }
    $card.Content = [PSCustomObject]$model
}
