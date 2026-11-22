Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365IntuneMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigurationId)

    $configurationGuid = [guid]::Parse($ConfigurationId)
    $matchedApps = foreach ($app in @(Get-EwIntuneApp)) {
        $guid = [guid]::Empty
        if ($app.NotesValid -ne 'Yes' -or
            -not [guid]::TryParse([string]$app.NotesGuid, [ref]$guid) -or $guid -eq [guid]::Empty -or
            [string]::IsNullOrWhiteSpace([string]$app.IntuneAppId)) {
            throw 'A PSPackageFactory Intune app has invalid notes or an unavailable ID. Matching cannot be verified.'
        }
        if ($guid -eq $configurationGuid) {
            [PSCustomObject]@{
                Id = [string]$app.IntuneAppId; Name = [string]$app.DisplayName
                Version = [string]$app.DisplayVersion
            }
        }
    }
    $rows = @($matchedApps | Sort-Object -Property Id)
    if (@($rows | Group-Object -Property Id | Where-Object Count -gt 1).Count -gt 0) {
        throw 'Intune returned duplicate app identifiers. Matching cannot be verified.'
    }
    return $rows
}
