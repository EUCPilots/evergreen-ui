Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet('Apps', 'Library', 'Packages', 'Intune', 'Nerdio', 'Install', 'Settings', 'About')]
        [string]$View
    )

    if ($View -eq 'Install') {
        $State.InstallTab.IsSelected = $true
        $View = 'Packages'
    }
    foreach ($name in @('Apps', 'Library', 'Packages', 'Intune', 'Nerdio', 'Settings', 'About')) {
        $visibility = if ($name -eq $View) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
        $State["${name}Panel"].Visibility = $visibility
    }
    $State.ViewTitleText.Text = $View
    if ($State.UiStateReady -and [string]$State.Settings.StartupView -ne $View) {
        Save-EwWorkbenchUiSetting -State $State -Name 'StartupView' -Value $View
    }
    switch ($View) {
        'Apps' { $State.SubtitleTextBlock.Text = 'Discover and download Evergreen applications' }
        'Library' { $State.SubtitleTextBlock.Text = 'Inspect and refresh a local Evergreen library' }
        'Packages' {
            $State.SubtitleTextBlock.Text = 'Validate and update Intune package definitions. Test with local installation'
            if ($State.InstallTab.IsSelected -and -not $State.InstallDefinitionsStale) {
                Invoke-EwWorkbenchInstallStale -State $State
            }
            Invoke-EwWorkbenchInstallRefresh -State $State
        }
        'Intune' { $State.SubtitleTextBlock.Text = 'Compare and publish applications to Intune' }
        'Nerdio' { $State.SubtitleTextBlock.Text = 'Compare and publish Nerdio Manager Shell Apps' }
        'Settings' {
            $State.SubtitleTextBlock.Text = 'Manage saved Workbench folders and preferences'
            Invoke-EwWorkbenchSettingsRefresh -State $State
        }
        'About' {
            $State.SubtitleTextBlock.Text = 'View Workbench and dependency information'
            Invoke-EwWorkbenchAboutRefresh -State $State
        }
    }
}
