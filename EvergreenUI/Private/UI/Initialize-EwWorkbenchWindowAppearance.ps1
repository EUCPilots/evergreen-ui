Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchWindowAppearance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    $foregroundDescriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Window]
    )
    $backgroundDescriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Window]
    )
    $appearance = @{ Pending = $false; Closed = $false; Source = $null }
    $setTitleBar = Get-Command -Name Set-EwWorkbenchTitleBar -CommandType Function -ErrorAction Stop
    $refreshTitleBar = [System.EventHandler]{
        if ($appearance.Closed -or $appearance.Pending -or $Window.Dispatcher.HasShutdownStarted) {
            return
        }
        $appearance.Pending = $true
        $targetWindow = $Window
        $applyTitleBar = $setTitleBar
        $appearanceState = $appearance
        $null = $targetWindow.Dispatcher.InvokeAsync([action]{
            $appearanceState.Pending = $false
            if ($appearanceState.Closed) { return }
            try {
                & $applyTitleBar -Window $targetWindow
            }
            catch {
                # Title bar styling is cosmetic and must not interrupt the interface.
                Write-Verbose -Message "EvergreenUI: Could not update the title bar: $($_.Exception.Message)"
            }
        }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Render)
    }.GetNewClosure()
    $appearanceHook = [System.Windows.Interop.HwndSourceHook]{
        if ($args[1] -in 0x001A, 0x031A, 0x031E, 0x031F, 0x0320) {
            $refreshTitleBar.Invoke($Window, [EventArgs]::Empty)
        }
        return [IntPtr]::Zero
    }.GetNewClosure()
    $Window.Add_SourceInitialized({
        $handle = [System.Windows.Interop.WindowInteropHelper]::new($Window).Handle
        $appearance.Source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
        if ($null -ne $appearance.Source) {
            $appearance.Source.AddHook($appearanceHook)
        }
        $refreshTitleBar.Invoke($Window, [EventArgs]::Empty)
    }.GetNewClosure())
    $Window.Add_Loaded({
        param($eventSource, $loadedArgs)
        $refreshTitleBar.Invoke($eventSource, $loadedArgs)
    }.GetNewClosure())
    $foregroundDescriptor.AddValueChanged($Window, $refreshTitleBar)
    $backgroundDescriptor.AddValueChanged($Window, $refreshTitleBar)
    $systemAppearanceChanged = [System.ComponentModel.PropertyChangedEventHandler]{
        if ($args[1].PropertyName -in 'HighContrast', 'WindowGlassColor', 'WindowGlassBrush') {
            $refreshTitleBar.Invoke($Window, [EventArgs]::Empty)
        }
    }.GetNewClosure()
    [System.Windows.SystemParameters]::add_StaticPropertyChanged($systemAppearanceChanged)
    $Window.Add_Closed({
        $appearance.Closed = $true
        if ($null -ne $appearance.Source -and -not $appearance.Source.IsDisposed) {
            $appearance.Source.RemoveHook($appearanceHook)
        }
        $foregroundDescriptor.RemoveValueChanged($Window, $refreshTitleBar)
        $backgroundDescriptor.RemoveValueChanged($Window, $refreshTitleBar)
        [System.Windows.SystemParameters]::remove_StaticPropertyChanged($systemAppearanceChanged)
    }.GetNewClosure())
}
