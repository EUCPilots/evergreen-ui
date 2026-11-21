Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365SetupArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Channel
    )

    $rows = @(Get-EwAppVersion -Name Microsoft365Apps -ErrorAction Stop | Where-Object {
        [string]$_.Channel -ieq $Channel
    })
    if ($rows.Count -eq 0) {
        throw "No Evergreen Microsoft 365 Apps artifact was found for channel '$Channel'."
    }

    $best = $null
    $bestVersion = [version]'0.0'
    foreach ($row in $rows) {
        $versionText = ([string]$row.Version) -replace '^[^0-9]*', '' -replace '[^0-9\.].*$', ''
        $candidateVersion = [version]'0.0'
        if ([version]::TryParse($versionText, [ref]$candidateVersion) -and
            ($null -eq $best -or $candidateVersion -gt $bestVersion)) {
            $best = $row
            $bestVersion = $candidateVersion
        }
        elseif ($null -eq $best) {
            $best = $row
        }
    }
    return $best
}
