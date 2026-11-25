Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EwNerdioSource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source
    )

    $type = [string](Get-EwFirstPropertyValue -InputObject $Source -Name 'type')
    $filter = [string](Get-EwFirstPropertyValue -InputObject $Source -Name 'filter')
    switch ($type) {
        'Evergreen' {
            $app = [string](Get-EwFirstPropertyValue -InputObject $Source -Name 'app')
            if ([string]::IsNullOrWhiteSpace($app)) {
                throw 'Definition source.app is empty.'
            }
            $expression = "Get-EvergreenApp -Name '$($app.Replace("'", "''"))'"
        }
        'VcRedist' {
            $expression = 'Get-VcList'
        }
        'Static' {
            $url = [string](Get-EwFirstPropertyValue -InputObject $Source -Name 'url')
            if ([string]::IsNullOrWhiteSpace($url)) {
                throw 'Static definition source has no url.'
            }
            Write-Verbose -Message "EvergreenUI: Using static Nerdio source URL '$url'"
            return [PSCustomObject]@{
                Version = [string](Get-EwFirstPropertyValue -InputObject $Source -Name 'version')
                URI = $url
                Artifact = $null
            }
        }
        default {
            throw "Unsupported definition source type '$type'."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($filter)) {
        $expression += " | Where-Object { $filter }"
    }
    $expression += ' | Select-Object -First 1'
    Write-Verbose -Message "EvergreenUI: Resolving Nerdio source with '$expression'"
    $query = ConvertFrom-EwDefinitionFilter -Filter $expression
    $artifacts = @(Invoke-EwDefinitionQuery -Query $query)
    if ($null -ne $query.Predicate) {
        $artifacts = @($artifacts | Where-Object { [bool](Get-EwFilterLiteralValue -Expression $query.Predicate -Artifact $_) })
    }
    if ($artifacts.Count -eq 0) {
        throw 'The definition source filter returned no artifacts.'
    }
    $artifact = $artifacts[0]
    $result = [PSCustomObject]@{
        Version = [string](Get-EwFirstPropertyValue -InputObject $artifact -Name 'Version')
        URI = [string](Get-EwFirstPropertyValue -InputObject $artifact -Name 'URI', 'Uri', 'URL', 'Download')
        Artifact = $artifact
    }
    Write-Verbose -Message "EvergreenUI: Nerdio source resolved to version '$($result.Version)'"
    return $result
}
