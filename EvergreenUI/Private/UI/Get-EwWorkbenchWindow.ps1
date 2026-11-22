Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwWorkbenchWindow {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    if (-not $IsWindows) {
        throw 'Evergreen Workbench requires Windows because its user interface uses WPF.'
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $moduleRoot = Split-Path -Path $script:ewModulePath -Parent
    $xamlPath = Join-Path -Path $moduleRoot -ChildPath 'Resources\EvergreenWorkbench.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        throw "Workbench XAML resource was not found: $xamlPath"
    }

    Write-Verbose -Message "EvergreenUI: Loading Workbench XAML from $xamlPath"
    $reader = [System.Xml.XmlReader]::Create($xamlPath)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if ($window -isnot [System.Windows.Window]) {
        throw "Workbench XAML did not create a WPF Window: $xamlPath"
    }

    $navigationColumn = $window.FindName('NavigationColumn')
    $navigationPane = $window.FindName('NavigationPane')
    $navigationBrand = $window.FindName('NavigationBrand')
    $navigationScroll = $window.FindName('NavigationScrollViewer')
    $window.Add_SizeChanged({
        $compact = $args[0].ActualWidth -lt 1100
        $navigationColumn.Width = [System.Windows.GridLength]::new($(if ($compact) { 64 } else { 208 }))
        $navigationPane.Padding = [System.Windows.Thickness]::new($(if ($compact) { 4 } else { 16 }))
        $navigationBrand.Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
        $navigationScroll.Tag = $compact
    }.GetNewClosure())

    $activityLog = $window.FindName('ActivityLog')
    $resizeLog = {
        param([double]$change)
        $activityLog.Height = [Math]::Clamp($activityLog.Height + $change, 60, 300)
    }.GetNewClosure()
    $logResizeThumb = $window.FindName('ActivityLogResizeThumb')
    $logResizeThumb.Add_DragDelta({
        $dragArgs = $args[1]
        & $resizeLog -change (-$dragArgs.VerticalChange)
    }.GetNewClosure())
    $logResizeThumb.Add_KeyDown({
        $keyArgs = $args[1]
        if ($keyArgs.Key -eq [System.Windows.Input.Key]::Up) {
            & $resizeLog -change 10
            $keyArgs.Handled = $true
        }
        elseif ($keyArgs.Key -eq [System.Windows.Input.Key]::Down) {
            & $resizeLog -change -10
            $keyArgs.Handled = $true
        }
    }.GetNewClosure())

    $backgroundDescriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Window]
    )
    $foregroundDescriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Window]
    )
    $setTitleBar = Get-Command -Name Set-EwWorkbenchTitleBar -CommandType Function -ErrorAction Stop
    $refreshTitleBar = [System.EventHandler]{
        # Nested closures only capture locals, so copy the outer captured values first.
        $targetWindow = $window
        $applyTitleBar = $setTitleBar
        # Apply after the native theme has finished updating its own window chrome.
        $null = $targetWindow.Dispatcher.InvokeAsync([action]{
            try {
                & $applyTitleBar -Window $targetWindow
            }
            catch {
                # Title bar styling is cosmetic and must not interrupt the interface.
                Write-Verbose -Message "EvergreenUI: Could not update the title bar: $($_.Exception.Message)"
            }
        }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Render)
    }.GetNewClosure()
    $window.Add_SourceInitialized($refreshTitleBar)
    $window.Add_Loaded({
        param($eventSource, $loadedArgs)
        $refreshTitleBar.Invoke($eventSource, $loadedArgs)
    }.GetNewClosure())
    $backgroundDescriptor.AddValueChanged($window, $refreshTitleBar)
    $foregroundDescriptor.AddValueChanged($window, $refreshTitleBar)
    $window.Add_Closed({
        $backgroundDescriptor.RemoveValueChanged($window, $refreshTitleBar)
        $foregroundDescriptor.RemoveValueChanged($window, $refreshTitleBar)
    }.GetNewClosure())
    return $window
}
