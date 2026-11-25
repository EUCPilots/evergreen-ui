Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchArtifactExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    if ($State.ArtifactsGrid.Items.Count -eq 0) {
        Write-EwWorkbenchLog -State $State -Message 'There are no artifacts to export.' -Level Warning
        return
    }

    # Snapshot before the modal dialog can dispatch a grid refresh.
    $columns = @(
        $State.ArtifactsGrid.Columns |
            Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible } |
            Sort-Object -Property DisplayIndex
    )
    $rows = @(
        foreach ($artifact in $State.ArtifactsGrid.Items) {
            $values = [ordered]@{}
            foreach ($column in $columns) {
                $propertyName = [string]$column.Binding.Path.Path
                $property = $artifact.PSObject.Properties[$propertyName]
                $values[[string]$column.Header] = if ($null -eq $property) { $null } else { $property.Value }
            }
            [PSCustomObject]$values
        }
    )

    $dialog = New-EwWorkbenchArtifactExportDialog
    if (-not $dialog.ShowDialog($State.Window)) {
        Write-Verbose -Message 'EvergreenUI: Artifact export was cancelled'
        return
    }
    $path = [string]$dialog.FileName
    Write-EwWorkbenchLog -State $State -Message "Exporting $($rows.Count) artifacts to $path."
    $rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8BOM -ErrorAction Stop
    Write-EwWorkbenchLog -State $State -Message "Exported $($rows.Count) artifacts to $path."
}
