Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchNavigationIndicator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Grid]$Container,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Border]$Indicator,

        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$SelectedItem,

        [Parameter(Mandatory)]
        [bool]$Animate,

        [ValidateSet('Vertical', 'Horizontal')]
        [string]$Orientation = 'Vertical'
    )

    if (-not $SelectedItem.IsLoaded -or $SelectedItem.ActualHeight -le 0) {
        return
    }

    $position = $SelectedItem.TranslatePoint([System.Windows.Point]::new(0, 0), $Container)
    $transform = $Indicator.RenderTransform
    if ($transform.IsFrozen) {
        $transform = $transform.Clone()
        $Indicator.RenderTransform = $transform
    }
    if ($Orientation -eq 'Horizontal') {
        $target = $position.X + (($SelectedItem.ActualWidth - $Indicator.Width) / 2)
        $property = [System.Windows.Media.TranslateTransform]::XProperty
        $transform.Y = $position.Y + $SelectedItem.ActualHeight - $Indicator.Height
    }
    else {
        $target = $position.Y + (($SelectedItem.ActualHeight - $Indicator.Height) / 2)
        $property = [System.Windows.Media.TranslateTransform]::YProperty
    }
    $current = [double]$transform.GetValue($property)
    $wasVisible = $Indicator.Visibility -eq [System.Windows.Visibility]::Visible
    $transform.BeginAnimation($property, $null)
    $Indicator.Visibility = [System.Windows.Visibility]::Visible

    if ($Animate -and $wasVisible -and $current -ne $target) {
        $transform.SetValue($property, $current)
        $animation = [System.Windows.Media.Animation.DoubleAnimation]::new(
            $current,
            $target,
            [System.Windows.Duration]::new([timespan]::FromMilliseconds(200))
        )
        $animation.EasingFunction = [System.Windows.Media.Animation.CubicEase]@{
            EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        }
        $transform.BeginAnimation($property, $animation)
    }
    else {
        $transform.SetValue($property, $target)
    }
}
