Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchLibraryActionState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$State)

    $application = $State.LibraryListView.SelectedItem
    $canRemove = $null -eq $State.ActiveJobId -and -not $State.LibraryPromptActive -and $State.LibraryListView.IsEnabled -and
        -not [string]::IsNullOrWhiteSpace($State.LoadedLibraryPath) -and
        $State.LoadedLibraryPath -eq [string]$State.LibraryPathBox.Text -and
        $null -ne $application -and $null -ne $application.PSObject.Properties['ManifestHash'] -and
        -not [string]::IsNullOrWhiteSpace([string]$application.ManifestHash) -and
        $null -ne $application.PSObject.Properties['LibraryHash'] -and
        -not [string]::IsNullOrWhiteSpace([string]$application.LibraryHash)
    $State.RemoveLibraryAppButton.IsEnabled = $canRemove
    $State.RemoveLibraryVersionsButton.IsEnabled = $canRemove -and $State.LibraryVersionsListView.SelectedItems.Count -gt 0
}
