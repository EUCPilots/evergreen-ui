Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchLibraryJobResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$State,
        [Parameter(Mandatory)][psobject]$Job
    )

    $envelope = @($Job.Output) | Select-Object -Last 1
    if ($Job.State -ne 'Completed' -or $null -ne $Job.TerminatingError -or $null -eq $envelope) {
        $State.LoadedLibraryPath = ''
        Write-EwWorkbenchLog -State $State -Message 'Library removal outcome is unavailable. No automatic retry; reload inventory and review the files before another removal.' -Level Error
        return
    }
    $result = $envelope.Result
    $message = "Library removal for $($State.LibraryRemovalContext.Name): $($result.RemovedCount) artifact entries and $(@($result.RemovedFiles).Count) files removed."
    if (-not $result.Succeeded) {
        $message += " Stopped: $($result.Error) Failed file: $($result.FailedFile). Unattempted files: $(@($result.UnattemptedFiles).Count)."
    }
    $level = if ($result.Succeeded) { 'Info' } else { 'Error' }
    Write-EwWorkbenchLog -State $State -Message $message -Level $level
    if ($null -ne $result.PSObject.Properties['Items']) {
        foreach ($item in @($result.Items)) {
            Write-EwWorkbenchLog -State $State -Message "Artifact row $($item.Index), version $($item.Version): $($item.Status)" -Level $level
        }
    }
    foreach ($file in @($result.RemovedFiles)) { Write-EwWorkbenchLog -State $State -Message "Removed: $file" }
    foreach ($file in @($result.UnattemptedFiles)) { Write-EwWorkbenchLog -State $State -Message "Not attempted: $file" -Level Warning }
    if ($envelope.RefreshError) {
        $State.LoadedLibraryPath = ''
        Write-EwWorkbenchLog -State $State -Message "Removal is not rolled back. Inventory refresh failed: $($envelope.RefreshError)" -Level Error
    }
    else {
        Invoke-EwWorkbenchLibraryInventory -State $State -Item @($envelope.Items) -Path $State.LibraryRemovalContext.Path -SelectedName $State.LibraryRemovalContext.Name
    }
    $State.LibraryRemovalContext = $null
}
