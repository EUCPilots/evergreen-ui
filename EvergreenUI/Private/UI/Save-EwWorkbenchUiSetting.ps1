Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Save-EwWorkbenchUiSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet(
            'StartupView', 'LastAppName', 'WindowWidth', 'WindowHeight', 'DownloadTrayHeight',
            'AppsListWidth', 'ArtifactHiddenColumns', 'WindowMaximized'
        )]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    # UI state is a convenience; a failed save must never block navigation, selection or closing.
    try {
        Set-EwSetting -Name $Name -Value $Value -Confirm:$false -ErrorAction Stop
        $State.Settings[$Name] = if ($Name -in @('DownloadTrayHeight', 'AppsListWidth')) { [int]$Value } else { $Value }
        Write-Verbose -Message "EvergreenUI: Saved Workbench UI setting $Name"
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Could not save UI setting ${Name}: $($_.Exception.Message)"
        Write-EwWorkbenchLog -State $State -Message "Could not save $Name`: $($_.Exception.Message)" -Level Warning
    }
}
