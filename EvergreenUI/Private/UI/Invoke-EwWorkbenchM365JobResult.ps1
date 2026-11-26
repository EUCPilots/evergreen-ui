Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchM365JobResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State, [Parameter(Mandatory)][object]$Job)

    $provider = $State.M365ActiveProvider
    $action = $State.M365ActiveAction
    $view = $State.M365Views[$provider]
    $output = @($Job.Output)
    if ($Job.State -ne 'Completed' -or $null -ne $Job.TerminatingError) {
        $view.ResultText.Text = 'Operation did not finish. Check the log and review any provider recovery record.'
        if ($provider -eq 'Nerdio') {
            Sync-EwWorkbenchNerdioRecoveryState -State $State | Out-Null
            $view.ResultText.Text += ' Open Nerdio recovery below to review or acknowledge an unresolved outcome.'
        }
    }
    else {
        switch ($action) {
            'Load' {
                $view.ConfigurationCombo.ItemsSource = [object[]]$output
                $view.TargetCombo.ItemsSource = @()
                Clear-EwWorkbenchM365Preview -State $State -Provider $provider
                $view.ResultText.Text = "Loaded $($output.Count) configurations."
            }
            'Targets' {
                $view.TargetCombo.ItemsSource = [object[]]$output
                $view.TargetCombo.SelectedIndex = -1
                Clear-EwWorkbenchM365Preview -State $State -Provider $provider
                $view.ResultText.Text = "Loaded $($output.Count) provider targets."
            }
            { $_ -in @('PreviewBuild', 'PreviewPublish') } {
                $result = $output | Select-Object -Last 1
                if ($null -eq $result) { throw 'Microsoft 365 preview returned no result.' }
                $view.BuildPlan = $result.Build
                $view.PublishPlan = $result.Publish
                $build = $result.Build
                $text = "Configuration: $($build.ConfigurationPath)`nID: $($build.ConfigurationId)`n" +
                    "Tenant: $($build.TenantId)`nChannel: $($build.Channel), Office version: $($build.OfficeVersion)`n" +
                    "Deployment tool version: $($build.ToolVersion)`nCompany: $($build.CompanyName), session: $($build.ImportFor)`n" +
                    'Office uses a rolling channel; installation may be newer than the preview. ' +
                    'The legacy TenantId and company XML settings are not documented by Microsoft as tenant association or company configuration.'
                if ($null -ne $result.Publish) {
                    if ($provider -eq 'Intune') {
                        $matchedApps = @($result.Publish.Matches | ForEach-Object { "$($_.Name) [$($_.Id)] $($_.Version)" })
                        $text += "`nExisting configuration-ID matches: $(if ($matchedApps.Count) { $matchedApps -join '; ' } else { 'none' })"
                        $text += "`nSupersedence target: $(if ($result.Publish.PreviousAppId) { $result.Publish.PreviousAppId } else { 'none' }) (update, not uninstall)."
                    }
                    else {
                        $text += "`nNerdio: $($result.Publish.Destination.NmeHost) / $($result.Publish.Destination.StorageAccountName) / $($result.Publish.Destination.ContainerName)"
                        $text += "`nOperation: $($result.Publish.Operation); name: $($result.Publish.Name); target ID: $($result.Publish.ShellAppId)"
                        if ($result.Publish.SameVersionAttested) {
                            $text += "`nSame-version configuration change attested; Nerdio may reject the version."
                        }
                    }
                    $text += "`nProvider checks are not atomic locks."
                }
                $view.PreviewText.Text = $text
                $view.ResultText.Text = 'Preview ready.'
            }
            { $_ -in @('Build', 'Publish') } {
                $result = $output | Select-Object -Last 1
                if ($null -eq $result) { throw 'Microsoft 365 operation returned no result. Check provider recovery state.' }
                $message = if ($action -eq 'Build') {
                    if ($result.Succeeded) { "Built: $($result.PackagePath)" } else { "Build failed: $($result.Error)" }
                }
                elseif ($provider -eq 'Intune') {
                    "Result: $($result.Status); app: $($result.IntuneAppId); previous app: $($result.PreviousAppId); supersedence: $($result.SupersedenceStatus); recovery: $($result.RecoveryId). $($result.Error)"
                }
                else {
                    "Result: $($result.Status); app: $($result.AppId); job: $($result.JobId); blob: $($result.BlobName). $($result.Error)"
                }
                $view.ResultText.Text = $message -replace 'https?://\S+', '[URL omitted]'
                Write-EwWorkbenchLog -State $State -Message $view.ResultText.Text -Level $(if ($result.Succeeded) { 'Info' } else { 'Warning' })
                Clear-EwWorkbenchM365Preview -State $State -Provider $provider
                if ($provider -eq 'Nerdio') { Sync-EwWorkbenchNerdioRecoveryState -State $State | Out-Null }
            }
            { $_ -in @('Recovery', 'Review') } {
                $State.IntuneM365RecoveryCombo.ItemsSource = [object[]]$output
                $view.ResultText.Text = "$($output.Count) Intune recovery records."
            }
        }
    }
    if ($null -ne $State.M365Cancellation) {
        $State.M365Cancellation.Dispose()
        $State.M365Cancellation = $null
    }
    $State.M365ActiveProvider = ''
    $State.M365ActiveAction = ''
}
