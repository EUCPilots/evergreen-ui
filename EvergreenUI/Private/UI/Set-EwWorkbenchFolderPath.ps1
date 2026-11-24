Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwWorkbenchFolderPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Download', 'Library')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )

    $settingName = if ($Kind -eq 'Download') { 'OutputPath' } else { 'LibraryPath' }
    if (-not $PSCmdlet.ShouldProcess($settingName, "Set $Kind folder")) {
        return
    }
    Set-EwSetting -Name $settingName -Value $Path -Confirm:$false -ErrorAction Stop
    $State.Settings[$settingName] = $Path
    $State["Settings${Kind}PathBox"].Text = $Path
    if ($Kind -eq 'Download') {
        $State.DownloadDestinationText.Text = $Path
        $State.DownloadDestinationText.ToolTip = $Path
        if ([string]::IsNullOrWhiteSpace([string]$State.Settings.PackageOutputPath)) {
            $State.PackageOutputPathBox.Text = $Path
        }
    }
    else {
        $State.Settings.LibraryPathHistory = @((Get-EwSetting -ErrorAction Stop).LibraryPathHistory)
        Update-EwWorkbenchLibraryPathHistory -State $State -Path $Path -Confirm:$false
    }
    Invoke-EwWorkbenchFolderCheck -State $State -Kind $Kind
    Write-EwWorkbenchLog -State $State -Message "$Kind folder saved."
}
