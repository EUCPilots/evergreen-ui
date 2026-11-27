Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EwAzAccount {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [switch]$UseDeviceAuthentication
    )

    $valueOf = {
        param([object]$Object, [string]$Path)
        $current = $Object
        foreach ($name in $Path.Split('.')) {
            if ($null -eq $current -or $null -eq $current.PSObject.Properties[$name]) {
                return ''
            }
            $current = $current.PSObject.Properties[$name].Value
        }
        [string]$current
    }
    $describe = {
        param([object]$Context)
        [PSCustomObject]@{
            AccountId = & $valueOf -Object $Context -Path 'Account.Id'
            TenantId = & $valueOf -Object $Context -Path 'Tenant.Id'
            SubscriptionId = & $valueOf -Object $Context -Path 'Subscription.Id'
            SubscriptionName = & $valueOf -Object $Context -Path 'Subscription.Name'
        }
    }

    Assert-EwModule -Name Az.Accounts
    $existing = & $describe -Context (Get-AzContext -ErrorAction SilentlyContinue)
    $tenantMatches = [string]::IsNullOrWhiteSpace($TenantId) -or $existing.TenantId -ieq $TenantId.Trim()
    $subscriptionMatches = [string]::IsNullOrWhiteSpace($SubscriptionId) -or $existing.SubscriptionId -ieq $SubscriptionId.Trim()
    if (-not [string]::IsNullOrWhiteSpace($existing.AccountId) -and
        -not [string]::IsNullOrWhiteSpace($existing.TenantId) -and $tenantMatches -and $subscriptionMatches) {
        try {
            $null = Get-AzAccessToken -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Reusing Azure context for '$($existing.AccountId)' in tenant '$($existing.TenantId)'"
            return $existing
        }
        catch {
            if ($_.Exception.Message -notmatch 'Your Azure credentials have not been set up or have expired') {
                throw
            }
            Write-Verbose -Message 'EvergreenUI: Cached Azure credentials are unavailable or expired; requesting sign-in'
        }
    }

    $parameters = @{ ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $parameters.Tenant = $TenantId.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $parameters.Subscription = $SubscriptionId.Trim()
    }
    if ($UseDeviceAuthentication) {
        $parameters.UseDeviceAuthentication = $true
    }
    Write-Verbose -Message 'EvergreenUI: Calling Connect-AzAccount'
    Connect-AzAccount @parameters | Out-Null
    $connected = & $describe -Context (Get-AzContext -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($connected.TenantId)) {
        $connected.TenantId = [string]$TenantId
    }
    if ([string]::IsNullOrWhiteSpace($connected.SubscriptionId)) {
        $connected.SubscriptionId = [string]$SubscriptionId
    }
    Write-Verbose -Message "EvergreenUI: Azure sign-in completed for '$($connected.AccountId)'"
    return $connected
}
