Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchProviderTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TabControl]$Tabs
    )

    $showIndicator = ${function:Show-EwWorkbenchNavigationIndicator}
    $layout = @{ Item = $null; X = $null; Y = $null }
    $update = {
        param([bool]$animate)

        $item = $Tabs.SelectedItem
        if (-not $Tabs.IsVisible -or $item -isnot [System.Windows.Controls.TabItem] -or
            -not $item.IsVisible -or -not $item.IsArrangeValid -or $item.ActualWidth -le 0) {
            return
        }
        $container = $Tabs.Template.FindName('HeaderArea', $Tabs)
        $indicator = $Tabs.Template.FindName('SelectedIndicator', $Tabs)
        if ($null -eq $container -or $null -eq $indicator) {
            return
        }
        $position = $item.TranslatePoint([System.Windows.Point]::new(0, 0), $container)
        $x = $position.X + (($item.ActualWidth - $indicator.Width) / 2)
        $y = $position.Y + $item.ActualHeight - $indicator.Height
        if ($layout.Item -eq $item -and $layout.X -eq $x -and $layout.Y -eq $y) {
            return
        }
        & $showIndicator -Container $container -Indicator $indicator -SelectedItem $item `
            -Animate $animate -Orientation 'Horizontal'
        $layout.Item = $item
        $layout.X = $x
        $layout.Y = $y
    }.GetNewClosure()
    $Tabs.Add_SelectionChanged({
        if ($args[1].OriginalSource -eq $Tabs) {
            & $update -animate ([System.Windows.SystemParameters]::ClientAreaAnimation)
        }
    }.GetNewClosure())
    foreach ($item in $Tabs.Items) {
        $item.Add_Loaded({ & $update -animate $false }.GetNewClosure())
    }
    $Tabs.Add_LayoutUpdated({ & $update -animate $false }.GetNewClosure())
}
