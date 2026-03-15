#Requires -Version 5.1
<#+
.SYNOPSIS
    Handles interactive Azure/Entra sign-in and sign-out for Import workflows.

.DESCRIPTION
    Uses Az.Accounts to open an interactive Microsoft sign-in experience and
    returns normalized non-secret session metadata for the UI layer.
#>

function Invoke-AzureSignIn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    try {
        Import-Module Az.Accounts -ErrorAction Stop | Out-Null

        $tenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { $null } else { $TenantId.Trim() }
        if ([string]::IsNullOrWhiteSpace($tenant)) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        else {
            Connect-AzAccount -Tenant $tenant -ErrorAction Stop | Out-Null
        }

        $ctx = Get-AzContext -ErrorAction Stop
        return [PSCustomObject]@{
            Succeeded        = $true
            AccountId        = [string]$ctx.Account.Id
            TenantId         = [string]$ctx.Tenant.Id
            SubscriptionName = [string]$ctx.Subscription.Name
            ErrorMessage     = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            Succeeded        = $false
            AccountId        = ''
            TenantId         = ''
            SubscriptionName = ''
            ErrorMessage     = $_.Exception.Message
        }
    }
}

function Invoke-AzureSignOut {
    [CmdletBinding()]
    param()

    try {
        Import-Module Az.Accounts -ErrorAction Stop | Out-Null
        Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # Sign-out should be best-effort and never block UI flow.
    }
}
