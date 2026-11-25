Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Reset-EwSetting {
    <#
    .SYNOPSIS
        Resets Evergreen Workbench settings.
    .DESCRIPTION
        Removes the Workbench settings file so defaults are used on the next read.
    .EXAMPLE
        Reset-EwSetting -Confirm
    .OUTPUTS
        None.
    .NOTES
        Only removes the Workbench settings file.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $path = Get-EwSettingsPath
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and $PSCmdlet.ShouldProcess($path, 'Reset settings')) {
        Write-Verbose -Message "EvergreenUI: Removing settings from $path"
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        Write-Verbose -Message "EvergreenUI: Settings reset"
    }
}
