# Feature-Scoped State Containers (Phase 4, Item 13)

## Overview

The `$syncHash` synchronized hashtable has been gradually refactored to use feature-scoped state containers while maintaining backward compatibility. This allows the monolithic state structure to be organized by feature without requiring a big-bang rename of every key.

## Structure

The `Initialize-FeatureScopedState` helper creates these nested containers within `$syncHash`:

```
$syncHash
├── Window, LogTextBox, VersionsListView, ... (UI controls - stay at root)
├── Config, ImportCurrentProvider, AzureAuthState, ... (shared config/auth - stay at root)
├── Operations
│   ├── Registry (keyed by feature/operation ID)
│   ├── PollingTimer
│   ├── ActiveCount
│   └── LastPolledAt
├── Install
│   ├── IsLoading
│   ├── DefinitionRows, Rows
│   ├── ActionButtonStates
│   ├── SortProperty, SortDirection
│   └── LatestVersionCache, LatestVersionCacheAge
├── Intune
│   ├── IsLoading
│   ├── DefinitionRows, Win32Rows, ComparisonRows
│   ├── ActionButtonStates, CompareHasRun
│   └── SortProperty, SortDirection
├── Nerdio
│   ├── IsShellAppsLoading, IsAddVersionLoading, IsPruneLoading, IsImportNewLoading
│   ├── DefinitionRows, ShellAppRows, ComparisonRows
│   ├── ActionButtonStates, CompareHasRun
│   ├── SortProperty, SortDirection
│   └── PostImportVerifyAppId, PostImportVerifyAppName, ...
└── M365
    ├── IsImportLoading, IsEvergreenLoading
    ├── ConfigRows, EvergreenRows
    ├── ActionButtonStates
    └── SortProperty, SortDirection
```

## Migration Strategy

### Phase 1: Initialization Only (Current)
- Feature-scoped containers are created but empty
- All existing code continues to use flat keys (e.g., `$syncHash.IsInstallLoading`)
- Backward compatibility: flat keys remain at root level until explicitly removed

### Phase 2: Selective Migration (By Workflow)
As each workflow is hardened with tests (per Phase 3), start using the nested containers:

1. Create tests for the workflow-specific state accessors
2. Update the workflow's functions to use the new nested structure
3. Verify all tests pass
4. Remove the old flat keys from that workflow

### Phase 3: Complete Refactoring
- All workflows use feature-scoped containers
- Old flat keys are removed
- Code is more maintainable and better organized

## Usage Examples

### Old Pattern (Flat Keys)
```powershell
$syncHash.IsInstallLoading = $true
$syncHash.InstallDefinitionRows = @()
$syncHash.InstallSortProperty = 'Name'
```

### New Pattern (Feature-Scoped)
```powershell
$syncHash.Install.IsLoading = $true
$syncHash.Install.DefinitionRows = @()
$syncHash.Install.SortProperty = 'Name'
```

## Workflow-Specific States

### Operations Container
Manages background operation lifecycle across all features:

```powershell
# Check if an operation is running
if ($syncHash.Operations.Registry.ContainsKey('Install.batch1')) {
    $op = $syncHash.Operations.Registry['Install.batch1']
    if ($null -ne $op.Async -and -not $op.Async.IsCompleted) {
        # Operation is still running
    }
}

# Register a new operation
$syncHash.Operations.Registry['Install.batch1'] = @{
    PowerShell = $ps
    Runspace   = $runspace
    Async      = $asyncResult
    Timer      = $timer
    Status     = 'Running'
}
```

### Install Container
Manages Install workflow state:

```powershell
# Toggle loading state
$syncHash.Install.IsLoading = $true

# Update data models
$syncHash.Install.DefinitionRows = $definitions
$syncHash.Install.Rows = $results

# Manage sorting
$syncHash.Install.SortProperty = 'Name'
$syncHash.Install.SortDirection = 'Ascending'

# Cache latest versions (batch optimization)
$syncHash.Install.LatestVersionCache = $cache
$syncHash.Install.LatestVersionCacheAge = [datetime]::Now
```

### Intune Container
Manages Intune workflow state:

```powershell
$syncHash.Intune.IsLoading = $true
$syncHash.Intune.DefinitionRows = $definitions
$syncHash.Intune.Win32Rows = $deployed
$syncHash.Intune.ComparisonRows = $comparison
$syncHash.Intune.CompareHasRun = $true
```

