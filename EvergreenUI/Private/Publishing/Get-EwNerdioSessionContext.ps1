Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioSessionContext {
    [CmdletBinding()]
    param()

    if ($null -eq $script:ewNerdioContext) {
        throw 'Nerdio is not connected. Call Connect-EwNerdio first.'
    }
    if ([DateTimeOffset]::UtcNow -ge $script:ewNerdioContext.TokenExpiresAt) {
        $script:ewNerdioContext = $null
        throw 'Nerdio Manager access token has expired. Call Connect-EwNerdio again.'
    }
    return $script:ewNerdioContext
}
