Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioSessionContext {
    [CmdletBinding()]
    param()

    $context = $script:ewNerdioSession.Context
    if ($null -eq $context) {
        throw 'Nerdio is not connected. Call Connect-EwNerdio first.'
    }
    if ([DateTimeOffset]::UtcNow -ge $context.TokenExpiresAt) {
        $script:ewNerdioSession.Context = $null
        throw 'Nerdio Manager access token has expired. Call Connect-EwNerdio again.'
    }
    return $context
}