### Nerdio Container
Manages Nerdio Manager workflow state:

```powershell
$syncHash.Nerdio.IsShellAppsLoading = $true
$syncHash.Nerdio.DefinitionRows = $definitions
$syncHash.Nerdio.ShellAppRows = $apps
$syncHash.Nerdio.PostImportVerifyAppId = $appId
```

### M365 Container
Manages Microsoft 365 Apps workflow state:

```powershell
$syncHash.M365.IsImportLoading = $true
$syncHash.M365.ConfigRows = $configs
$syncHash.M365.EvergreenRows = $apps
```

## Backward Compatibility

**Important**: Flat keys are NOT automatically synchronized with feature-scoped containers. During the migration period, you must choose one pattern or the other for each piece of state.

Legacy flat keys that will eventually be removed:
```
Intune workflow:
  - PendingIntuneImportTimer → Intune.Operations.Timer
  - PendingIntuneImportPS → Intune.Operations.PowerShell
  - PendingIntuneImportRunspace → Intune.Operations.Runspace
  - PendingIntuneImportAsync → Intune.Operations.Async
  - IsIntuneImportLoading → Intune.IsLoading
  - IntuneDefinitionRows → Intune.DefinitionRows
  - IntuneWin32Rows → Intune.Win32Rows
  - IntuneCompareHasRun → Intune.CompareHasRun
  - IntuneComparisonRows → Intune.ComparisonRows
  - IntuneSortProperty → Intune.SortProperty
  - IntuneSortDirection → Intune.SortDirection
  - IntuneActionButtonStates → Intune.ActionButtonStates

Install workflow:
  - PendingInstallTimer → Operations.Registry['Install...'].Timer
  - PendingInstallPS → Operations.Registry['Install...'].PowerShell
  - PendingInstallRunspace → Operations.Registry['Install...'].Runspace
  - PendingInstallAsync → Operations.Registry['Install...'].Async
  - IsInstallLoading → Install.IsLoading
  - InstallDefinitionRows → Install.DefinitionRows
  - InstallRows → Install.Rows
  - InstallSortProperty → Install.SortProperty
  - InstallSortDirection → Install.SortDirection
  - InstallActionButtonStates → Install.ActionButtonStates

Nerdio workflow:
  - PendingNerdioShellAppsTimer → Operations.Registry['Nerdio.ShellApps'].Timer
  - PendingNerdioShellAppsPS → Operations.Registry['Nerdio.ShellApps'].PowerShell
  - PendingNerdioShellAppsRunspace → Operations.Registry['Nerdio.ShellApps'].Runspace
  - PendingNerdioShellAppsAsync → Operations.Registry['Nerdio.ShellApps'].Async
  - IsNerdioShellAppsLoading → Nerdio.IsShellAppsLoading
  - (similar for Add, Prune, ImportNew operations)
  - NerdioSortProperty → Nerdio.SortProperty
  - NerdioSortDirection → Nerdio.SortDirection

M365 workflow:
  - PendingM365ImportTimer → Operations.Registry['M365.Import'].Timer
  - PendingM365ImportPS → Operations.Registry['M365.Import'].PowerShell
  - PendingM365ImportRunspace → Operations.Registry['M365.Import'].Runspace
  - PendingM365ImportAsync → Operations.Registry['M365.Import'].Async
  - IsM365ImportLoading → M365.IsImportLoading
  - (similar for M365 Evergreen operation)
  - M365SortProperty → M365.SortProperty
  - M365SortDirection → M365.SortDirection
```

## Testing Strategy

When migrating a workflow:

1. Write unit tests for the new nested structure
2. Update the workflow's functions to use the nested containers
3. Verify all existing tests still pass
4. Remove the old flat keys from `Start-EvergreenWorkbench.ps1` initialization
5. Remove any usage of the flat keys in the workflow's functions

## Notes

- WPF control references (Window, LogTextBox, VersionsListView, etc.) remain at the root level for simplicity
- Shared authentication state (AzureAuthState, NerdioApiAuthState, NerdioAzureAuthState) remains at the root for now
- The `Operations` container will eventually consolidate all background operation management across features
- Each feature container is independently synchronized, allowing safe concurrent access from background runspaces
