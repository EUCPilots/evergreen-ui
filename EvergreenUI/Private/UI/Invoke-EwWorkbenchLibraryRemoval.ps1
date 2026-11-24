Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchLibraryRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$State,
        [Parameter(Mandatory)][bool]$EntireApplication
    )

    Invoke-EwWorkbenchLibraryActionState -State $State
    $enabled = if ($EntireApplication) { $State.RemoveLibraryAppButton.IsEnabled } else { $State.RemoveLibraryVersionsButton.IsEnabled }
    if (-not $enabled) { return }
    $application = $State.LibraryListView.SelectedItem
    [object[]]$rows = if ($EntireApplication) { @($State.LibraryVersionsListView.ItemsSource) } else { @($State.LibraryVersionsListView.SelectedItems) }
    $plan = @{
        Path = $State.LoadedLibraryPath; Name = [string]$application.Name
        ExpectedManifestHash = [string]$application.ManifestHash; ExpectedLibraryHash = [string]$application.LibraryHash
    }
    if (-not $EntireApplication) { $plan.Index = [int[]]@($rows | ForEach-Object { $_.Index }) }
    try {
        $State.LibraryPromptActive = $true
        $confirmed = Confirm-EwWorkbenchLibraryRemoval -Window $State.Window -Path $plan.Path -Name $plan.Name -Row $rows -EntireApplication $EntireApplication
    }
    finally {
        $State.LibraryPromptActive = $false
        Invoke-EwWorkbenchLibraryActionState -State $State
    }
    if (-not $confirmed) {
        Write-EwWorkbenchLog -State $State -Message 'Library removal cancelled; no files changed.'
        return
    }
    if ($null -ne $State.ActiveJobId -or $State.LibraryListView.SelectedItem -ne $application -or
        [string]$State.LibraryPathBox.Text -ne $plan.Path -or
        (-not $EntireApplication -and
            (@($State.LibraryVersionsListView.SelectedItems | ForEach-Object { $_.Index } | Sort-Object) -join ',') -ne
            (@($plan.Index | Sort-Object) -join ','))) {
        Write-EwWorkbenchLog -State $State -Message 'Library selection changed. Select again and confirm a new removal.' -Level Warning
        return
    }
    try {
        $State.LibraryRemovalContext = $plan
        $State.LoadedLibraryPath = ''
        Invoke-EwWorkbenchJob -State $State -Kind LibraryRemoval -Name 'Remove library items' -ScriptBlock {
            param($Plan)
            $result = $null
            $items = @()
            $refreshError = ''
            try { $result = Remove-EwLibraryApp @Plan -Confirm:$false -ErrorAction Stop }
            catch {
                $result = [PSCustomObject]@{
                    Succeeded = $false; Error = $_.Exception.Message; RemovedCount = 0
                    RemovedFiles = @(); FailedFile = ''; UnattemptedFiles = @()
                    ManifestUpdated = $false; ApplicationRemoved = $false
                }
            }
            try { $items = @(Get-EwLibrary -Path $Plan.Path -ErrorAction Stop) }
            catch { $refreshError = $_.Exception.Message }
            [PSCustomObject]@{ Result = $result; Items = $items; RefreshError = $refreshError }
        } -ArgumentList @($plan)
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not start library removal: $($_.Exception.Message)" -Level Error
        Invoke-EwWorkbenchLibraryActionState -State $State
    }
}
