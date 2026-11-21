Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioShellApp {
    <#
    .SYNOPSIS
        Lists Nerdio Manager Shell Apps.
    .DESCRIPTION
        Returns the Shell Apps in Nerdio Manager with their latest version and
        version count. When the API omits either value, the app's versions are
        queried to derive them.
    .EXAMPLE
        Get-EwNerdioShellApp
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $context = Get-EwNerdioSessionContext
    Write-Verbose -Message 'EvergreenUI: Listing Nerdio Shell Apps'
    $response = Invoke-EwNerdioApiRequest -Method GET -Uri "https://$($context.NmeHost)/api/v1/shell-app" `
        -AccessToken $context.AccessToken
    $apps = @(Get-EwFirstPropertyValue -InputObject $response -Name 'items' | Where-Object { $null -ne $_ })
    Write-Verbose -Message "EvergreenUI: Nerdio returned $($apps.Count) Shell Apps"

    $rows = foreach ($app in $apps) {
        $id = [string](Get-EwFirstPropertyValue -InputObject $app -Name 'id', 'publicId', 'externalId')
        $latest = [string](Get-EwFirstPropertyValue -InputObject $app -Name 'latestVersion', 'version')
        $countValue = Get-EwFirstPropertyValue -InputObject $app -Name 'versionCount', 'versionsCount'
        $count = if ($null -ne $countValue -and [string]$countValue -match '^\d+$') { [int]$countValue } else { $null }

        if (($null -eq $count -or [string]::IsNullOrWhiteSpace($latest)) -and -not [string]::IsNullOrWhiteSpace($id)) {
            try {
                $versions = @(Get-EwNerdioShellAppVersion -Id $id)
                if ($null -eq $count) {
                    $count = $versions.Count
                }
                if ([string]::IsNullOrWhiteSpace($latest)) {
                    $latest = @($versions |
                            ForEach-Object { [string](Get-EwFirstPropertyValue -InputObject $_ -Name 'version', 'displayVersion', 'name') } |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                            Sort-Object -Property @{ Expression = { ConvertTo-EwNerdioVersionSortKey -Name $_ } } -Descending |
                            Where-Object { (ConvertTo-EwNerdioVersionSortKey -Name $_) -ne [version]::new([int]::MaxValue, [int]::MaxValue, [int]::MaxValue, [int]::MaxValue) } |
                            Select-Object -First 1) -join ''
                }
            }
            catch {
                # best-effort - a failed version lookup leaves the count and latest version unknown
                Write-Verbose -Message "EvergreenUI: Version lookup failed for Shell App '$id': $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            Id = $id
            Name = [string](Get-EwFirstPropertyValue -InputObject $app -Name 'name', 'displayName', 'cachedName')
            Publisher = [string](Get-EwFirstPropertyValue -InputObject $app -Name 'publisher', 'vendor', 'manufacturer')
            LatestVersion = $latest
            VersionCount = $count
        }
    }
    @($rows) | Sort-Object -Property Publisher, Name, Id
}
