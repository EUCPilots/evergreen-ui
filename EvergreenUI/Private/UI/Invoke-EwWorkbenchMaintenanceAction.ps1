Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchMaintenanceAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Update', 'Clear', 'Open', 'Catalog', 'Artifacts', 'ReloadVersions')][string]$Action
    )

    if ($State.MaintenancePromptActive) { return }
    if ($Action -ne 'Open' -and $null -ne $State.ActiveJobId) {
        Write-EwWorkbenchLog -State $State -Message 'Wait for the current operation to finish.' -Level Warning
        return
    }
    try {
        if ($Action -eq 'Open') {
            $path = [string](& $State.ModuleInvoker -Name 'Get-EwCachePath' -Parameters @{})
            if ([string]::IsNullOrWhiteSpace($path)) { throw 'No Workbench cache folder was returned.' }
            Write-EwWorkbenchLog -State $State -Message "Creating and opening Workbench cache folder: $path"
            $null = [System.IO.Directory]::CreateDirectory($path)
            Start-Process -FilePath $path -ErrorAction Stop
            $State.AppsMaintenanceStatusLabel.Text = 'Cache folder opened.'
            return
        }
        if ($Action -eq 'Clear') {
            $State.MaintenancePromptActive = $true
            try {
                $confirmed = Confirm-EwWorkbenchCacheClear -Window $State.Window
            }
            finally { $State.MaintenancePromptActive = $false }
            if (-not $confirmed) { return }
            if ($null -ne $State.ActiveJobId) { return }
        }
        if ($Action -in @('Update', 'Clear')) {
            $filters = @{}
            foreach ($name in $State.ArtifactFilterControls.Keys) {
                $selectedValues = @($State.ArtifactFilterControls[$name].CheckBoxes |
                    Where-Object { [bool]$_.IsChecked } | ForEach-Object { [string]$_.Tag })
                if ($selectedValues.Count -gt 0) { $filters[$name] = $selectedValues }
            }
            $State.MaintenanceContext = @{
                AppName = if ($null -ne $State.CurrentApp) { [string]$State.CurrentApp.Name } else { '' }
                Filters = $filters
                Catalog = @()
                Outcome = ''
            }
        }
        switch ($Action) {
            'Update' {
                $State.AppsMaintenanceStatusLabel.Text = 'Updating Evergreen application data...'
                Invoke-EwWorkbenchJob -State $State -Kind 'EvergreenUpdate' -Name 'Update Evergreen application data' -ScriptBlock {
                    Update-EwEvergreen -Confirm:$false -InformationAction Continue -ErrorAction Stop
                }
            }
            'Clear' {
                $State.AppsMaintenanceStatusLabel.Text = 'Clearing Workbench caches...'
                Invoke-EwWorkbenchJob -State $State -Kind 'CacheClear' -Name 'Clear Workbench caches' -ScriptBlock {
                    Clear-EwCache -Confirm:$false -InformationAction Continue -ErrorAction Stop
                }
            }
            'Catalog' {
                $State.AppsMaintenanceStatusLabel.Text = "$($State.MaintenanceContext.Outcome) Refreshing Apps..."
                Invoke-EwWorkbenchJob -State $State -Kind 'MaintenanceCatalog' -Name 'Reload catalog after maintenance' -ScriptBlock {
                    Get-EwApp -Force -ErrorAction Stop
                }
            }
            'ReloadVersions' {
                if ($null -eq $State.CurrentApp) {
                    $State.AppsMaintenanceStatusLabel.Text = 'Select an application to reload its versions.'
                    return
                }
                $appName = [string]$State.CurrentApp.Name
                $State.SelectedAppText.Text = "Loading versions for $($State.CurrentApp.FriendlyName)..."
                Invoke-EwWorkbenchJob -State $State -Kind 'Artifacts' -Name "Reload $appName artifacts" -ScriptBlock {
                    param($AppName)
                    Get-EwApp -Name $AppName -Force -ErrorAction Stop
                } -ArgumentList @($appName)
            }
            'Artifacts' {
                Invoke-EwWorkbenchJob -State $State -Kind 'MaintenanceArtifacts' -Name 'Reload selected application Artifacts' -ScriptBlock {
                    param($AppName)
                    Get-EwApp -Name $AppName -ErrorAction Stop
                } -ArgumentList @($State.MaintenanceContext.AppName)
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($Action -in @('Catalog', 'Artifacts')) {
            Invoke-EwWorkbenchMaintenanceStale -State $State -Message $message
            return
        }
        else { $State.AppsMaintenanceStatusLabel.Text = "$Action failed: $message" }
        Write-EwWorkbenchLog -State $State -Message $State.AppsMaintenanceStatusLabel.Text -Level Error
    }
}
