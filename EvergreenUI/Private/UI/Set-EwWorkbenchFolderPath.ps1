Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwWorkbenchFolderPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )

    $settingName = switch ($Kind) {
        'Download' { 'OutputPath' }
        'Library' { 'LibraryPath' }
        'PackageDefinitions' { 'IntuneDefinitionsPath' }
        'M365Configurations' { 'M365DefinitionsPath' }
        'NerdioDefinitions' { 'NerdioDefinitionsPath' }
    }
    if ($Kind -notin @('Download', 'Library') -and $null -ne $State.ActiveJobId) {
        throw 'Wait for the current operation to finish before changing this folder.'
    }
    if (-not $PSCmdlet.ShouldProcess($settingName, "Set $Kind folder")) {
        return
    }
    $previousPath = [string]$State.Settings[$settingName]
    Set-EwSetting -Name $settingName -Value $Path -Confirm:$false -ErrorAction Stop
    $State.Settings[$settingName] = $Path
    $State["Settings${Kind}PathBox"].Text = $Path
    switch ($Kind) {
        'Download' {
            $State.DownloadDestinationText.Text = $Path
            $State.DownloadDestinationText.ToolTip = $Path
            if ([string]::IsNullOrWhiteSpace([string]$State.Settings.PackageOutputPath)) {
                $State.PackageOutputPathBox.Text = $Path
            }
        }
        'Library' {
            $State.Settings.LibraryPathHistory = @((Get-EwSetting -ErrorAction Stop).LibraryPathHistory)
            Update-EwWorkbenchLibraryPathHistory -State $State -Path $Path -Confirm:$false
        }
        'PackageDefinitions' {
            $changed = $previousPath -cne $Path -or [string]$State.IntuneDefinitionsPathBox.Text -cne $Path
            if ($changed) {
                if ([string]$State.IntuneDefinitionsPathBox.Text -ceq $Path) {
                    Invoke-EwWorkbenchInstallStale -State $State
                }
                else {
                    $State.IntuneDefinitionsPathBox.Text = $Path
                }
                $State.PackageDefinitions.Clear()
                $State.PackageDefinitionsCountLabel.Text = 'Definitions need refresh'
                $State.UpdatePackageDefinitionsButton.IsEnabled = $false
                $State.IntuneComparison = @()
                $State.IntuneComparisonRoot = ''
                $State.IntuneComparisonLoaded = $false
                $State.IntuneComparisonListView.ItemsSource = @()
                $State.IntuneOnlyAppsListView.ItemsSource = @()
                $State.PublishSelectedIntuneButton.IsEnabled = $false
                $State.PublishIntuneUpdateButton.IsEnabled = $false
                Update-EwWorkbenchIntuneView -State $State
            }
        }
        'M365Configurations' {
            foreach ($provider in 'Intune', 'Nerdio') {
                $view = $State.M365Views[$provider]
                if ($previousPath -cne $Path -or [string]$view.PathBox.Text -cne $Path) {
                    $view.PathBox.Text = $Path
                    $view.ConfigurationCombo.ItemsSource = @()
                    $view.TargetCombo.ItemsSource = @()
                    Clear-EwWorkbenchM365Preview -State $State -Provider $provider
                }
            }
        }
        'NerdioDefinitions' {
            if ($previousPath -cne $Path -or [string]$State.NerdioDefinitionsPathBox.Text -cne $Path) {
                if ([string]$State.NerdioDefinitionsPathBox.Text -ceq $Path) {
                    Clear-EwWorkbenchNerdioComparison -State $State -ConnectionChanged $false
                }
                else {
                    $State.NerdioDefinitionsPathBox.Text = $Path
                }
            }
        }
    }
    Invoke-EwWorkbenchFolderCheck -State $State -Kind $Kind
    $label = [regex]::Replace($Kind, '(?<=[a-z0-9])(?=[A-Z])', ' ')
    Write-EwWorkbenchLog -State $State -Message "$label folder saved."
}
