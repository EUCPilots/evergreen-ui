Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet('Apps', 'Download', 'Library', 'Packages', 'Install')]
        [string]$View
    )

    foreach ($name in @('Apps', 'Download', 'Library', 'Packages', 'Install')) {
        $visibility = if ($name -eq $View) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
        $State["${name}Panel"].Visibility = $visibility
    }
    $State.ViewTitleText.Text = $View
    switch ($View) {
        'Apps' { $State.SubtitleTextBlock.Text = 'Discover and manage Evergreen applications' }
        'Download' { $State.SubtitleTextBlock.Text = 'Review and run queued artifact downloads' }
        'Library' { $State.SubtitleTextBlock.Text = 'Inspect and refresh a local Evergreen library' }
        'Packages' { $State.SubtitleTextBlock.Text = 'Configure and update Intune package definitions' }
        'Install' { $State.SubtitleTextBlock.Text = 'Check and install applications on this device' }
    }
}
