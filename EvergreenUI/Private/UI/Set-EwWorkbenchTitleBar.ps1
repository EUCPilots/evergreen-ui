Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwWorkbenchTitleBar {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [bool]$HighContrast = [System.Windows.SystemParameters]::HighContrast
    )

    $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
    if ($handle -eq [IntPtr]::Zero) { return }
    if ([Environment]::OSVersion.Version.Build -lt 22000) {
        Write-Verbose -Message 'EvergreenUI: Using the native title bar on this Windows version.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Window.Title, 'Update the backdrop and title bar')) {
        return
    }

    if (-not ('EvergreenUI.WorkbenchChromeInterop' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace EvergreenUI {
    public static class WorkbenchChromeInterop {
        public const int CaptionColor = 35;
        public const int TextColor = 36;
        public const int SystemBackdropType = 38;

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
        [DllImport("dwmapi.dll")]
        public static extern int DwmIsCompositionEnabled(out int enabled);
    }
}
'@ -ErrorAction Stop
    }

    if (Test-EwWorkbenchMicaAvailable -Window $Window -HighContrast $HighContrast) {
        if ($Window.Background -ne [System.Windows.Media.Brushes]::Transparent) {
            $Window.Background = [System.Windows.Media.Brushes]::Transparent
            Write-Verbose -Message 'EvergreenUI: Enabled the WPF Mica backdrop behind the native window.'
        }
    }
    elseif ($Window.Background -eq [System.Windows.Media.Brushes]::Transparent) {
        $Window.SetResourceReference(
            [System.Windows.Controls.Control]::BackgroundProperty, 'ApplicationBackgroundBrush'
        )
        Write-Verbose -Message 'EvergreenUI: Restored the opaque themed window background.'
    }

    foreach ($attribute in [EvergreenUI.WorkbenchChromeInterop]::CaptionColor, [EvergreenUI.WorkbenchChromeInterop]::TextColor) {
        $colorRef = -1
        if (-not $HighContrast) {
            $brush = if ($attribute -eq [EvergreenUI.WorkbenchChromeInterop]::CaptionColor) {
                $Window.TryFindResource('ApplicationBackgroundBrush')
            }
            else {
                $Window.Foreground
            }
            if ($brush -is [System.Windows.Media.SolidColorBrush]) {
                $color = $brush.Color
                $colorRef = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
            }
            else {
                Write-Verbose -Message "EvergreenUI: Could not resolve a solid colour for title bar attribute $attribute; using the Windows default."
            }
        }
        $null = Invoke-EwWorkbenchDwmAttribute -Handle $handle -Attribute $attribute -Value $colorRef
    }
}
