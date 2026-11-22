Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365DeploymentArtifact {
    [CmdletBinding()]
    param()

    $best = $null
    $bestVersion = [version]'0.0'
    foreach ($row in @(Get-EwAppVersion -Name MicrosoftOfficeDeploymentTool -ErrorAction Stop)) {
        $version = [version]'0.0'
        $text = [string](Get-EwFirstPropertyValue -InputObject $row -Name 'Version')
        $uri = [string](Get-EwFirstPropertyValue -InputObject $row -Name 'URI')
        $parsedUri = $null
        if ([version]::TryParse($text, [ref]$version) -and
            [uri]::TryCreate($uri, [UriKind]::Absolute, [ref]$parsedUri) -and
            $parsedUri.Scheme -eq 'https' -and ($null -eq $best -or $version -gt $bestVersion)) {
            $best = $row
            $bestVersion = $version
        }
    }
    if ($null -eq $best) {
        throw 'Evergreen returned no valid Office Deployment Tool artifact with an HTTPS URI.'
    }
    Write-Verbose -Message "EvergreenUI: Resolved Office Deployment Tool version '$($best.Version)'"
    return $best
}
