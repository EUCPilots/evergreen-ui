Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchMaintenanceJobResult {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][psobject]$Job
    )

    $failed = $Job.State -ne 'Completed' -or $null -ne $Job.TerminatingError
    $errorMessage = if ($null -ne $Job.TerminatingError) {
        $Job.TerminatingError.Exception.Message
    } else { "Job finished with state '$($Job.State)'." }
    if ($Kind -in @('EvergreenUpdate', 'CacheClear')) {
        $result = @($Job.Output) | Where-Object {
            $null -ne $_ -and $null -ne $_.PSObject.Properties['Succeeded'] -and
            $null -ne $_.PSObject.Properties['Error']
        } | Select-Object -Last 1
        $succeeded = -not $failed -and $null -ne $result -and $result.Succeeded
        $changed = $Kind -eq 'CacheClear' -and $null -ne $result -and
            $null -ne $result.PSObject.Properties['Changed'] -and $result.Changed
        $name = if ($Kind -eq 'CacheClear') { 'Workbench cache clearing' } else { 'Evergreen application data update' }
        if ($succeeded) {
            $State.MaintenanceContext.Outcome = "$name succeeded."
            Write-EwWorkbenchLog -State $State -Message $State.MaintenanceContext.Outcome
        }
        else {
            if (-not $failed) {
                $errorMessage = if ($null -ne $result) { [string]$result.Error } else { 'No structured maintenance result returned.' }
            }
            $State.MaintenanceContext.Outcome = "$name $(if ($changed) { 'partially completed' } else { 'failed' }): $errorMessage"
            Write-EwWorkbenchLog -State $State -Message $State.MaintenanceContext.Outcome -Level Error
        }
        $State.AppsMaintenanceStatusLabel.Text = $State.MaintenanceContext.Outcome
        if ($Kind -eq 'CacheClear' -and $null -ne $result -and $null -ne $result.PSObject.Properties['RemovedEntryCount']) {
            $entryCount = if ($null -ne $result.PSObject.Properties['EntryCountKnown'] -and -not $result.EntryCountKnown) {
                'Entry count unavailable'
            } else { "$($result.RemovedEntryCount) entries removed" }
            Write-EwWorkbenchLog -State $State -Message "Workbench cache: $entryCount from $($result.CachePath). Catalog invalidated: $($result.CatalogInvalidated); definition cache invalidated: $($result.DefinitionCacheInvalidated)."
        }
        if ($succeeded -or $changed) { return 'Catalog' }
        return ''
    }
    if ($failed) {
        Invoke-EwWorkbenchMaintenanceStale -State $State -Message $errorMessage
        return ''
    }
    if ($Kind -eq 'MaintenanceCatalog') {
        $State.MaintenanceContext.Catalog = @($Job.Output)
        $app = $State.MaintenanceContext.Catalog | Where-Object Name -eq $State.MaintenanceContext.AppName |
            Select-Object -First 1
        if ($null -ne $app) { return 'Artifacts' }
        $State.AppCatalog = @($State.MaintenanceContext.Catalog)
        Invoke-EwWorkbenchAppList -State $State -PreserveCurrentApp
        if (-not [string]::IsNullOrWhiteSpace($State.MaintenanceContext.AppName)) {
            $message = "Application '$($State.MaintenanceContext.AppName)' is no longer in the catalog; its details were cleared. Queued downloads are unchanged."
            $State.SelectedAppText.Text = $message
            Write-EwWorkbenchLog -State $State -Message $message -Level Warning
        }
    }
    else {
        try {
            $metadata = @()
            if (@($Job.Output).Count -gt 0) {
                $metadata = @(Get-EwFilterableProperty -Artifact @($Job.Output) -ErrorAction Stop)
            }
        }
        catch {
            Invoke-EwWorkbenchMaintenanceStale -State $State -Message $_.Exception.Message
            return ''
        }
        $State.AppCatalog = @($State.MaintenanceContext.Catalog)
        Invoke-EwWorkbenchAppList -State $State -PreserveCurrentApp
        $State.AllArtifacts = @($Job.Output)
        $State.SelectedAppText.Text = "$($State.CurrentApp.FriendlyName) ($($State.CurrentApp.Name))"
        Invoke-EwWorkbenchArtifactList -State $State -RebuildFilters -PreservedFilters $State.MaintenanceContext.Filters -FilterMetadata @($metadata)
        Write-EwWorkbenchLog -State $State -Message "Reloaded $($State.AllArtifacts.Count) Artifacts for $($State.CurrentApp.Name). Queued downloads are unchanged."
    }
    $State.AppsDisplayStale = $false
    $State.AppCountLabel.Text = $State.AppCountLabel.Text -replace '^STALE: ', ''
    $State.ArtifactCountLabel.Text = $State.ArtifactCountLabel.Text -replace '^STALE: ', ''
    $State.AppsMaintenanceStatusLabel.Text = "$($State.MaintenanceContext.Outcome) Apps refreshed."
    return ''
}
