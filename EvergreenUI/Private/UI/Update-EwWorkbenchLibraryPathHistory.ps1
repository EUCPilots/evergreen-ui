Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-EwWorkbenchLibraryPathHistory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter()][AllowEmptyString()][string]$Path = [string]$State.LibraryPathBox.Text
    )

    if (-not $PSCmdlet.ShouldProcess('LibraryPathBox', 'Refresh library path history')) {
        return
    }
    $history = @(
        if ($State.Settings.Contains('LibraryPathHistory')) {
            $State.Settings.LibraryPathHistory | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }
        }
    )
    # Replacing ItemsSource can clear an editable ComboBox's text, so restore it afterwards.
    $State.LibraryPathBox.ItemsSource = [string[]]$history
    $State.LibraryPathBox.Text = $Path
    Write-Verbose -Message "EvergreenUI: Library path history shows $($history.Count) entries"
}
