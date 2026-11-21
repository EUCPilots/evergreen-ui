Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EwNerdio {
    <#
    .SYNOPSIS
        Connects to Azure and authenticates to Nerdio Manager.
    .DESCRIPTION
        Uses Az.Accounts for the selected Azure subscription and a client
        credentials token for Nerdio Manager API calls. The client secret and
        tokens remain in memory and are not written to settings.
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
    .EXAMPLE
        Connect-EwNerdio -TenantId $tenant -SubscriptionId $subscription `
            -ClientId $clientId -ClientSecret (Read-Host -AsSecureString) `
            -ApiScope $scope -NmeHost 'nme.contoso.com' `
            -ResourceGroupName 'apps' -StorageAccountName 'packages' -ContainerName 'shell-apps'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Az.Accounts and an accessible Nerdio Manager API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ContainerName,

        [Parameter()]
        [string]$OAuthTokenUrl,

        [Parameter()]
        [switch]$UseDeviceAuthentication
    )

    try {
        $hostUri = if ($NmeHost -match '^https://') { [uri]$NmeHost } else { [uri]("https://$($NmeHost.Trim('/'))") }
        if ($hostUri.Scheme -ne 'https' -or -not [string]::IsNullOrWhiteSpace($hostUri.PathAndQuery.Trim('/'))) {
            throw 'NmeHost must be a host name or HTTPS origin without a path.'
        }
        $token = Get-EwNerdioAccessToken -TenantId $TenantId -ClientId $ClientId `
            -ClientSecret $ClientSecret -ApiScope $ApiScope -OAuthTokenUrl $OAuthTokenUrl
        Assert-EwModule -Name Az.Accounts
        $connectParameters = @{ Tenant = $TenantId; ErrorAction = 'Stop' }
        if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
            $connectParameters.Subscription = $SubscriptionId
        }
        if ($UseDeviceAuthentication) {
            $connectParameters.UseDeviceAuthentication = $true
        }
        Connect-AzAccount @connectParameters | Out-Null
        $azureContext = Get-AzContext -ErrorAction Stop
        $script:ewNerdioContext = [PSCustomObject]@{
            AccessToken = [string]$token.access_token
            TokenExpiresAt = [DateTimeOffset]::UtcNow.AddSeconds([double]$token.expires_in)
            TenantId = [string]$TenantId
            AccountId = if ($null -ne $azureContext.Account) { [string]$azureContext.Account.Id } else { '' }
            SubscriptionId = if ($null -ne $azureContext.Subscription) { [string]$azureContext.Subscription.Id } else { [string]$SubscriptionId }
            SubscriptionName = if ($null -ne $azureContext.Subscription) { [string]$azureContext.Subscription.Name } else { '' }
            NmeHost = $hostUri.Host
            ResourceGroupName = $ResourceGroupName
            StorageAccountName = $StorageAccountName
            ContainerName = $ContainerName
        }
        [PSCustomObject]@{
            Succeeded = $true
            AccountId = $script:ewNerdioContext.AccountId
            TenantId = $TenantId
            SubscriptionId = $script:ewNerdioContext.SubscriptionId
            SubscriptionName = $script:ewNerdioContext.SubscriptionName
            NmeHost = $hostUri.Host
            Error = ''
        }
    }
    catch {
        $script:ewNerdioContext = $null
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
