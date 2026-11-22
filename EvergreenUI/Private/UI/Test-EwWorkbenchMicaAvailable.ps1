Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EwWorkbenchMicaAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [int]$WindowsBuild = [Environment]::OSVersion.Version.Build,

        [bool]$HighContrast = [System.Windows.SystemParameters]::HighContrast
    )

    if ($WindowsBuild -lt 22621 -or $HighContrast -or $Window.AllowsTransparency) {
        Write-Verbose -Message 'EvergreenUI: Mica is unavailable for the current Windows or accessibility settings.'
        return $false
    }
    $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
    if ($handle -eq [IntPtr]::Zero) {
        Write-Verbose -Message 'EvergreenUI: Mica is unavailable because the window has no native handle.'
        return $false
    }
    $source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
    if ($null -eq $source -or $null -eq $source.CompositionTarget) {
        Write-Verbose -Message 'EvergreenUI: Mica is unavailable because the window has no composition target.'
        return $false
    }

    $compositionEnabled = 0
    $result = [EvergreenUI.WorkbenchChromeInterop]::DwmIsCompositionEnabled([ref]$compositionEnabled)
    if ($result -ne 0 -or $compositionEnabled -eq 0) {
        Write-Verbose -Message "EvergreenUI: Mica composition is unavailable (HRESULT $result)."
        return $false
    }
    $backdrop = 0
    $result = [EvergreenUI.WorkbenchChromeInterop]::DwmGetWindowAttribute(
        $handle, [EvergreenUI.WorkbenchChromeInterop]::SystemBackdropType, [ref]$backdrop, 4
    )
    if ($result -ne 0) {
        Write-Verbose -Message "EvergreenUI: Could not inspect the WPF backdrop (HRESULT $result)."
        return $false
    }
    if ($backdrop -ne 2) {
        Write-Verbose -Message 'EvergreenUI: WPF did not enable the main-window backdrop.'
        return $false
    }
    return $true
}
