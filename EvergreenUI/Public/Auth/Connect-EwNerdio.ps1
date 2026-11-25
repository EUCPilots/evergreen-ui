Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EwNerdio {
    <#
    .SYNOPSIS
        Authenticates to Nerdio Manager, optionally with Azure storage context.
    .DESCRIPTION
        Uses a client credentials token for Nerdio Manager API calls. A full
        connection also uses Az.Accounts for the selected subscription and
        reuses an existing matching Azure context. The client secret and tokens
        remain in memory and are not written to settings.
    .PARAMETER TenantId
        Entra tenant ID.
    .PARAMETER SubscriptionId
        Optional Azure subscription ID used for the storage account context.
    .PARAMETER ClientId
        Application client ID used for Nerdio Manager API authentication.
    .PARAMETER ClientSecret
        Client secret held as a SecureString.
    .PARAMETER ApiScope
        OAuth scope required by the Nerdio Manager API.
    .PARAMETER NmeHost
        Nerdio Manager host name or HTTPS URL.
    .PARAMETER ResourceGroupName
        Azure resource group containing the target storage account.
    .PARAMETER StorageAccountName
        Azure storage account used to host Nerdio app payloads.
    .PARAMETER ContainerName
        Blob container used to host Nerdio app payloads.
    .PARAMETER OAuthTokenUrl
        Optional custom HTTPS OAuth token endpoint.
    .PARAMETER UseDeviceAuthentication
        Uses device authentication for the Azure sign-in.
    .PARAMETER ApiOnly
        Connects to the Nerdio API without signing in to Azure or selecting storage.
        Azure and a storage destination are still required for publishing.
    .EXAMPLE
        Connect-EwNerdio -TenantId $tenant -SubscriptionId $subscription `
            -ClientId $clientId -ClientSecret (Read-Host -AsSecureString) `
            -ApiScope $scope -NmeHost 'nme.contoso.com' `
            -ResourceGroupName 'apps' -StorageAccountName 'packages' -ContainerName 'shell-apps'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires an accessible Nerdio Manager API. A full connection also requires Az.Accounts.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Full')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Full')]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiScope,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NmeHost,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [ValidateNotNullOrEmpty()]
        [string]$ContainerName,

        [Parameter()]
        [string]$OAuthTokenUrl,

        [Parameter(ParameterSetName = 'Full')]
        [switch]$UseDeviceAuthentication,

        [Parameter(Mandatory, ParameterSetName = 'ApiOnly')]
        [switch]$ApiOnly
    )

    $script:ewNerdioSession.Context = $null
    $script:ewNerdioSession.ApiOnly = $false
    try {
        $hostUri = if ($NmeHost -match '^https://') { [uri]$NmeHost } else { [uri]("https://$($NmeHost.Trim('/'))") }
        if ($hostUri.Scheme -ne 'https' -or -not [string]::IsNullOrWhiteSpace($hostUri.PathAndQuery.Trim('/'))) {
            throw 'NmeHost must be a host name or HTTPS origin without a path.'
        }
        $token = Get-EwNerdioAccessToken -TenantId $TenantId -ClientId $ClientId `
            -ClientSecret $ClientSecret -ApiScope $ApiScope -OAuthTokenUrl $OAuthTokenUrl
        $azureContext = [PSCustomObject]@{ AccountId = ''; SubscriptionId = ''; SubscriptionName = '' }
        if (-not $ApiOnly) {
            Assert-EwModule -Name Az.Accounts
            $azureContext = Connect-EwAzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId `
                -UseDeviceAuthentication:$UseDeviceAuthentication
        }
        $script:ewNerdioSession.Context = [PSCustomObject]@{
            SessionId = [guid]::NewGuid().ToString()
            ApiOnly = [bool]$ApiOnly
            AccessToken = [string]$token.access_token
            TokenExpiresAt = [DateTimeOffset]::UtcNow.AddSeconds([double]$token.expires_in)
            TenantId = [string]$TenantId
            AccountId = $azureContext.AccountId
            SubscriptionId = $azureContext.SubscriptionId
            SubscriptionName = $azureContext.SubscriptionName
            NmeHost = $hostUri.Host
            ResourceGroupName = $ResourceGroupName
            StorageAccountName = $StorageAccountName
            ContainerName = $ContainerName
        }
        $script:ewNerdioSession.ApiOnly = [bool]$ApiOnly
        [PSCustomObject]@{
            Succeeded = $true
            SessionId = $script:ewNerdioSession.Context.SessionId
            ApiOnly = [bool]$ApiOnly
            AccountId = $script:ewNerdioSession.Context.AccountId
            TenantId = $TenantId
            SubscriptionId = $script:ewNerdioSession.Context.SubscriptionId
            SubscriptionName = $script:ewNerdioSession.Context.SubscriptionName
            NmeHost = $hostUri.Host
            ResourceGroupName = $ResourceGroupName
            StorageAccountName = $StorageAccountName
            ContainerName = $ContainerName
            Error = ''
        }
    }
    catch {
        $script:ewNerdioSession.Context = $null
        [PSCustomObject]@{
            Succeeded = $false
            AccountId = ''
            TenantId = ''
            SubscriptionId = ''
            SubscriptionName = ''
            NmeHost = ''
            Error = $_.Exception.Message
        }
    }
}
