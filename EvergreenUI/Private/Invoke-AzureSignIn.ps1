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
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [System.Collections.Hashtable]$SyncHash
    )

    $authSyncHash = $SyncHash

    $protectLogValue = {
        param([AllowNull()][string]$Value)

        if ([string]::IsNullOrEmpty($Value)) {
            return $Value
        }

        $safeValue = [regex]::Replace(
            $Value,
            '(?i)\b(access_token|refresh_token|id_token|client_secret)\b\s*[:=]\s*[^\s,;]+',
            '$1=[REDACTED]'
        )
        $safeValue = [regex]::Replace($safeValue, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]')
        $safeValue = [regex]::Replace($safeValue, '\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b', '[REDACTED JWT]')
        return $safeValue
    }

    $writeAuthLog = {
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet('Info', 'Warning', 'Error')]
            [string]$Level = 'Info'
        )

        $safeMessage = & $protectLogValue -Value $Message
        Write-Verbose -Message "EvergreenUI: Entra authentication: $safeMessage"

        if ($null -ne $authSyncHash -and $null -ne (Get-Command -Name Write-UILog -ErrorAction SilentlyContinue)) {
            try {
            Write-UILog -SyncHash $authSyncHash -Message "Entra authentication: $safeMessage" -Level $Level
            }
            catch {
                # best-effort - authentication must continue if UI logging is unavailable during shutdown
                Write-Verbose -Message "EvergreenUI: Entra authentication UI logging failed (ignored): $($_.Exception.Message)"
            }
        }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $tenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { $null } else { $TenantId.Trim() }
        $accountId = ''
        # Local name must differ from $TenantId: PowerShell variable names are case-insensitive.
        $resolvedTenantId = if ($null -eq $tenant) { '' } else { [string]$tenant }
        $authMethod = 'Connect-MgGraph'
        $powerShellEdition = if ($PSVersionTable.ContainsKey('PSEdition')) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
        $apartmentState = [System.Threading.Thread]::CurrentThread.ApartmentState
        $processArchitecture = if ([System.Environment]::Is64BitProcess) { 'x64' } else { 'x86' }

        & $writeAuthLog -Message "Starting interactive sign-in. PowerShell=$($PSVersionTable.PSVersion) ($powerShellEdition); process=$processArchitecture; apartment=$apartmentState; tenant=$(if ($null -eq $tenant) { '<organization default>' } else { $tenant })."

        # Intune workflows should use Microsoft Graph interactive auth so the
        # sign-in button opens the browser flow instead of prompting for a client ID.
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience if
        # called before tab initialization.
        $graphModule = Get-Module -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $graphModule) {
            $availableModule = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1
            $availableDescription = if ($null -eq $availableModule) {
                'not found in PSModulePath'
            }
            else {
                "version $($availableModule.Version) at '$($availableModule.Path)'"
            }
            & $writeAuthLog -Message "Microsoft.Graph.Authentication is not loaded; discovered $availableDescription. Importing module."
            Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
            $graphModule = Get-Module -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue | Select-Object -First 1
        }

        if ($null -ne $graphModule) {
            & $writeAuthLog -Message "Microsoft.Graph.Authentication loaded: version $($graphModule.Version) from '$($graphModule.Path)'."
        }

        $connectCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
        if ($null -eq $connectCommand) {
            throw 'Connect-MgGraph is not available. Install Microsoft.Graph.Authentication.'
        }
        & $writeAuthLog -Message "Connect-MgGraph resolved as $($connectCommand.CommandType) from module '$($connectCommand.Source)' version $($connectCommand.Version)."

        $mgParams = @{
            Scopes       = @('DeviceManagementApps.ReadWrite.All')
            ContextScope = 'Process'
            NoWelcome    = $true
            ErrorAction  = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($tenant)) {
            $mgParams['TenantId'] = $tenant
        }

        & $writeAuthLog -Message "Invoking Connect-MgGraph with scopes '$($mgParams.Scopes -join ', ')', ContextScope=Process, NoWelcome=True, and explicit tenant=$($mgParams.ContainsKey('TenantId'))."
        Connect-MgGraph @mgParams | Out-Null
        & $writeAuthLog -Message "Connect-MgGraph completed after $($stopwatch.ElapsedMilliseconds) ms; reading non-secret Graph context metadata."

        if (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue) {
            $mgContext = Get-MgContext -ErrorAction SilentlyContinue
            if ($null -ne $mgContext) {
                if ($mgContext.PSObject.Properties.Name -contains 'Account' -and -not [string]::IsNullOrWhiteSpace([string]$mgContext.Account)) {
                    $accountId = [string]$mgContext.Account
                }
                if ($mgContext.PSObject.Properties.Name -contains 'TenantId' -and -not [string]::IsNullOrWhiteSpace([string]$mgContext.TenantId)) {
                    $resolvedTenantId = [string]$mgContext.TenantId
                }

                $contextScope = if ($mgContext.PSObject.Properties.Name -contains 'ContextScope') { [string]$mgContext.ContextScope } else { '<not reported>' }
                $authType = if ($mgContext.PSObject.Properties.Name -contains 'AuthType') { [string]$mgContext.AuthType } else { '<not reported>' }
                $grantedScopes = if ($mgContext.PSObject.Properties.Name -contains 'Scopes') { @($mgContext.Scopes) -join ', ' } else { '<not reported>' }
                & $writeAuthLog -Message "Graph context confirmed: tenant='$resolvedTenantId'; account='$accountId'; ContextScope=$contextScope; AuthType=$authType; granted scopes='$grantedScopes'."
            }
            else {
                & $writeAuthLog -Message 'Connect-MgGraph returned successfully, but Get-MgContext returned no context.' -Level Warning
            }
        }
        else {
            & $writeAuthLog -Message 'Get-MgContext is unavailable; account and tenant metadata could not be confirmed.' -Level Warning
        }

        & $writeAuthLog -Message "Interactive sign-in completed successfully in $($stopwatch.ElapsedMilliseconds) ms."

        return [PSCustomObject]@{
            Succeeded          = $true
            AccountId          = $accountId
            TenantId           = $resolvedTenantId
            SubscriptionName   = ''
            AuthMethod         = $authMethod
            ErrorMessage       = ''
            IntuneConnected    = $true
            IntuneConnectError = ''
        }
    }
    catch {
        $safeErrorMessage = & $protectLogValue -Value $_.Exception.Message
        $errorType = $_.Exception.GetType().FullName
        $errorId = & $protectLogValue -Value $_.FullyQualifiedErrorId
        $errorCategory = [string]$_.CategoryInfo.Category
        & $writeAuthLog -Message "Interactive sign-in failed after $($stopwatch.ElapsedMilliseconds) ms. Exception=$errorType; ErrorId='$errorId'; Category=$errorCategory; Message='$safeErrorMessage'." -Level Error
        if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
            $safeStackTrace = & $protectLogValue -Value $_.ScriptStackTrace
            & $writeAuthLog -Message "Failure script stack: $safeStackTrace" -Level Error
        }

        return [PSCustomObject]@{
            Succeeded          = $false
            AccountId          = ''
            TenantId           = ''
            SubscriptionName   = ''
            AuthMethod         = ''
            ErrorMessage       = $safeErrorMessage
            IntuneConnected    = $false
            IntuneConnectError = $safeErrorMessage
        }
    }
    finally {
        $stopwatch.Stop()
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
        Write-Verbose -Message "EvergreenUI: Disconnect-MgGraph failed (ignored): $($_.Exception.Message)"
    }

    try {
        # Also clear Az context if present so the previous behavior stays clean.
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience.
        if (-not (Get-Module -Name Az.Accounts -ErrorAction SilentlyContinue)) {
            Import-Module -Name Az.Accounts -ErrorAction SilentlyContinue | Out-Null
        }
        Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # best-effort - sign-out must never block UI flow
        Write-Verbose -Message "EvergreenUI: Az sign-out step failed (ignored): $($_.Exception.Message)"
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
        # Az modules are pre-loaded by $loadImportTabModules; guards ensure resilience
        # if called before tab initialization.
        Write-Verbose 'EvergreenUI: Ensuring Az.Accounts, Az.Resources, Az.Storage are loaded...'
        foreach ($mod in @('Az.Accounts', 'Az.Resources', 'Az.Storage')) {
            if (-not (Get-Module -Name $mod -ErrorAction SilentlyContinue)) {
                Import-Module -Name $mod -ErrorAction SilentlyContinue | Out-Null
            }
        }
        Write-Verbose -Message "EvergreenUI: Connect-AzAccount available: $(($null -ne (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)))"

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
                Write-Verbose -Message "EvergreenUI: Update-AzConfig step failed (ignored): $($_.Exception.Message)"
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
                Write-Verbose -Message "EvergreenUI: Enable-AzContextAutosave failed (ignored): $($_.Exception.Message)"
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
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience.
        if (-not (Get-Module -Name Az.Accounts -ErrorAction SilentlyContinue)) {
            Import-Module -Name Az.Accounts -ErrorAction SilentlyContinue | Out-Null
        }
        Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext     -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # best-effort - sign-out must never block UI flow
        Write-Verbose -Message "EvergreenUI: Nerdio Az sign-out step failed (ignored): $($_.Exception.Message)"
    }
}

