Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Restore-EwWorkbenchWindowSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings,

        [System.Windows.Rect]$WorkArea = [System.Windows.SystemParameters]::WorkArea
    )

    $readSize = {
        param([string]$Name, [double]$Default, [double]$Minimum, [double]$Maximum)
        $size = 0.0
        $raw = if ($Settings.Contains($Name)) { [string]$Settings[$Name] } else { '' }
        if (-not [double]::TryParse($raw, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$size) -or $size -le 0) {
            Write-Verbose -Message "EvergreenUI: Invalid or missing $Name '$raw'; using $Default"
            $size = $Default
        }
        # The work area wins when it is smaller than the XAML minimum so the window stays on screen.
        $upper = [Math]::Max(1.0, $Maximum)
        return [Math]::Min([Math]::Max($size, [Math]::Min($Minimum, $upper)), $upper)
    }

    $Window.Width = & $readSize -Name 'WindowWidth' -Default 1200 -Minimum $Window.MinWidth -Maximum $WorkArea.Width
    $Window.Height = & $readSize -Name 'WindowHeight' -Default 820 -Minimum $Window.MinHeight -Maximum $WorkArea.Height
    $maximized = $false
    if ($Settings.Contains('WindowMaximized') -and [bool]::TryParse([string]$Settings.WindowMaximized, [ref]$maximized) -and $maximized) {
        $Window.WindowState = [System.Windows.WindowState]::Maximized
    }
    Write-Verbose -Message "EvergreenUI: Restored window size $($Window.Width)x$($Window.Height) (maximised: $maximized)"
}
