Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwDefinitionQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Query,

        [Parameter()]
        [switch]$NoCache
    )

    if ($Query.CommandName -ieq 'Get-EvergreenApp') {
        return @(Get-EwAppVersion -Name $Query.AppName -NoCache:$NoCache -ErrorAction Stop)
    }

    return @(Get-EwVcList -ErrorAction Stop)
}