function Get-NerdioAzureResourceGroup {
    [CmdletBinding()]
    param()
    try {
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience.
        if (-not (Get-Module -Name Az.Resources -ErrorAction SilentlyContinue)) {
            Import-Module -Name Az.Resources -ErrorAction SilentlyContinue | Out-Null
        }
        $groups = Get-AzResourceGroup -ErrorAction Stop
        return @($groups | Sort-Object ResourceGroupName | Select-Object -ExpandProperty ResourceGroupName)
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Get-NerdioAzureResourceGroup failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}

function Get-NerdioAzureStorageAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    try {
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience.
        if (-not (Get-Module -Name Az.Storage -ErrorAction SilentlyContinue)) {
            Import-Module -Name Az.Storage -ErrorAction SilentlyContinue | Out-Null
        }
        $accounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        return @($accounts | Sort-Object StorageAccountName | Select-Object -ExpandProperty StorageAccountName)
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Get-NerdioAzureStorageAccount failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}

function Get-NerdioAzureStorageContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName
    )
    try {
        # Module is pre-loaded by $loadImportTabModules; guard ensures resilience.
        if (-not (Get-Module -Name Az.Storage -ErrorAction SilentlyContinue)) {
            Import-Module -Name Az.Storage -ErrorAction SilentlyContinue | Out-Null
        }
        $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        $containers = Get-AzStorageContainer -Context $sa.Context -ErrorAction Stop
        return @($containers | Sort-Object Name | Select-Object -ExpandProperty Name)
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Get-NerdioAzureStorageContainer failed (returning empty list): $($_.Exception.Message)"
        return @()
    }
}
