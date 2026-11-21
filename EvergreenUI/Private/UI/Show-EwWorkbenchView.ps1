Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet('Apps', 'Download', 'Library')]
        [string]$View
    )

    foreach ($name in @('Apps', 'Download', 'Library')) {
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
    }
}
