Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchDwmAttribute {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Handle,

        [Parameter(Mandatory)]
        [int]$Attribute,

        [Parameter(Mandatory)]
        [int]$Value
    )

    $result = [EvergreenUI.WorkbenchChromeInterop]::DwmSetWindowAttribute($Handle, $Attribute, [ref]$Value, 4)
    if ($result -ne 0) {
        Write-Verbose -Message "EvergreenUI: Could not set window attribute $Attribute (HRESULT $result)."
    }
    return $result
}
