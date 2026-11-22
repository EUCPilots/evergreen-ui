Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwM365UninstallConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Uninstall-Microsoft365Apps.xml was not found: $Path"
    }
    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ($null -eq $xml.SelectSingleNode('/Configuration/Remove')) {
        throw "The Office Deployment Tool uninstall configuration '$Path' has no Configuration.Remove element."
    }
}
