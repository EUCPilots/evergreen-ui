Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwVcList {
    [CmdletBinding()]
    param()

    Get-VcList -ErrorAction Stop
}
