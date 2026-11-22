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

    foreach ($name in @('Apps', 'Library', 'Packages', 'Intune', 'Nerdio', 'Install', 'Settings', 'About')) {
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
        'Apps' { $State.SubtitleTextBlock.Text = 'Discover and manage Evergreen applications' }
        'Library' { $State.SubtitleTextBlock.Text = 'Inspect and refresh a local Evergreen library' }
        'Packages' { $State.SubtitleTextBlock.Text = 'Configure and update Intune package definitions' }
        'Intune' { $State.SubtitleTextBlock.Text = 'Compare and publish applications to Intune' }
        'Nerdio' { $State.SubtitleTextBlock.Text = 'Compare and publish Nerdio Manager Shell Apps' }
        'Install' { $State.SubtitleTextBlock.Text = 'Check and install applications on this device' }
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
