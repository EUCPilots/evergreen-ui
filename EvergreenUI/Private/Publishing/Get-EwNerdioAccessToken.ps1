Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory)]
        [string]$ApiScope,

        [Parameter()]
        [string]$OAuthTokenUrl
    )

    if ([string]::IsNullOrWhiteSpace($OAuthTokenUrl)) {
        $OAuthTokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    }
    $uri = $null
    if (-not [uri]::TryCreate($OAuthTokenUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw 'Nerdio OAuth token endpoint must be an absolute HTTPS URI.'
    }

    $credential = [PSCredential]::new($ClientId, $ClientSecret)
    $body = @{
        grant_type = 'client_credentials'
        scope = $ApiScope
        client_id = $ClientId
        client_secret = $credential.GetNetworkCredential().Password
    }
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body `
        -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$response.access_token)) {
        throw 'Nerdio authentication response did not contain an access token.'
    }
    return $response
}
