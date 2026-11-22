Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchMaintenanceStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][string]$Message
    )

    $State.AppsDisplayStale = $true
    $State.AppCountLabel.Text = "STALE: $($State.AppCountLabel.Text -replace '^STALE: ', '')"
    $State.ArtifactCountLabel.Text = "STALE: $($State.ArtifactCountLabel.Text -replace '^STALE: ', '')"
    $State.AppsMaintenanceStatusLabel.Text = "$($State.MaintenanceContext.Outcome) Apps STALE: refresh failed: $Message"
    Write-EwWorkbenchLog -State $State -Message $State.AppsMaintenanceStatusLabel.Text -Level Error
}
