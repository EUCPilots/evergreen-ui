Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Save-EwWorkbenchWindowSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $window = $State.Window
    $maximized = $window.WindowState -eq [System.Windows.WindowState]::Maximized
    # RestoreBounds holds the normal size while the window is maximised or minimised.
    $bounds = if ($window.WindowState -ne [System.Windows.WindowState]::Normal -and -not $window.RestoreBounds.IsEmpty) {
        $window.RestoreBounds.Size
    }
    else {
        [System.Windows.Size]::new($window.ActualWidth, $window.ActualHeight)
    }
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
        Write-Verbose -Message 'EvergreenUI: Window size is unavailable; keeping the saved size'
    }
    else {
        $width = [string][int][Math]::Round($bounds.Width)
        $height = [string][int][Math]::Round($bounds.Height)
        if ([string]$State.Settings.WindowWidth -ne $width) {
            Save-EwWorkbenchUiSetting -State $State -Name 'WindowWidth' -Value $width
        }
        if ([string]$State.Settings.WindowHeight -ne $height) {
            Save-EwWorkbenchUiSetting -State $State -Name 'WindowHeight' -Value $height
        }
    }
    if ([string]$State.Settings.WindowMaximized -ne [string]$maximized) {
        Save-EwWorkbenchUiSetting -State $State -Name 'WindowMaximized' -Value ([string]$maximized)
    }
}
