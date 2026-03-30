#Requires -Version 5.1
<#+
.SYNOPSIS
    Handles interactive Entra sign-in and sign-out for Import workflows.

.DESCRIPTION
    Uses Microsoft Graph PowerShell interactive authentication and returns
    normalized non-secret session metadata for the UI layer.
#>

function Invoke-AzureSignIn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    try {
        $tenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { $null } else { $TenantId.Trim() }
        $accountId = ''
        $tenantId = if ($null -eq $tenant) { '' } else { [string]$tenant }
        $authMethod = 'Connect-MgGraph'

        # Intune workflows should use Microsoft Graph interactive auth so the
        # sign-in button opens the browser flow instead of prompting for a client ID.
        Write-Verbose 'EvergreenUI: Importing Microsoft.Graph.Authentication...'
        Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue | Out-Null
        Write-Verbose "EvergreenUI: Connect-MgGraph available: $(($null -ne (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)))"

        if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
            throw 'Connect-MgGraph is not available. Install Microsoft.Graph.Authentication.'
        }

        $mgParams = @{
            Scopes       = @('DeviceManagementApps.ReadWrite.All')
            ContextScope = 'Process'
            NoWelcome    = $true
            ErrorAction  = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($tenant)) {
            $mgParams['TenantId'] = $tenant
        }

        Connect-MgGraph @mgParams | Out-Null

        if (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue) {
            $mgContext = Get-MgContext -ErrorAction SilentlyContinue
            if ($null -ne $mgContext) {
                if ($mgContext.PSObject.Properties.Name -contains 'Account' -and -not [string]::IsNullOrWhiteSpace([string]$mgContext.Account)) {
                    $accountId = [string]$mgContext.Account
                }
                if ($mgContext.PSObject.Properties.Name -contains 'TenantId' -and -not [string]::IsNullOrWhiteSpace([string]$mgContext.TenantId)) {
                    $tenantId = [string]$mgContext.TenantId
                }
            }
        }

        return [PSCustomObject]@{
            Succeeded          = $true
            AccountId          = $accountId
            TenantId           = $tenantId
            SubscriptionName   = ''
            AuthMethod         = $authMethod
            ErrorMessage       = ''
            IntuneConnected    = $true
            IntuneConnectError = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            Succeeded          = $false
            AccountId          = ''
            TenantId           = ''
            SubscriptionName   = ''
            AuthMethod         = ''
            ErrorMessage       = $_.Exception.Message
            IntuneConnected    = $false
            IntuneConnectError = $_.Exception.Message
        }
    }
}

