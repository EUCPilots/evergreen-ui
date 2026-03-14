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

        [Parameter()]
        [AllowNull()]
        [System.Windows.Controls.TextBlock]$ThemeLabelTextBlock
    )

    function NewBrush([byte]$r, [byte]$g, [byte]$b) {
        [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($r, $g, $b)
        )
    }

    $res = $Window.Resources

    # Evergreen brand dark palette - deep forest teal base
    $res['WindowBackgroundBrush'] = NewBrush  20  29  28   # #141D1C
    $res['TextPrimaryBrush'] = NewBrush 232 242 240   # #E8F2F0
    $res['TextSecondaryBrush'] = NewBrush 144 170 167   # #90AAA7
    $res['AccentBrush'] = NewBrush  77 184 173   # #4DB8AD
    $res['AccentHoverBrush'] = NewBrush 103 185 201   # #67B9C9
    $res['AccentLightBrush'] = NewBrush  13  41  38   # #0D2926
    $res['ControlBackgroundBrush'] = NewBrush  28  40  38   # #1C2826
    $res['ControlBorderBrush'] = NewBrush  46  63  60   # #2E3F3C
    $res['ButtonForegroundBrush'] = NewBrush   0   0   0   # #000000
    $res['ToggleThumbBrush'] = NewBrush   0   0   0   # #000000
    $res['SecondaryButtonBackgroundBrush'] = NewBrush  45  68  64   # #2D4440 - visible above window bg
    $res['SecondaryButtonBorderBrush']     = NewBrush  90 123 119   # #5A7B77 - visible mid-tone border

    $Window.Background = $res['WindowBackgroundBrush']
    if ($null -ne $ThemeLabelTextBlock) {
        $ThemeLabelTextBlock.Text = 'Dark theme'
    }

    # Colour the native OS title bar to match AccentBrush #4DB8AD (R=77 G=184 B=173)
    # COLORREF byte order is 0x00BBGGRR → 0x00ADB84D
    Set-DwmTitleBarColor -Window $Window -CaptionColorRef 0x00ADB84D -UseDarkMode $true
}
