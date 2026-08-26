<#
.SYNOPSIS
    Initialize feature-scoped state containers within the synchronized hash.

.DESCRIPTION
    Creates nested feature-scoped state containers (Operations, Install, Intune, Nerdio, M365)
    within the shared $syncHash to gradually organize related workflow state.
    
    This helper supports incremental refactoring of the monolithic $syncHash without
    requiring a big-bang rename of every key. Legacy flat keys remain available for
    backward compatibility; only remove them after each workflow's tests pass.

.PARAMETER SyncHash
    The synchronized hashtable containing shared UI state and runspace communication.

.NOTES
    Called early during Start-EvergreenWorkbench initialization after $syncHash creation
    but before XAML loading and event handlers.
#>
function Initialize-FeatureScopedState {
    param([hashtable]$SyncHash)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Operations: Background operation lifecycle and registry
    if (-not $SyncHash.ContainsKey('Operations')) {
        $SyncHash.Operations = @{
            # The primary registry: keyed by feature/operation ID
            # Structure: @{ 'Install.batch1' = @{ PowerShell = ..., Runspace = ..., Async = ..., Timer = ..., Status = ... }, ... }
            Registry            = [hashtable]::Synchronized(@{})
            
            # Timer for polling all active operations (shared across features)
            PollingTimer        = $null
            
            # Counters and state for the UI
            ActiveCount         = 0
            LastPolledAt        = [datetime]::MinValue
        }
    }

    # Install: Install workflow state
    if (-not $SyncHash.ContainsKey('Install')) {
        $SyncHash.Install = @{
            # UI state
            IsLoading           = $false
            
            # Data models
            DefinitionRows      = @()
            Rows                = @()
            ActionButtonStates  = @{}
            
            # Sorting
            SortProperty        = ''
            SortDirection       = 'Ascending'
            
            # Latest-version resolution cache (for batch operations)
            LatestVersionCache  = @{}
            LatestVersionCacheAge = [datetime]::MinValue
        }
    }

    # Intune: Intune workflow state
    if (-not $SyncHash.ContainsKey('Intune')) {
        $SyncHash.Intune = @{
            # UI state
            IsLoading           = $false
            
            # Data models
            DefinitionRows      = @()
            Win32Rows           = @()
            ComparisonRows      = @()
            ActionButtonStates  = @{}
            
            # Comparison state
            CompareHasRun       = $false
            
            # Sorting
            SortProperty        = ''
            SortDirection       = 'Ascending'
            
            # Authentication state (shared with root level for now)
            # Will reference $SyncHash.AzureAuthState
        }
    }

    # Nerdio: Nerdio Manager workflow state
    if (-not $SyncHash.ContainsKey('Nerdio')) {
        $SyncHash.Nerdio = @{
            # UI state
            IsShellAppsLoading  = $false
            IsAddVersionLoading = $false
            IsPruneLoading      = $false
            IsImportNewLoading  = $false
            
            # Data models
            DefinitionRows      = @()
            ShellAppRows        = @()
            ComparisonRows      = @()
            SelectedComparisonRow = $null
            ActionButtonStates  = @{}
            
            # Comparison state
            CompareHasRun       = $false
            
            # Sorting
            SortProperty        = ''
            SortDirection       = 'Ascending'
            
            # Post-import verification context
            PostImportVerifyAppId = ''
            PostImportVerifyAppName = ''
            PostImportExpectedEvergreenVersion = ''
            
            # Pending operation context (for single app operations)
            PendingPruneAppName = ''
            PendingImportNewAppName = ''
            
            # Authentication state (shared with root level for now)
            # Will reference $SyncHash.NerdioApiAuthState and $SyncHash.NerdioAzureAuthState
        }
    }

    # M365: Microsoft 365 Apps workflow state
    if (-not $SyncHash.ContainsKey('M365')) {
        $SyncHash.M365 = @{
            # UI state
            IsImportLoading     = $false
            IsEvergreenLoading  = $false
            
            # Data models
            ConfigRows          = @()
            EvergreenRows       = @()
            ActionButtonStates  = @{}
            
            # Sorting
            SortProperty        = ''
            SortDirection       = 'Ascending'
        }
    }

    Write-Verbose -Message 'EvergreenUI: Initialized feature-scoped state containers.'
}
