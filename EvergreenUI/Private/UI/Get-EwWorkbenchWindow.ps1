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
    $navigationToggle = $window.FindName('NavigationToggle')
    $navigationItems = $window.FindName('NavigationItems')
    $navigationStack = $window.FindName('NavigationItemsStack')
    $navigationFooter = $window.FindName('NavigationFooter')
    $navigationIndicator = $window.FindName('NavigationSelectionIndicator')
    $navigationButtons = @('NavApps', 'NavLibrary', 'NavPackages', 'NavIntune', 'NavNerdio', 'NavSettings', 'NavAbout') |
        ForEach-Object { $window.FindName($_) }
    $showIndicator = ${function:Show-EwWorkbenchNavigationIndicator}
    $updateIndicator = {
        param([bool]$animate)
        foreach ($button in $navigationButtons) {
            if ($button.IsChecked) {
                & $showIndicator -Container $navigationItems -Indicator $navigationIndicator `
                    -SelectedItem $button -Animate $animate
                break
            }
        }
    }.GetNewClosure()
    foreach ($button in $navigationButtons) {
        $button.Add_Checked({
            & $showIndicator -Container $navigationItems -Indicator $navigationIndicator -SelectedItem $args[0] `
                -Animate ([System.Windows.SystemParameters]::ClientAreaAnimation)
        }.GetNewClosure())
        $button.Add_SizeChanged({ & $updateIndicator -animate $false }.GetNewClosure())
    }
    $navigationStack.Add_SizeChanged({ & $updateIndicator -animate $false }.GetNewClosure())
    $navigationFooter.Add_SizeChanged({ & $updateIndicator -animate $false }.GetNewClosure())
    $window.Add_Loaded({ & $updateIndicator -animate $false }.GetNewClosure())
    foreach ($name in @('PackagesTabControl', 'IntuneTabControl', 'NerdioTabControl')) {
        Initialize-EwWorkbenchProviderTab -Tabs $window.FindName($name)
    }
    $updateNavigationLayout = {
        $narrow = $window.ActualWidth -lt 1100
        $compact = $narrow -or $navigationToggle.IsChecked
        $navigationColumn.Width = [System.Windows.GridLength]::new($(if ($compact) { 64 } else { 208 }))
        $navigationPane.Padding = [System.Windows.Thickness]::new($(if ($compact) { 4 } else { 16 }))
        $navigationBrand.Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
        $navigationPane.Tag = $compact
        $navigationToggle.IsEnabled = -not $narrow
        $navigationToggle.ToolTip = if ($narrow) {
            'Navigation is compact while the window is narrow'
        }
        elseif ($compact) {
            'Expand navigation'
        }
        else {
            'Collapse navigation'
        }
        [System.Windows.Automation.AutomationProperties]::SetHelpText($navigationToggle, $navigationToggle.ToolTip)
    }.GetNewClosure()
    $navigationToggle.Add_Checked({ & $updateNavigationLayout }.GetNewClosure())
    $navigationToggle.Add_Unchecked({ & $updateNavigationLayout }.GetNewClosure())
    $window.Add_SizeChanged({
        & $updateNavigationLayout
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
