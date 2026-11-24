Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-EwWorkbenchLibraryRemovalDialog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs a confirmation dialog without removing files.')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Owner,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][psobject[]]$Row,
        [Parameter(Mandatory)][bool]$EntireApplication
    )

    $moduleRoot = Split-Path -Path $script:ewModulePath -Parent
    $xamlPath = Join-Path -Path $moduleRoot -ChildPath 'Resources\LibraryRemovalDialog.xaml'
    Write-Verbose -Message "EvergreenUI: Loading library confirmation dialog from $xamlPath"
    $reader = [System.Xml.XmlReader]::Create($xamlPath)
    try {
        $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if ($dialog -isnot [System.Windows.Window]) {
        throw "Library confirmation XAML did not create a WPF Window: $xamlPath"
    }
    $dialog.Owner = $Owner
    $dialog.ThemeMode = $Owner.ThemeMode
    $dialog.FontFamily = $Owner.FontFamily
    $dialog.FontSize = [Math]::Max(14, $Owner.FontSize)
    if ($Owner.ActualHeight -gt 0) {
        $dialog.MaxHeight = [Math]::Max($dialog.MinHeight, [Math]::Min(640, $Owner.ActualHeight - 64))
    }

    $dialog.FindName('LibraryRemovalHeadingText').Text = if ($EntireApplication) {
        'Remove application from the library?'
    }
    else {
        'Remove selected versions from the library?'
    }
    $dialog.FindName('LibraryRemovalApplicationText').Text = "Application: $Name"
    $dialog.FindName('LibraryRemovalPathText').Text = "Library: $Path"
    $dialog.FindName('LibraryRemovalArtifactsHeadingText').Text = if ($Row.Count -eq 0) {
        'No recorded artifacts'
    }
    else {
        "Artifacts to remove: $($Row.Count)"
    }
    $dialog.FindName('LibraryRemovalArtifactsList').ItemsSource = [object[]]@(
        foreach ($artifact in $Row) {
            [PSCustomObject]@{
                Summary = "$($artifact.Version) | $($artifact.Architecture) | $($artifact.Type)"
                URI = [string]$artifact.URI
            }
        }
    )
    $confirmButton = $dialog.FindName('ConfirmLibraryRemovalButton')
    $confirmButton.Content = if ($EntireApplication) { 'Remove application' } else { 'Remove versions' }
    $confirmButton.Add_Click({
        $dialog.DialogResult = $true
    }.GetNewClosure())
    $cancelButton = $dialog.FindName('CancelLibraryRemovalButton')
    $dialog.Add_ContentRendered({
        $null = $cancelButton.Focus()
    }.GetNewClosure())
    Initialize-EwWorkbenchWindowAppearance -Window $dialog
    return $dialog
}
