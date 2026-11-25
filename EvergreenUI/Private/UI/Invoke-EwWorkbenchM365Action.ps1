Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchM365Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Intune', 'Nerdio')][string]$Provider,
        [Parameter(Mandatory)][ValidateSet('Browse', 'Load', 'Save', 'Targets', 'PreviewBuild', 'PreviewPublish',
            'Build', 'Publish', 'Cancel', 'Recovery', 'Review')][string]$Action
    )

    $view = $State.M365Views[$Provider]
    try {
        if ($Action -eq 'Cancel') {
            if ($null -ne $State.M365Cancellation) {
                $State.M365Cancellation.Cancel()
                Write-EwWorkbenchLog -State $State -Message 'Cancellation requested; the active stage will finish.' -Level Warning
                Invoke-EwWorkbenchM365BusyState -State $State
            }
            return
        }
        if ($null -ne $State.ActiveJobId) { throw 'Wait for the current operation to finish.' }
        switch ($Action) {
            'Browse' {
                $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
                if ($dialog.ShowDialog($State.Window)) { $view.PathBox.Text = $dialog.FolderName }
                return
            }
            'Save' {
                $values = @{
                    M365DefinitionsPath = [string]$view.PathBox.Text
                    M365Channel = [string]$view.ChannelCombo.SelectedItem
                    M365CompanyName = [string]$view.CompanyBox.Text
                    M365ImportFor = [string]$view.SessionCombo.SelectedItem
                }
                foreach ($name in $values.Keys) {
                    Set-EwSetting -Name $name -Value $values[$name]
                    $State.Settings[$name] = $values[$name]
                }
                $other = if ($Provider -eq 'Intune') { $State.M365Views.Nerdio } else { $State.M365Views.Intune }
                $other.PathBox.Text = $values.M365DefinitionsPath
                $other.ChannelCombo.SelectedItem = $values.M365Channel
                $other.CompanyBox.Text = $values.M365CompanyName
                $other.SessionCombo.SelectedItem = $values.M365ImportFor
                $other.ConfigurationCombo.ItemsSource = @()
                Clear-EwWorkbenchM365Preview -State $State -Provider $other.Provider
                Write-EwWorkbenchLog -State $State -Message 'Saved shared Microsoft 365 settings.'
                return
            }
            'Load' {
                $body = { param($Path) Get-EwM365Configuration -Path $Path }
                $arguments = @([string]$view.PathBox.Text)
            }
            'Targets' {
                if ($Provider -eq 'Intune') {
                    $selected = $view.ConfigurationCombo.SelectedItem
                    if ($null -eq $selected -or $selected.Status -ne 'Valid') { throw 'Select a valid configuration first.' }
                    $body = {
                        param($Id)
                        & (Get-Module -Name EvergreenUI) { param($Value) Get-EwM365IntuneMatch -ConfigurationId $Value } $Id
                    }
                    $arguments = @([string]$selected.ConfigId)
                }
                else {
                    $body = { Get-EwNerdioShellApp }
                    $arguments = @()
                }
            }
            { $_ -in @('PreviewBuild', 'PreviewPublish') } {
                $selected = $view.ConfigurationCombo.SelectedItem
                if ($null -eq $selected -or $selected.Status -ne 'Valid') { throw 'Select a configuration with a valid ID.' }
                $root = (Resolve-Path -LiteralPath $view.PathBox.Text -ErrorAction Stop).Path
                if ((Split-Path -Path $selected.FilePath -Parent) -ine $root) { throw 'Reload configurations for the current folder.' }
                $tenant = if ($Provider -eq 'Intune') { [string]$State.IntuneTenantId } else {
                    if ($null -eq $State.NerdioDestination) { '' } else { [string]$State.NerdioDestination.TenantId }
                }
                if ([string]::IsNullOrWhiteSpace($tenant)) { throw "Connect to $Provider before previewing." }
                $parameters = @{
                    ConfigurationPath = [string]$selected.FilePath; ConfigurationRoot = $root; Provider = $Provider
                    Channel = [string]$view.ChannelCombo.SelectedItem; CompanyName = [string]$view.CompanyBox.Text
                    ImportFor = [string]$view.SessionCombo.SelectedItem; TenantId = $tenant
                }
                $options = @{ Publish = $Action -eq 'PreviewPublish'; Provider = $Provider; PreviousAppId = ''; ShellAppId = ''; Name = ''; Operation = ''; Attested = $false }
                if ($Provider -eq 'Intune' -and $null -ne $view.TargetCombo.SelectedItem) {
                    $options.PreviousAppId = [string]$view.TargetCombo.SelectedItem.Id
                }
                if ($Provider -eq 'Nerdio') {
                    $options.Operation = [string]$State.NerdioM365OperationCombo.SelectedItem
                    $options.Name = [string]$State.NerdioM365NameBox.Text
                    $options.Attested = [bool]$State.NerdioM365AttestToggle.IsChecked
                    if ($null -ne $view.TargetCombo.SelectedItem -and $options.Operation -eq 'Add version') {
                        $options.ShellAppId = [string]$view.TargetCombo.SelectedItem.Id
                    }
                }
                $view.BuildPlan = $null
                $view.PublishPlan = $null
                $body = {
                    param($Parameters, $Options)
                    $build = Get-EwM365BuildPlan @Parameters
                    if (-not $Options.Publish) { return [PSCustomObject]@{ Build = $build; Publish = $null } }
                    $publish = if ($Options.Provider -eq 'Intune') {
                        Get-EwM365IntunePublishPlan -BuildPlan $build -PreviousAppId $Options.PreviousAppId
                    }
                    else {
                        Get-EwM365NerdioPublishPlan -BuildPlan $build -Operation $Options.Operation `
                            -Name $Options.Name -ShellAppId $Options.ShellAppId -SameVersionAttested:([bool]$Options.Attested)
                    }
                    [PSCustomObject]@{ Build = $build; Publish = $publish }
                }
                $arguments = @($parameters, $options)
            }
            { $_ -in @('Build', 'Publish') } {
                $plan = if ($Action -eq 'Build') { $view.BuildPlan } else { $view.PublishPlan }
                if ($null -eq $plan) { throw 'Preview this operation again before continuing.' }
                $build = if ($Action -eq 'Build') { $plan } else { $plan.BuildPlan }
                $working = [string]$State.Settings.PackageOutputPath
                if ([string]::IsNullOrWhiteSpace($working)) { $working = [string]$State.Settings.OutputPath }
                if ([string]::IsNullOrWhiteSpace($working)) { throw 'Save a package output path before building.' }
                $configuration = Read-EwM365Configuration -Path $build.ConfigurationPath
                $safeName = [regex]::Replace($configuration.DisplayName, '[\\/:*?"<>|]', '_').Trim('_')
                if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'Microsoft365Apps' }
                $output = Join-Path -Path $working -ChildPath "$safeName\Output"
                $filter = if ($Provider -eq 'Nerdio') { 'Microsoft365Apps.zip' } else { '*.intunewin' }
                $existing = @(if (Test-Path -LiteralPath $output -PathType Container) {
                    Get-ChildItem -LiteralPath $output -File -Filter $filter -ErrorAction Stop
                })
                $force = $false
                if ($existing.Count -gt 0) {
                    $names = ($existing | ForEach-Object Name) -join ', '
                    $answer = Confirm-EwWorkbenchM365Action -Window $State.Window `
                        -Message "A package may be replaced in $output`n$names`n`nAllow replacement?" -Title 'Replace package'
                    if (-not $answer) { return }
                    $force = $true
                }
                if ($Action -eq 'Publish') {
                    $answer = Confirm-EwWorkbenchM365Action -Window $State.Window `
                        -Message "$($view.PreviewText.Text)`n`nOutput: $output`n`nBuild and publish this confirmed selection?" `
                        -Title 'Confirm Microsoft 365 publishing'
                    if (-not $answer) { return }
                }
                $State.M365Cancellation = [System.Threading.CancellationTokenSource]::new()
                $body = {
                    param($Plan, $Provider, $Action, $Working, $Force, $Token)
                    if ($Action -eq 'Publish') {
                        if ($Provider -eq 'Intune') {
                            return Publish-EwM365IntuneApp -Plan $Plan -WorkingPath $Working -Force:([bool]$Force) -CancellationToken $Token -Confirm:$false
                        }
                        return Publish-EwM365NerdioApp -Plan $Plan -WorkingPath $Working -Force:([bool]$Force) -CancellationToken $Token -Confirm:$false
                    }
                    if ($Token.IsCancellationRequested) { return [PSCustomObject]@{ Succeeded = $false; Error = 'Cancelled before building.'; PackagePath = '' } }
                    New-EwPackage -M365ConfigurationPath $Plan.ConfigurationPath -ConfigurationRoot $Plan.ConfigurationRoot `
                        -WorkingPath $Working -Provider $Provider -Channel $Plan.Channel -CompanyName $Plan.CompanyName `
                        -ImportFor $Plan.ImportFor -TenantId $Plan.TenantId -AppJsonTemplatePath $Plan.AppJsonTemplatePath `
                        -M365Plan $Plan -Force:([bool]$Force) -Confirm:$false
                }
                $arguments = @($plan, $Provider, $Action, $working, $force, $State.M365Cancellation.Token)
            }
            'Recovery' {
                $body = { Get-EwM365IntuneRecovery }
                $arguments = @()
            }
            'Review' {
                $record = $State.IntuneM365RecoveryCombo.SelectedItem
                if ($null -eq $record) { throw 'Select a recovery record first.' }
                $message = "Tenant: $($record.TenantId)`nConfiguration: $($record.ConfigurationId)`nStage: $($record.Stage)`n" +
                    "New app ID: $($record.AppId)`nPrevious app ID: $($record.PreviousAppId)`n`n" +
                    'Inspect the outcome in Intune first. Acknowledge that you reviewed it? This does not retry or remove anything.'
                if (-not (Confirm-EwWorkbenchM365Action -Window $State.Window -Message $message -Title 'Review Intune outcome')) { return }
                $body = { param($Id) Clear-EwM365IntuneRecovery -Id $Id -Reviewed -Confirm:$false; Get-EwM365IntuneRecovery }
                $arguments = @([string]$record.Id)
            }
        }
        $State.M365ActiveProvider = $Provider
        $State.M365ActiveAction = $Action
        Invoke-EwWorkbenchJob -State $State -Kind M365 -Name "Microsoft 365 $Provider $Action" -ScriptBlock $body -ArgumentList $arguments
    }
    catch {
        if ($null -ne $State.M365Cancellation) { $State.M365Cancellation.Dispose(); $State.M365Cancellation = $null }
        $message = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
        $view.ResultText.Text = $message
        Write-EwWorkbenchLog -State $State -Message "Microsoft 365 $Provider $Action failed: $message" -Level Error
        Invoke-EwWorkbenchM365BusyState -State $State
    }
}
