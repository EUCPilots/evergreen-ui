Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioDefinitionHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath
    )

    $hashes = foreach ($name in 'Definition.json', 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
        $path = Join-Path -Path $DefinitionPath -ChildPath $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            "$name=$((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash)"
        }
        else {
            "$name=missing"
        }
    }
    $hashes -join ';'
}
