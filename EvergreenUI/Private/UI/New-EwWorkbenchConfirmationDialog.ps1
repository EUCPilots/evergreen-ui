Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-EwWorkbenchConfirmationDialog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs a confirmation dialog without changing state.')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Owner,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][bool]$DefaultYes
    )

    $moduleRoot = Split-Path -Path $script:ewModulePath -Parent
    $xamlPath = Join-Path -Path $moduleRoot -ChildPath 'Resources\ConfirmationDialog.xaml'
    Write-Verbose -Message "EvergreenUI: Loading confirmation dialog from $xamlPath"
    $reader = [System.Xml.XmlReader]::Create($xamlPath)
    try {
        $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if ($dialog -isnot [System.Windows.Window]) {
        throw "Confirmation XAML did not create a WPF Window: $xamlPath"
    }
    $dialog.Owner = $Owner
    $dialog.Title = $Title
    $dialog.ThemeMode = $Owner.ThemeMode
    $dialog.FontFamily = $Owner.FontFamily
    $dialog.FontSize = [Math]::Max(14, $Owner.FontSize)
    if ($Owner.ActualHeight -gt 0) {
        $dialog.MaxHeight = [Math]::Max($dialog.MinHeight, [Math]::Min(640, $Owner.ActualHeight - 64))
    }
    if ($Owner.ActualWidth -gt 0) {
        $dialog.MaxWidth = [Math]::Max($dialog.MinWidth, [Math]::Min(680, $Owner.ActualWidth - 64))
    }

    $dialog.FindName('ConfirmationHeadingText').Text = $Title
    $dialog.FindName('ConfirmationMessageText').Text = $Message
    $yesButton = $dialog.FindName('ConfirmationYesButton')
    $noButton = $dialog.FindName('ConfirmationNoButton')
    $yesButton.IsDefault = $DefaultYes
    $noButton.IsDefault = -not $DefaultYes
    $defaultButton = if ($DefaultYes) { $yesButton } else { $noButton }
    $defaultButton.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'AccentButtonStyle')
    $yesButton.Add_Click({
        $dialog.DialogResult = $true
    }.GetNewClosure())
    $dialog.Add_ContentRendered({
        $null = $defaultButton.Focus()
    }.GetNewClosure())
    Initialize-EwWorkbenchWindowAppearance -Window $dialog
    return $dialog
}