function Invoke-AzureSignOut {
    [CmdletBinding()]
    param()

    try {
        if (Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        # best-effort - sign-out must never block UI flow
        Write-Verbose "EvergreenUI: Disconnect-MgGraph failed (ignored): $($_.Exception.Message)"
    }

    try {
        # Also clear Az context if present so the previous behavior stays clean.
        Import-Module Az.Accounts -ErrorAction SilentlyContinue | Out-Null
        Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # best-effort - sign-out must never block UI flow
        Write-Verbose "EvergreenUI: Az sign-out step failed (ignored): $($_.Exception.Message)"
    }
}

function Invoke-NerdioAzureSignIn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    try {
        Write-Verbose 'EvergreenUI: Importing Az.Accounts, Az.Resources, Az.Storage...'
        Import-Module Az.Accounts   -ErrorAction SilentlyContinue | Out-Null
        Import-Module Az.Resources  -ErrorAction SilentlyContinue | Out-Null
        Import-Module Az.Storage    -ErrorAction SilentlyContinue | Out-Null
        Write-Verbose "EvergreenUI: Connect-AzAccount available: $(($null -ne (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)))"

        if (-not (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)) {
            throw 'Connect-AzAccount is not available. Install the Az.Accounts module.'
        }

        $sub = $SubscriptionId.Trim()
        $tenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { $null } else { $TenantId.Trim() }

        if (Get-Command -Name Update-AzConfig -ErrorAction SilentlyContinue) {
            try {
                Update-AzConfig -EnableLoginByWam $false -Scope Process -AppliesTo Az -ErrorAction Stop | Out-Null
                Update-AzConfig -LoginExperienceV2 Off -Scope Process -AppliesTo Az -ErrorAction Stop | Out-Null
                Update-AzConfig -DefaultSubscriptionForLogin $sub -Scope Process -AppliesTo Az -ErrorAction Stop | Out-Null
            }
            catch {
                # best-effort - older Az.Accounts builds may not support all process-scoped settings
                Write-Verbose "EvergreenUI: Update-AzConfig step failed (ignored): $($_.Exception.Message)"
            }
        }

        # Ensure the Az context is persisted to disk so that background runspaces
        # (used for blob upload during add-version / new Shell App operations)
        # can load it when they import Az.Accounts.
        if (Get-Command -Name Enable-AzContextAutosave -ErrorAction SilentlyContinue) {
            try {
                Enable-AzContextAutosave -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                # best-effort - default is already enabled; failure here is non-blocking
                Write-Verbose "EvergreenUI: Enable-AzContextAutosave failed (ignored): $($_.Exception.Message)"
            }
        }

        # Passing -Subscription avoids the interactive subscription-picker prompt
        # that would otherwise block the UI thread.
        $connectParams = @{
            Subscription = $sub
            ErrorAction  = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($tenant)) {
            $connectParams['Tenant'] = $tenant
        }

        Connect-AzAccount @connectParams | Out-Null

        $ctx = Get-AzContext -ErrorAction SilentlyContinue

        $accountId = if ($null -ne $ctx -and $null -ne $ctx.Account) { [string]$ctx.Account.Id }      else { '' }
        $resolvedTenant = if ($null -ne $ctx -and $null -ne $ctx.Tenant) { [string]$ctx.Tenant.Id }       else { if ($null -eq $tenant) { '' } else { $tenant } }
        $subscriptionName = if ($null -ne $ctx -and $null -ne $ctx.Subscription) { [string]$ctx.Subscription.Name } else { '' }

        return [PSCustomObject]@{
            Succeeded        = $true
            AccountId        = $accountId
            TenantId         = $resolvedTenant
            SubscriptionName = $subscriptionName
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

function Invoke-NerdioAzureSignOut {
    [CmdletBinding()]
    param()

    try {
        Import-Module Az.Accounts -ErrorAction SilentlyContinue | Out-Null
        Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext     -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # best-effort - sign-out must never block UI flow
        Write-Verbose "EvergreenUI: Nerdio Az sign-out step failed (ignored): $($_.Exception.Message)"
    }
}

function Get-NerdioAzureResourceGroups {
    [CmdletBinding()]
    param()
    try {
        Import-Module Az.Resources -ErrorAction SilentlyContinue | Out-Null
        $groups = Get-AzResourceGroup -ErrorAction Stop
        return @($groups | Sort-Object ResourceGroupName | Select-Object -ExpandProperty ResourceGroupName)
    }
    catch {
        Write-Verbose "EvergreenUI: Get-NerdioAzureResourceGroups failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}

function Get-NerdioAzureStorageAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    try {
        Import-Module Az.Storage -ErrorAction SilentlyContinue | Out-Null
        $accounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        return @($accounts | Sort-Object StorageAccountName | Select-Object -ExpandProperty StorageAccountName)
    }
    catch {
        Write-Verbose "EvergreenUI: Get-NerdioAzureStorageAccounts failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}

function Get-NerdioAzureStorageContainers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName
    )
    try {
        Import-Module Az.Storage -ErrorAction SilentlyContinue | Out-Null
        $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        $containers = Get-AzStorageContainer -Context $sa.Context -ErrorAction Stop
        return @($containers | Sort-Object Name | Select-Object -ExpandProperty Name)
    }
    catch {
        Write-Verbose "EvergreenUI: Get-NerdioAzureStorageContainers failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}
