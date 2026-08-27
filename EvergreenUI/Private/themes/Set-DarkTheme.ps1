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

    # Helper: create a semi-transparent SolidColorBrush from A,R,G,B components
    function NewAlphaBrush([byte]$a, [byte]$r, [byte]$g, [byte]$b) {
        [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromArgb($a, $r, $g, $b)
        )
    }

    $setDwmTitleBarColor = {
        param(
            [System.Windows.Window]$ThemeWindow,
            [int]$CaptionColorRef,
            [bool]$UseDarkMode
        )

        if (-not ('EvergreenUI.DwmHelper' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EvergreenUI {
    public static class DwmHelper {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(
            IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        public const int DWMWA_CAPTION_COLOR           = 35;
    }
}
'@
        }

        try {
            $hwnd = [System.Windows.Interop.WindowInteropHelper]::new($ThemeWindow).Handle
            if ($hwnd -eq [System.IntPtr]::Zero) { return }

            $darkInt = [int]$UseDarkMode
            [EvergreenUI.DwmHelper]::DwmSetWindowAttribute(
                $hwnd,
                [EvergreenUI.DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE,
                [ref]$darkInt,
                4
            ) | Out-Null

            [EvergreenUI.DwmHelper]::DwmSetWindowAttribute(
                $hwnd,
                [EvergreenUI.DwmHelper]::DWMWA_CAPTION_COLOR,
                [ref]$CaptionColorRef,
                4
            ) | Out-Null
        }
        catch {
            Write-Verbose -Message "EvergreenUI: DWM title bar colouring failed: $($_.Exception.Message)"
        }
    }

    $res = $Window.Resources

    # Windows 11 dark background standard (#202020)
    $res['WindowBackgroundBrush'] = NewBrush  32  32  32   # #202020
    $res['TextPrimaryBrush'] = NewBrush 232 242 240   # #E8F2F0
    $res['TextSecondaryBrush'] = NewBrush 144 170 167   # #90AAA7
    $res['AccentBrush'] = NewBrush  77 184 173   # #4DB8AD
    $res['AccentHoverBrush'] = NewBrush 103 185 201   # #67B9C9
    $res['AccentLightBrush'] = NewBrush  13  41  38   # #0D2926
    $res['ControlBackgroundBrush'] = NewBrush  43  43  43   # #2B2B2B
    $res['ControlBorderBrush'] = NewBrush  62  62  62   # #3E3E3E
    $res['ButtonForegroundBrush'] = NewBrush   0   0   0   # #000000
    $res['ToggleThumbBrush'] = NewBrush   0   0   0   # #000000
    $res['SecondaryButtonBackgroundBrush'] = NewBrush  51  51  51   # #333333 - Fluent dark neutral secondary surface
    $res['SecondaryButtonBorderBrush']     = NewBrush  90 123 119   # #5A7B77 - visible mid-tone border
    $res['StatusPositiveBrush']      = NewBrush 137 194 160        # #89C2A0 - text/icon: success state
    $res['StatusErrorBrush']         = NewBrush 210 132 132        # #D28484 - text/icon: error state
    $res['StatusWarningBrush']       = NewBrush 214 158  46        # #D69E2E - text/icon: warning state
    $res['StatusPositiveLightBrush'] = NewAlphaBrush 26  76 175  80  # #1A4CAF50 - row background: positive
    $res['StatusWarningLightBrush']  = NewAlphaBrush 26 255 179   0  # #1AFFB300 - row background: warning
    $res['StatusErrorLightBrush']    = NewAlphaBrush 26 255  51  51  # #1AFF3333 - row background: error
    $res['RowHoverBrush']            = NewBrush  48  80  76          # #30504C   - row hover: visible mid-tone teal above dark bg

    $Window.Background = $res['WindowBackgroundBrush']
    if ($null -ne $ThemeLabelTextBlock) {
        $ThemeLabelTextBlock.Text = 'Dark theme'
    }

    # Colour the native OS title bar to match AccentBrush #4DB8AD (R=77 G=184 B=173)
    # COLORREF byte order is 0x00BBGGRR -> 0x00ADB84D
    & $setDwmTitleBarColor -ThemeWindow $Window -CaptionColorRef 0x00ADB84D -UseDarkMode $true
}
