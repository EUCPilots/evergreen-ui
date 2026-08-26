# Phase 5, Item 17: Start-EvergreenWorkbench Feature Registration Refactoring

## Overview

This document describes the refactoring of the 8,461-line `Start-EvergreenWorkbench` function into modular feature registration functions per item 17 of phase 5 in [plan-codebaseImprovements.prompt.md](.github/prompts/plan-codebaseImprovements.prompt.md).

## Goal

Split the monolithic `Start-EvergreenWorkbench` function by feature registration/orchestration while keeping the public function responsible for:
- STA enforcement
- Config/XAML startup
- Shared state construction  
- Feature orchestration
- Window lifetime management
- Final cleanup

## Architecture

### Orchestration Layer

**`Register-UIFeatures` (new Private function)**
- Entry point for feature registration orchestration
- Resolves all WPF control references from the loaded XAML
- Stores control references in `$SyncHash.Controls` hashtable for unified access
- Calls feature-specific registration functions in sequence
- Provides clear error handling and logging

### Feature Registration Layer

Each of the eight navigation views has a corresponding feature registration function:

1. **Register-AppsFeature.ps1**
   - Apps tab: app catalog browsing, search, filtering, version loading
   - Contains ~200 lines of helper scriptblocks and event handlers

2. **Register-DownloadFeature.ps1**
   - Download tab: queue display, item management, download execution
   - Integrates with the download workflow in `Invoke-AppDownload`

3. **Register-LibraryFeature.ps1**
   - Library tab: library path management, content display, updates
   - Delegates to `Invoke-LibraryUpdate` for Evergreen library operations

4. **Register-InstallFeature.ps1**
   - Install (Packages) tab: definition loading, version resolution, local installation
   - Coordinates with `Get-InstallPackageDefinitions`, `Test-LocalPackageDetection`, `Invoke-LocalPackageInstall`

5. **Register-ImportFeature.ps1** ⚠️ Most complex
   - Import tab with four sub-tabs:
     - **Intune Win32 Apps**: definition loading, building .intunewin, Graph API import
     - **Nerdio Manager Shell Apps**: shell app management, Azure blob upload
     - **Microsoft 365 Apps**: ODT config loading, M365 app packaging
     - **Authentication**: Entra ID signin (Connect-MgGraph), Azure signin (Connect-AzAccount)
   - Contains ~2,500 lines of helpers and event handlers in the current monolith

6. **Register-SettingsFeature.ps1**
   - Settings tab: theme selection, path configuration, cache/log management, feature toggles
   - Handles config persistence and folder browsing

7. **Register-NavigationFeature.ps1**
   - Navigation RadioButtons (Apps, Download, Library, Packages, Import, Install, Settings, Update, About)
   - Panel visibility switching
   - Nav toggle button (sidebar expand/collapse)

8. **Register-WindowLifetime.ps1**
   - `window.Loaded` event: startup initialization sequence
   - `window.Closed` event: cleanup and shutdown handling
   - Only handler managing both startup and shutdown

### Public Function Refactoring

**`Start-EvergreenWorkbench`** now:
1. Enforces STA thread (lines 14-25)
2. Loads dependencies and WPF assemblies (lines 27-48)
3. Loads config and module metadata (lines 50-115)
4. Loads and validates XAML (lines 280-312)
5. Resolves critical control names (lines 314-350)
6. Initializes $syncHash with state variables (lines 352-556)
7. Calls `Initialize-FeatureScopedState` for gradual refactoring (line 558)
8. **Calls `Register-UIFeatures` for event handler orchestration (NEW - line ~2462)**
9. Shows window blocking dialog (line ~8470+)

The call to `Register-UIFeatures` replaces the massive inline event handler registration code (formerly lines 2454-8450+). For now, the old code remains as a fallback, but will be removed after all feature registration functions are fully implemented.

## Implementation Pattern

Each feature registration function follows this pattern:

```powershell
function Register-[Feature]Feature {
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls from $Controls hashtable
    $buttonName = $Controls.ButtonName
    $listViewName = $Controls.ListViewName
    # ... other controls ...

    # Define helper scriptblocks
    $helperScriptblock1 = {
        # Logic for this helper
    }
    $SyncHash.HelperName = $helperScriptblock1  # Store in SyncHash for accessibility

    # Register event handlers
    $buttonName.add_Click({
        # Event handler logic
    })
    $listViewName.add_SelectionChanged({
        # Event handler logic
    })

    Write-Verbose "EvergreenUI: [Feature] feature registered."
}
```

### Key Patterns

1. **Control Access**: Use `$Controls.ControlName` to access resolved WPF controls
2. **State Storage**: Store helper scriptblocks and frequently-accessed state in `$SyncHash` with descriptive names
3. **Error Handling**: Use `Write-UILog` for user-facing messages, `Write-Verbose` for diagnostic logs
4. **Async Operations**: Use `New-WpfRunspace`, `$registerBackgroundOperation`, and completion actions (see existing code in Install/Import features)
5. **No Direct Control Scope Leaking**: Avoid capturing control references directly in closures; store them in `$SyncHash` or pass via parameters

