#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the light theme to the EvergreenUI window resource dictionary.

.DESCRIPTION
    Updates all DynamicResource brush entries on the window's resource dictionary
    to the Evergreen-branded light palette. Must be called on the UI thread.

.PARAMETER Window
    The WPF Window object to retheme.

.PARAMETER ThemeLabelTextBlock
    The TextBlock in the title bar / settings view that displays the current
    theme name. Its text is updated to 'Light theme'.

.EXAMPLE
    Set-LightTheme -Window $window -ThemeLabelTextBlock $themeLabelTextBlock
#>
function Set-LightTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$ThemeLabelTextBlock
    )

    # Helper: create a SolidColorBrush from R,G,B components
    function NewBrush([byte]$r, [byte]$g, [byte]$b) {
        [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($r, $g, $b)
        )
    }

    $res = $Window.Resources

    # Evergreen brand light palette - primary: #009485, dark: #01786c, light: #67b9c9
    $res['WindowBackgroundBrush'] = NewBrush 243 244 244   # #F3F4F4
    $res['TextPrimaryBrush'] = NewBrush  26  26  26   # #1A1A1A
    $res['TextSecondaryBrush'] = NewBrush  77  90  88   # #4D5A58
    $res['AccentBrush'] = NewBrush   0 148 133   # #009485
    $res['AccentHoverBrush'] = NewBrush   1 120 108   # #01786c
    $res['AccentLightBrush'] = NewBrush 217 242 239   # #D9F2EF
    $res['ControlBackgroundBrush'] = NewBrush 255 255 255   # #FFFFFF
    $res['ControlBorderBrush'] = NewBrush 221 226 225   # #DDE2E1
    $res['ButtonForegroundBrush'] = NewBrush 255 255 255   # #FFFFFF
    $res['ToggleThumbBrush'] = NewBrush 255 255 255   # #FFFFFF
    $res['SecondaryButtonBackgroundBrush'] = NewBrush 228 232 231   # #E4E8E7 - clearly above window bg
    $res['SecondaryButtonBorderBrush']     = NewBrush 154 173 170   # #9AADAA - visible mid-tone border

    $Window.Background = $res['WindowBackgroundBrush']
    $ThemeLabelTextBlock.Text = 'Light theme'
}
