Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Sync-EwNerdioStorageContext {
    [CmdletBinding(DefaultParameterSetName = 'Attach')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Attach')][psobject]$Identity,
        [Parameter(Mandatory, ParameterSetName = 'Attach')][psobject]$Destination,
        [Parameter(Mandatory, ParameterSetName = 'Attach')][string]$ResourceGroupName,
        [Parameter(Mandatory, ParameterSetName = 'Attach')][string]$StorageAccountName,
        [Parameter(Mandatory, ParameterSetName = 'Attach')][string]$ContainerName,
        [Parameter(Mandatory, ParameterSetName = 'Detach')][switch]$Detach
    )

    $context = if ($Detach) { $script:ewNerdioSession.Context } else { Get-EwNerdioSessionContext }
    if ($null -eq $context) { return }
    if (-not $Detach) {
        if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($StorageAccountName) -or
            [string]::IsNullOrWhiteSpace($ContainerName) -or [string]::IsNullOrWhiteSpace([string]$Destination.SessionId) -or
            $context.SessionId -ne $Destination.SessionId -or $context.NmeHost -ine $Destination.NmeHost) {
            throw 'The Nerdio connection or Azure storage selection changed. Reconnect or select storage again.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$Identity.TenantId) -or
            [string]::IsNullOrWhiteSpace([string]$Identity.SubscriptionId) -or $context.TenantId -ine $Identity.TenantId) {
            throw 'The Nerdio and Azure tenants do not match. Connect both to the same tenant.'
        }
        Assert-EwAzureIdentity -Identity $Identity
        if (-not [object]::ReferenceEquals($script:ewNerdioSession.Context, $context)) {
            throw 'The Nerdio connection changed. Connect Nerdio again.'
        }
    }

    $updated = [PSCustomObject]@{
        SessionId = [guid]::NewGuid().ToString()
        ApiOnly = [bool]$Detach
        AccessToken = $context.AccessToken
        TokenExpiresAt = $context.TokenExpiresAt
        TenantId = $context.TenantId
        AccountId = if ($Detach) { '' } else { [string]$Identity.AccountId }
        SubscriptionId = if ($Detach) { '' } else { [string]$Identity.SubscriptionId }
        SubscriptionName = if ($Detach) { '' } else { [string]$Identity.SubscriptionName }
        NmeHost = $context.NmeHost
        ResourceGroupName = if ($Detach) { '' } else { $ResourceGroupName }
        StorageAccountName = if ($Detach) { '' } else { $StorageAccountName }
        ContainerName = if ($Detach) { '' } else { $ContainerName }
    }
    $script:ewNerdioSession.Context = $updated
    $script:ewNerdioSession.ApiOnly = [bool]$Detach
    [PSCustomObject]@{
        Succeeded = $true
        SessionId = $updated.SessionId
        ApiOnly = $updated.ApiOnly
        TenantId = $updated.TenantId
        AccountId = $updated.AccountId
        SubscriptionId = $updated.SubscriptionId
        SubscriptionName = $updated.SubscriptionName
        NmeHost = $updated.NmeHost
        ResourceGroupName = $updated.ResourceGroupName
        StorageAccountName = $updated.StorageAccountName
        ContainerName = $updated.ContainerName
        Error = ''
    }
}