## Migration Path

### Phase 1: Foundation (In Progress)
- ✅ Create `Register-UIFeatures` orchestrator
- ✅ Create all feature registration function stubs with documentation
- ✅ Insert call to `Register-UIFeatures` in public function
- ⏳ **Next**: Implement `Register-NavigationFeature` (simplest - only panel switching)

### Phase 2: Core Features
- Implement `Register-AppsFeature` (well-contained, ~200 lines)
- Implement `Register-DownloadFeature` (simple, ~50 lines)
- Implement `Register-LibraryFeature` (moderate, ~150 lines)
- Implement `Register-SettingsFeature` (moderate, ~200 lines)

### Phase 3: Complex Features
- Implement `Register-InstallFeature` (large, ~500 lines, coordinates multiple workflows)
- Implement `Register-WindowLifetime` (critical, handles startup/shutdown)

### Phase 4: Largest Feature
- Implement `Register-ImportFeature` (very large, ~2,500 lines, four sub-workflows + auth)
- Consider further decomposition of Import into sub-feature handlers

### Phase 5: Cleanup
- Remove legacy event handler code from `Start-EvergreenWorkbench` (lines 2454-8450+)
- Update tests to verify each feature works independently
- Update documentation

## Verification Checklist

When implementing each feature registration function:

- [ ] All event handlers for the feature are registered
- [ ] All helper scriptblocks are defined and stored in `$SyncHash` or local scope
- [ ] Controls are accessed via `$Controls` hashtable parameter, not direct scope capture
- [ ] `Write-UILog` calls for user-visible messages, `Write-Verbose` for diagnostics
- [ ] Async operations follow the `New-WpfRunspace` and `$registerBackgroundOperation` pattern
- [ ] No unhandled exceptions escape (use try/catch with appropriate logging)
- [ ] Feature functions are idempotent (safe to call multiple times)
- [ ] Verbose output logs feature registration completion
- [ ] All event handlers are tested with manual smoke tests

## Integration with Existing Code

All existing helper functions remain unchanged:
- `Get-UIConfig` / `Set-UIConfig` - Config persistence
- `Get-EvergreenAppList` - App catalog loading
- `New-WpfRunspace` - Runspace factory for async operations
- `Write-UILog` / `Write-UpdateOutput` - Logging to UI
- `Invoke-AppDownload`, `Invoke-LibraryUpdate`, `Invoke-IntunePackageBuild`, etc. - Workflow entry points
- Theme functions (`Set-LightTheme`, `Set-DarkTheme`) - Theme switching
- Prerequisite check functions - Module/elevation validation

Feature registration functions coordinate with these helpers and integrate their functionality into the UI event model.

## Testing Strategy

### Unit Tests
- Each feature registration function can be tested in isolation with mocked controls
- Verify event handlers are registered without errors
- Verify helper scriptblocks are properly defined

### Integration Tests
- Test each feature's workflow end-to-end:
  - Apps: search → select app → load versions → export CSV
  - Download: add items → browse output → clear queue
  - Library: select path → refresh → update library
  - Install: load definitions → resolve latest → apply
  - Import: select provider → authenticate → perform action (build/import)
  - Settings: change theme → change paths → verify persistence
  - Navigation: click nav buttons → verify panel switching
  - Lifecycle: startup → load state → shutdown → verify cleanup

### Regression Tests
- Verify all existing functionality continues to work with the new architecture
- Ensure no events are lost or double-registered during migration
- Validate async operation lifecycle (cancel, timeout, completion)

## Performance Considerations

- The refactoring does not change runtime performance; event handler registration and execution remain unchanged
- Memory footprint is equivalent (control references stored in `$SyncHash.Controls` instead of local scope)
- Startup time is unchanged (no additional module loading or initialization)

## Future Improvements

After this refactoring is complete, consider:

1. **Further decomposition of `Start-EvergreenWorkbench`**: Extract XAML loading, control resolution, and state initialization into separate functions
2. **XAML resource extraction**: Move styles and resource definitions out of the main XAML file into separate composable resource files
3. **State management consolidation**: Further structure `$SyncHash` into sub-objects for each feature (already begun with `Initialize-FeatureScopedState`)
4. **Event bus pattern**: Consider introducing a message-based event system for cross-feature communication (e.g., "auth state changed" → update all auth-dependent UI)
5. **Feature flags/registration**: Implement optional feature loading based on available module dependencies (e.g., load Import features only if Microsoft.Graph.Authentication is installed)

## References

- [Plan: Harden and streamline Evergreen Workbench](.github/prompts/plan-codebaseImprovements.prompt.md) - Phase 5, item 17
- `Start-EvergreenWorkbench.ps1` - Public function being refactored
- `Register-UIFeatures.ps1` - Orchestration function
- `Register-*Feature.ps1` - Feature-specific registration functions (8 files)
