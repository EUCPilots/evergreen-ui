Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioShellAppVersionPrunePlan {
    <#
    .SYNOPSIS
        Previews Shell App versions to retain and remove.
    .DESCRIPTION
        Returns an exact version-name snapshot for a Nerdio Shell App. Apps
        with duplicate, unparseable, or ambiguous versions are not eligible.
    .PARAMETER Id
        Shell App ID.
    .PARAMETER KeepVersions
        Number of newest versions to retain. Defaults to one.
    .PARAMETER PublishedVersion
        Version most recently published. When supplied, it must be the unique
        newest version before the app can be pruned.
    .EXAMPLE
        Get-EwNerdioShellAppVersionPrunePlan -Id 42 -KeepVersions 1 -PublishedVersion '2.0'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$KeepVersions = 1,

        [Parameter()]
        [AllowEmptyString()]
        [string]$PublishedVersion = ''
    )

    Write-Verbose -Message "EvergreenUI: Preparing a version pruning preview for Shell App '$Id'"
    $versions = @(Get-EwNerdioShellAppVersion -Id $Id | ForEach-Object {
            $name = [string](Get-EwFirstPropertyValue -InputObject $_ -Name 'name', 'version', 'displayVersion')
            $sortKey = $null
            if ($name -match '^[vV]?(\d+(?:\.\d+){0,3})$') {
                $parts = @($Matches[1].Split('.'))
                while ($parts.Count -lt 4) { $parts += '0' }
                $parsed = $null
                if (-not [version]::TryParse(($parts -join '.'), [ref]$parsed)) {
                    $parsed = [version]::new([int]::MaxValue, [int]::MaxValue, [int]::MaxValue, [int]::MaxValue)
                }
                $sortKey = $parsed
            }
            else {
                $sortKey = [version]::new([int]::MaxValue, [int]::MaxValue, [int]::MaxValue, [int]::MaxValue)
            }
            [PSCustomObject]@{
                Name = $name
                SortKey = $sortKey
            }
        })
    $names = @($versions | ForEach-Object Name)
    $reason = ''
    if ($versions.Count -eq 0) {
        $reason = 'Nerdio returned no versions.'
    }
    elseif (@($names | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        $reason = 'One or more version names are missing.'
    }
    elseif (@($names | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
        $reason = 'Duplicate version names make deletion ambiguous.'
    }
    elseif (@($versions | Where-Object {
                $_.SortKey -eq [version]::new([int]::MaxValue, [int]::MaxValue, [int]::MaxValue, [int]::MaxValue)
            }).Count -gt 0) {
        $reason = 'One or more version names cannot be ordered reliably.'
    }
    elseif (@($versions | Group-Object -Property SortKey | Where-Object Count -gt 1).Count -gt 0) {
        $reason = 'Different version names have the same ordering key.'
    }

    $sorted = @($versions | Sort-Object -Property SortKey, Name -Descending)
    if (-not $reason -and $PublishedVersion) {
        $published = @($versions | Where-Object Name -CEQ $PublishedVersion)
        if ($published.Count -ne 1 -or $sorted[0].Name -cne $PublishedVersion) {
            $reason = 'The published version is not uniquely the newest version.'
        }
    }
    $eligible = -not $reason
    if ($reason) {
        Write-Verbose -Message "EvergreenUI: Shell App '$Id' is not eligible for pruning: $reason"
    }
    $keep = @()
    $remove = @()
    if ($eligible) {
        $keepCount = [Math]::Min($KeepVersions, $sorted.Count)
        $keep = @($sorted | Select-Object -First $keepCount | ForEach-Object Name)
        if ($sorted.Count -gt $keepCount) {
            $remove = @($sorted | Select-Object -Skip $keepCount | ForEach-Object Name)
        }
    }

    Write-Verbose -Message "EvergreenUI: Shell App '$Id' pruning preview keeps $($keep.Count) and removes $($remove.Count) versions"
    [PSCustomObject]@{
        Id = $Id
        PublishedVersion = $PublishedVersion
        KeepVersions = $KeepVersions
        TotalVersions = $versions.Count
        VersionNames = [string[]]$names
        VersionDetails = [object[]]$versions
        Keep = [string[]]$keep
        Remove = [string[]]$remove
        Eligible = $eligible
        Message = if ($reason) { $reason } elseif ($remove.Count -eq 0) { 'No versions need removal.' } else { '' }
    }
}
