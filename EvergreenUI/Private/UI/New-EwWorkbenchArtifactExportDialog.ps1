Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-EwWorkbenchArtifactExportDialog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs a dialog without saving a file.')]
    param()

    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Title = 'Export artifacts to CSV'
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.DefaultExt = '.csv'
    $dialog.AddExtension = $true
    $dialog.OverwritePrompt = $true
    $dialog.FileName = 'export.csv'
    return $dialog
}
