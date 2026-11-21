Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwWorkbenchTitleBar {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
    if ($handle -eq [IntPtr]::Zero) { return }
    if ([Environment]::OSVersion.Version.Build -lt 22000) {
        Write-Verbose -Message 'EvergreenUI: Native title bar colour overrides require Windows 11.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Window.Title, 'Match title bar to form colours')) {
        return
    }
    if (-not ('EvergreenUI.WorkbenchDwm' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EvergreenUI {
    public static class WorkbenchDwm {
        public const int CaptionColor = 35;
        public const int TextColor = 36;
        public const int SystemBackdropType = 38;
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    }
}
'@ -ErrorAction Stop
    }

    if ([Environment]::OSVersion.Version.Build -ge 22621) {
        $noBackdrop = 1
        $result = [EvergreenUI.WorkbenchDwm]::DwmSetWindowAttribute(
            $handle, [EvergreenUI.WorkbenchDwm]::SystemBackdropType, [ref]$noBackdrop, 4
        )
        if ($result -ne 0) {
            Write-Verbose -Message "EvergreenUI: Could not disable the title bar backdrop (HRESULT $result)."
        }
    }
    foreach ($attribute in [EvergreenUI.WorkbenchDwm]::CaptionColor, [EvergreenUI.WorkbenchDwm]::TextColor) {
        $color = if ($attribute -eq [EvergreenUI.WorkbenchDwm]::CaptionColor) {
            $Window.Background.Color
        }
        else {
            $Window.Foreground.Color
        }
        $colorRef = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
        $result = [EvergreenUI.WorkbenchDwm]::DwmSetWindowAttribute($handle, $attribute, [ref]$colorRef, 4)
        if ($result -ne 0) {
            Write-Verbose -Message "EvergreenUI: Could not set title bar attribute $attribute (HRESULT $result)."
        }
    }
}
