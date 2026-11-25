Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Restore-EwWorkbenchStartupView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $views = @('Apps', 'Library', 'Packages', 'Intune', 'Nerdio', 'Settings', 'About')
    $saved = if ($State.Settings.Contains('StartupView')) { [string]$State.Settings.StartupView } else { '' }
    $view = if ($saved -eq 'Download') {
        'Apps'
    }
    elseif ($saved -eq 'Install') {
        $State.InstallTab.IsSelected = $true
        'Packages'
    }
    else {
        $views | Where-Object { $_ -eq $saved } | Select-Object -First 1
    }
    if ($null -eq $view) {
        Write-Verbose -Message "EvergreenUI: Startup view '$saved' is not supported; opening Apps"
        $view = 'Apps'
    }
    elseif ($saved -ne 'Download') {
        Write-Verbose -Message "EvergreenUI: Restoring startup view $view"
    }
    $navigation = $State["Nav$view"]
    if ($navigation.IsChecked) {
        Show-EwWorkbenchView -State $State -View $view
    }
    else {
        $navigation.IsChecked = $true
    }
    $State.Settings['StartupView'] = $view
    $State.UiStateReady = $true
}
