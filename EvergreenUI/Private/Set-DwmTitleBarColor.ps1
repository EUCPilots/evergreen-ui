#Requires -Version 5.1
<#
.SYNOPSIS
    Applies accent colour, border colour, and dark/light mode flags to native
    OS window chrome via the Desktop Window Manager (DWM) API.

.DESCRIPTION
    Uses DwmSetWindowAttribute with DWMWA_CAPTION_COLOR (attr 35),
    DWMWA_BORDER_COLOR (attr 34), and DWMWA_USE_IMMERSIVE_DARK_MODE (attr 20)
    to match the native title bar/border colour and text/button rendering to
    the active EvergreenUI theme.

    DWMWA_CAPTION_COLOR requires Windows 11 (build 22000+). On Windows 10 the
    DWM call fails with E_INVALIDARG; errors are silently swallowed so behaviour
    on older systems is unchanged.

    The P/Invoke type is registered once per PowerShell session under the
    namespace EvergreenUI to avoid conflicts with other modules.

.PARAMETER Window
    The WPF Window whose title bar colour should be updated.

.PARAMETER CaptionColorRef
    A Windows COLORREF integer (0x00BBGGRR byte order) representing the desired
    caption background colour.

.PARAMETER BorderColorRef
    Optional Windows COLORREF integer (0x00BBGGRR byte order) representing the
    desired native window border colour. If omitted, caption colour is used.

.PARAMETER UseDarkMode
    When $true the OS renders white caption text / buttons (for dark backgrounds).
    When $false it renders dark caption text / buttons (for light backgrounds).

.EXAMPLE
    # Dark theme – AccentBrush #4DB8AD (R=77 G=184 B=173)
    Set-DwmTitleBarColor -Window $window -CaptionColorRef 0x00ADB84D -UseDarkMode $true

    # Light theme – AccentBrush #009485 (R=0 G=148 B=133)
    Set-DwmTitleBarColor -Window $window -CaptionColorRef 0x00859400 -UseDarkMode $false
#>
function Set-DwmTitleBarColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [int]$CaptionColorRef,

        [Parameter()]
        [int]$BorderColorRef = $CaptionColorRef,

        [Parameter(Mandatory)]
        [bool]$UseDarkMode
    )

    # Register the P/Invoke type once per session
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
        public const int DWMWA_BORDER_COLOR            = 34;
        public const int DWMWA_CAPTION_COLOR           = 35;
    }
}
'@
    }

    try {
        $hwnd = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
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

        [EvergreenUI.DwmHelper]::DwmSetWindowAttribute(
            $hwnd,
            [EvergreenUI.DwmHelper]::DWMWA_BORDER_COLOR,
            [ref]$BorderColorRef,
            4
        ) | Out-Null
    }
    catch {
        # DWM window chrome colouring is cosmetic; silently ignore on unsupported builds
    }
}
