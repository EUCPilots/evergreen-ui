Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntuneSupersedenceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$App
    )

    $byId = @{}
    $incoming = @{}
    $outgoing = @{}
    foreach ($item in $App) {
        $id = [string]$item.IntuneAppId
        if ($byId.ContainsKey($id)) {
            return [PSCustomObject]@{ Verified = $false; CurrentAppId = ''; SupersededAppIds = @() }
        }
        $byId[$id] = $item
        $incoming[$id] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $outgoing[$id] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($item in $App) {
        foreach ($target in @(Get-EwObjectPropertyValue -Object $item -Name 'SupersededAppIds' -Default @())) {
            if ($byId.ContainsKey([string]$target)) {
                $null = $outgoing[[string]$item.IntuneAppId].Add([string]$target)
                $null = $incoming[[string]$target].Add([string]$item.IntuneAppId)
            }
        }
    }
    $roots = @($App | Where-Object { $incoming[[string]$_.IntuneAppId].Count -eq 0 })
    $linear = @($App | Where-Object { $incoming[[string]$_.IntuneAppId].Count -gt 1 -or $outgoing[[string]$_.IntuneAppId].Count -gt 1 }).Count -eq 0
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($roots.Count -eq 1 -and $linear) {
        $id = [string]$roots[0].IntuneAppId
        while (-not [string]::IsNullOrWhiteSpace($id) -and $visited.Add($id)) {
            $id = [string](@($outgoing[$id]) | Select-Object -First 1)
        }
    }
    $verified = $App.Count -gt 0 -and $roots.Count -eq 1 -and $linear -and $visited.Count -eq $App.Count
    [PSCustomObject]@{
        Verified = $verified
        CurrentAppId = if ($verified) { [string]$roots[0].IntuneAppId } else { '' }
        SupersededAppIds = if ($verified) { @($App | Where-Object IntuneAppId -NE $roots[0].IntuneAppId | ForEach-Object { [string]$_.IntuneAppId }) } else { @() }
    }
}
