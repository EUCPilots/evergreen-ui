Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwDefinitionQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Query
    )

    if ($Query.CommandName -ieq 'Get-EvergreenApp') {
        return @(Get-EwAppVersion -Name $Query.AppName -ErrorAction Stop)
    }

    return @(Get-EwVcList -ErrorAction Stop)
}
