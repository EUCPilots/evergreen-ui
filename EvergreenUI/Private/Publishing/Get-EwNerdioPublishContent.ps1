Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioPublishContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [switch]$AddVersion
    )

    $definition = Get-Content -LiteralPath (Join-Path -Path $DefinitionPath -ChildPath 'Definition.json') -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if (-not $AddVersion) {
        $versions = Get-EwFirstPropertyValue -InputObject $definition -Name 'versions'
        if ($null -eq $versions -or @($versions).Count -eq 0 -or
            $null -eq @($versions)[0].PSObject.Properties['name'] -or
            $null -eq @($versions)[0].PSObject.Properties['file'] -or
            $null -eq @($versions)[0].file -or
            $null -eq @($versions)[0].file.PSObject.Properties['sourceUrl'] -or
            $null -eq @($versions)[0].file.PSObject.Properties['sha256']) {
            throw 'Definition.json must contain a version with file.sourceUrl and file.sha256 fields.'
        }
        foreach ($entry in @{ detectScript = 'Detect.ps1'; installScript = 'Install.ps1'; uninstallScript = 'Uninstall.ps1' }.GetEnumerator()) {
            $content = Get-Content -LiteralPath (Join-Path -Path $DefinitionPath -ChildPath $entry.Value) -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) { throw "Required script '$($entry.Value)' is empty." }
            $definition | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $content -Force
        }
    }
    return $definition
}
