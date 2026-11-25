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

    $iconPath = Join-Path -Path $moduleRoot -ChildPath 'Resources\evergreenbulb.png'
    Write-Verbose -Message "EvergreenUI: Loading Workbench window icon from $iconPath"
    try {
        $icon = [System.Windows.Media.Imaging.BitmapImage]::new()
        $icon.BeginInit()
        $icon.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $icon.UriSource = [System.Uri]::new($iconPath, [System.UriKind]::Absolute)
        $icon.EndInit()
        $window.Icon = $icon
        Write-Verbose -Message "EvergreenUI: Loaded Workbench window icon from $iconPath"
    }
    catch {
        Write-Warning -Message "EvergreenUI: Could not load the Workbench window icon from ${iconPath}: $($_.Exception.Message)"
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

    Initialize-EwWorkbenchWindowAppearance -Window $window
    return $window
}
