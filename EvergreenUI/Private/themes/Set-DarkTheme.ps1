#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the dark theme to the EvergreenUI window resource dictionary.

.DESCRIPTION
    Updates all DynamicResource brush entries on the window's resource dictionary
    to the Evergreen-branded dark palette. Must be called on the UI thread.

.PARAMETER Window
    The WPF Window object to retheme.

.PARAMETER ThemeLabelTextBlock
    The TextBlock in the title bar / settings view that displays the current
    theme name. Its text is updated to 'Dark theme'.

.EXAMPLE
    Set-DarkTheme -Window $window -ThemeLabelTextBlock $themeLabelTextBlock
#>
function Set-DarkTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$ThemeLabelTextBlock
    )

    function NewBrush([byte]$r, [byte]$g, [byte]$b) {
        [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($r, $g, $b)
        )
    }

    $res = $Window.Resources

    # Evergreen brand dark palette — deep forest teal base
    $res['WindowBackgroundBrush']    = NewBrush  20  29  28   # #141D1C
    $res['TextPrimaryBrush']         = NewBrush 232 242 240   # #E8F2F0
    $res['TextSecondaryBrush']       = NewBrush 144 170 167   # #90AAA7
    $res['AccentBrush']              = NewBrush  77 184 173   # #4DB8AD
    $res['AccentHoverBrush']         = NewBrush 103 185 201   # #67B9C9
    $res['AccentLightBrush']         = NewBrush  13  41  38   # #0D2926
    $res['ControlBackgroundBrush']   = NewBrush  28  40  38   # #1C2826
    $res['ControlBorderBrush']       = NewBrush  46  63  60   # #2E3F3C
    $res['ButtonForegroundBrush']    = NewBrush   0   0   0   # #000000
    $res['ToggleThumbBrush']         = NewBrush   0   0   0   # #000000

    $Window.Background = $res['WindowBackgroundBrush']
    $ThemeLabelTextBlock.Text = 'Dark theme'
}
