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
        Add-Type -ReferencedAssemblies @(
            [System.Windows.Window].Assembly.Location
            [System.Windows.Interop.HwndSource].Assembly.Location
            [System.Windows.DependencyObject].Assembly.Location
        ) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace EvergreenUI {
    public static class WorkbenchChromeInterop {
        public const int NonClientRenderingEnabled = 1;
        public const int NonClientRenderingPolicy = 2;
        public const int UseWindowStyle = 0;
        public const int NonClientRenderingDisabled = 1;
        public const int WindowCornerPreference = 33;
        public const int RoundWindowCorners = 2;
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

    // PowerShell delegates cannot propagate the by-reference handled flag required by HwndSourceHook.
    public sealed class WorkbenchCaptionHook : IDisposable {
        private const int HitTestMaximize = 9;
        private readonly Window window;
        private readonly FrameworkElement maximizeButton;
        private readonly HwndSource source;
        private readonly HwndSourceHook hook;
        private readonly Action<string> report;
        private bool tracking;
        private bool pressed;
        private bool captured;

        [StructLayout(LayoutKind.Sequential)]
        private struct Point {
            public int X, Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TrackMouseEventInfo {
            public int Size, Flags;
            public IntPtr Window;
            public int HoverTime;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetCursorPos(out Point point);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetCapture(IntPtr hwnd);
        [DllImport("user32.dll")]
        private static extern IntPtr GetCapture();
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool ReleaseCapture();
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool TrackMouseEvent(ref TrackMouseEventInfo info);

        public WorkbenchCaptionHook(Window window, FrameworkElement maximizeButton, Action<string> report) {
            this.window = window;
            this.maximizeButton = maximizeButton;
            this.report = report;
            source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
            if (source == null) throw new InvalidOperationException("The Workbench window has no native source.");
            hook = HandleMessage;
        }

        public void Attach() {
            source.AddHook(hook);
        }

        private bool ContainsPoint(int x, int y) {
            if (!maximizeButton.IsVisible) return false;
            System.Windows.Point point = maximizeButton.PointFromScreen(new System.Windows.Point(x, y));
            return point.X >= 0 && point.Y >= 0 &&
                point.X < maximizeButton.ActualWidth && point.Y < maximizeButton.ActualHeight;
        }

        private bool ContainsCursor() {
            Point point;
            if (!GetCursorPos(out point)) {
                report("Could not read the caption pointer position (Win32 " + Marshal.GetLastWin32Error() + ").");
                return false;
            }
            return ContainsPoint(point.X, point.Y);
        }

        private void ReleaseMouse() {
            if (captured && GetCapture() == source.Handle && !ReleaseCapture()) {
                report("Could not release caption pointer capture (Win32 " + Marshal.GetLastWin32Error() + ").");
            }
            captured = false;
        }

        private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) {
            if (message == 0x84 && maximizeButton.IsVisible) {
                long packed = lParam.ToInt64();
                int x = unchecked((short)(packed & 0xffff));
                int y = unchecked((short)((packed >> 16) & 0xffff));
                if (ContainsPoint(x, y)) {
                    handled = true;
                    return new IntPtr(HitTestMaximize);
                }
            }
            else if (message == 0xa0 && wParam.ToInt64() == HitTestMaximize) {
                if (!pressed) maximizeButton.Tag = "Hover";
                if (!tracking) {
                    TrackMouseEventInfo info = new TrackMouseEventInfo {
                        Size = Marshal.SizeOf<TrackMouseEventInfo>(),
                        Flags = 0x12,
                        Window = hwnd
                    };
                    tracking = TrackMouseEvent(ref info);
                    if (!tracking) {
                        report("Could not track the caption pointer (Win32 " + Marshal.GetLastWin32Error() + ").");
                    }
                }
            }
            else if ((message == 0xa1 || message == 0xa3) && wParam.ToInt64() == HitTestMaximize) {
                pressed = true;
                maximizeButton.Tag = "Pressed";
                SetCapture(hwnd);
                captured = GetCapture() == hwnd;
                if (!captured) {
                    report("Could not capture the caption pointer (Win32 " + Marshal.GetLastWin32Error() + ").");
                }
                handled = true;
            }
            else if (pressed && message == 0x200) {
                maximizeButton.Tag = ContainsCursor() ? "Pressed" : null;
            }
            else if (pressed && (message == 0x202 || message == 0xa2)) {
                bool activate = ContainsCursor();
                pressed = false;
                ReleaseMouse();
                maximizeButton.Tag = activate ? "Hover" : null;
                if (activate) {
                    if (window.WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(window);
                    else SystemCommands.MaximizeWindow(window);
                }
                handled = true;
            }
            else if (message == 0x2a2) {
                tracking = false;
                if (!pressed || !captured) {
                    pressed = false;
                    maximizeButton.Tag = null;
                }
            }
            else if (pressed && (message == 0x1f || message == 0x215)) {
                pressed = false;
                ReleaseMouse();
                maximizeButton.Tag = null;
            }
            return IntPtr.Zero;
        }

        public void Dispose() {
            pressed = false;
            ReleaseMouse();
            maximizeButton.Tag = null;
            if (!source.IsDisposed) source.RemoveHook(hook);
        }
    }
}
'@ -ErrorAction Stop
    }

    $titleBar = $Window.FindName('WorkbenchTitleBar')
    $micaAvailable = Test-EwWorkbenchMicaAvailable -Window $Window -HighContrast $HighContrast
    if ($micaAvailable) {
        try {
            $initializing = $titleBar.Visibility -ne [System.Windows.Visibility]::Visible
            if ($initializing) {
                $Window.WindowStyle = [System.Windows.WindowStyle]::None
                $chrome = [System.Windows.Shell.WindowChrome]::new()
                $chrome.CaptionHeight = 40
                $chrome.ResizeBorderThickness = [System.Windows.Thickness]::new(8)
                $chrome.GlassFrameThickness = [System.Windows.Shell.WindowChrome]::GlassFrameCompleteThickness
                $chrome.UseAeroCaptionButtons = $false
                [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $chrome)
                $source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
                if ($null -eq $source.CompositionTarget -or $source.CompositionTarget.BackgroundColor.A -ne 0) {
                    throw 'The WPF composition target is not transparent.'
                }
                $report = [Action[string]]{
                    param($message)
                    Write-Verbose -Message "EvergreenUI: $message"
                }
                $titleBar.Tag = [EvergreenUI.WorkbenchCaptionHook]::new(
                    $Window, $Window.FindName('MaximizeWindowButton'), $report
                )
                $titleBar.Tag.Attach()
                $titleBar.Visibility = [System.Windows.Visibility]::Visible
            }
            $renderingEnabled = 0
            $result = [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute(
                $handle, [EvergreenUI.WorkbenchChromeInterop]::NonClientRenderingEnabled, [ref]$renderingEnabled, 4
            )
            if ($result -ne 0) {
                throw "Could not inspect non-client rendering (HRESULT $result)."
            }
            $changedRendering = $renderingEnabled -ne 0
            if ($changedRendering) {
                # The native accent-coloured caption otherwise covers the Mica backdrop.
                $result = Invoke-EwWorkbenchDwmAttribute -Handle $handle `
                    -Attribute ([EvergreenUI.WorkbenchChromeInterop]::NonClientRenderingPolicy) `
                    -Value ([EvergreenUI.WorkbenchChromeInterop]::NonClientRenderingDisabled)
                if ($result -ne 0) {
                    throw "Could not disable non-client rendering (HRESULT $result)."
                }
                $renderingEnabled = -1
                $result = [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute(
                    $handle, [EvergreenUI.WorkbenchChromeInterop]::NonClientRenderingEnabled, [ref]$renderingEnabled, 4
                )
                if ($result -ne 0 -or $renderingEnabled -ne 0) {
                    throw "Non-client rendering remained enabled (HRESULT $result)."
                }
            }
            if ($initializing -or $changedRendering) {
                $result = Invoke-EwWorkbenchDwmAttribute -Handle $handle `
                    -Attribute ([EvergreenUI.WorkbenchChromeInterop]::WindowCornerPreference) `
                    -Value ([EvergreenUI.WorkbenchChromeInterop]::RoundWindowCorners)
                if ($result -ne 0) {
                    throw "Could not request rounded window corners (HRESULT $result)."
                }
            }
            if ($Window.Background -ne [System.Windows.Media.Brushes]::Transparent) {
                $Window.Background = [System.Windows.Media.Brushes]::Transparent
                Write-Verbose -Message 'EvergreenUI: Enabled the Mica backdrop and custom caption.'
            }
            return
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Could not enable the Mica caption: $($_.Exception.Message)"
        }
    }

    $restoreBackground = $Window.WindowStyle -eq [System.Windows.WindowStyle]::None
    $chrome = [System.Windows.Shell.WindowChrome]::GetWindowChrome($Window)
    if ($restoreBackground) {
        $result = Invoke-EwWorkbenchDwmAttribute -Handle $handle `
            -Attribute ([EvergreenUI.WorkbenchChromeInterop]::NonClientRenderingPolicy) `
            -Value ([EvergreenUI.WorkbenchChromeInterop]::UseWindowStyle)
        if ($result -ne 0 -and $null -ne $chrome) {
            $titleBar.Visibility = [System.Windows.Visibility]::Visible
            $Window.SetResourceReference(
                [System.Windows.Controls.Control]::BackgroundProperty, 'ApplicationBackgroundBrush'
            )
            Write-Verbose -Message 'EvergreenUI: Could not restore the native caption; retaining the opaque custom caption.'
            return
        }
        $null = Invoke-EwWorkbenchDwmAttribute -Handle $handle `
            -Attribute ([EvergreenUI.WorkbenchChromeInterop]::WindowCornerPreference) -Value 0
    }
    if ($titleBar.Tag -is [IDisposable]) {
        $titleBar.Tag.Dispose()
        $titleBar.Tag = $null
    }
    $titleBar.Visibility = [System.Windows.Visibility]::Collapsed
    if ($null -ne $chrome) {
        [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $null)
    }
    if ($restoreBackground) {
        $Window.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
        $Window.SetResourceReference(
            [System.Windows.Controls.Control]::BackgroundProperty, 'ApplicationBackgroundBrush'
        )
        Write-Verbose -Message 'EvergreenUI: Restored the opaque background and native title bar.'
    }

    foreach ($attribute in [EvergreenUI.WorkbenchChromeInterop]::CaptionColor, [EvergreenUI.WorkbenchChromeInterop]::TextColor) {
        if ($HighContrast) {
            $null = Invoke-EwWorkbenchDwmAttribute -Handle $handle -Attribute $attribute -Value -1
            continue
        }
        $brush = if ($attribute -eq [EvergreenUI.WorkbenchChromeInterop]::CaptionColor) {
            $Window.TryFindResource('ApplicationBackgroundBrush')
        }
        else {
            $Window.Foreground
        }
        if ($brush -isnot [System.Windows.Media.SolidColorBrush]) {
            Write-Verbose -Message "EvergreenUI: Could not resolve a solid colour for title bar attribute $attribute."
            continue
        }
        $color = $brush.Color
        $colorRef = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
        $null = Invoke-EwWorkbenchDwmAttribute -Handle $handle -Attribute $attribute -Value $colorRef
    }
}
