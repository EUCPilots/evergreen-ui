# Evergreen Workbench Nerdio Manager Reimplementation Plan

Last verified: 2026-03-15
Source of truth: current implementation in EvergreenUI module

## Goal

Re-implement the current Nerdio Manager support exactly as it exists today, including:
- Nerdio connection and session validation
- Import panel behavior (Nerdio provider workflow)
- Settings tab Nerdio fields and persistence behavior
- Dry-run then apply flow for import and prune operations

This plan is implementation-oriented and maps directly to existing UI controls, config keys, and PowerShell functions.

## Scope

In scope:
- Import provider switch behavior (Nerdio and Intune placeholder)
- Nerdio definitions discovery
- Nerdio connection lifecycle (Connect, Disconnect, required fields, status)
- Nerdio import/prune/list-version actions
- Config persistence for Nerdio settings
- Sync state keys and enable/disable rules for Nerdio UI buttons

Out of scope:
- Building the NerdioShellApps module itself
- Intune import execution (currently placeholder UI)

## Files And Responsibilities

- `EvergreenUI/Public/Start-EvergreenWorkbench.ps1`
  - Wires all Nerdio controls, events, state, and background actions
  - Enforces connection prerequisites before Nerdio actions
  - Persists Nerdio settings from Settings tab

- `EvergreenUI/Private/Connect-NerdioSession.ps1`
  - Connect/Disconnect helper for Nerdio Manager
  - Imports NerdioShellApps module and calls `Set-NmeCredentials` + `Connect-Nme`

- `EvergreenUI/Private/Invoke-NerdioImport.ps1`
  - Action engine for:
    - `PlanImport`
    - `ApplyImport`
    - `ListVersions`
    - `PlanPrune`
    - `ApplyPrune`

- `EvergreenUI/Private/Get-UIConfig.ps1`
  - Defines default and merged persisted Nerdio settings

- `EvergreenUI/Private/Set-UIConfig.ps1`
  - Writes config to `%APPDATA%\EvergreenUI\settings.json`

- `EvergreenUI/Resources/EvergreenUI.xaml`
  - Import view and Settings view controls for Nerdio

- `support/NerdioShellApps.psm1`
  - External command surface consumed by the UI/helpers

## Phase Plan

### Phase 1: Recreate Config Schema

Implement config read/write first, because all Nerdio behavior depends on it.

Required persisted keys under `NerdioSettings`:
- `DefinitionsRootPath` (string)
- `ModulePath` (string)
- `NmeHost` (string)
- `OauthToken` (string)
- `PruneKeepCount` (int, default 3)
- `DefaultDryRun` (bool, default true)
- `TenantId` (string)
- `ClientId` (string)
- `Scope` (string)

Required persisted key under `ImportSettings`:
- `CurrentProvider` (string, default `Nerdio`)

Secret handling contract:
- Secret is never persisted to config.
- Secret is held in memory only as `SecureString` for current session.

### Phase 2: Recreate XAML Surface

Implement all Nerdio controls with these names so code-behind wiring works:

Import panel:
- `ImportProviderComboBox`
- `NerdioHeaderCommandPanel`
- `NerdioRefreshDefinitionsButton`
- `NerdioPreviewImportButton`
- `NerdioApplyImportButton`
- `NerdioImportPathCommandGrid`
- `NerdioDefinitionsPathBox`
- `NerdioBrowseDefinitionsPathButton`
- `NerdioPreviewPruneButton`
- `NerdioApplyPruneButton`
- `NerdioListVersionsButton`
- `NerdioDefinitionsBorder`
- `NerdioDefinitionsListView`
- `NerdioPlanSummaryLabel`
- `NerdioPlanBorder`
- `NerdioPlanListView`
- `IntuneHeaderCommandPanel`
- `IntuneImportWorkflowPanel`

Settings panel (Nerdio section):
- `NerdioBrowseModulePathSettingsButton`
- `NerdioModulePathSettingsBox`
- `NerdioManagerHostSettingsBox`
- `NerdioOauthTokenSettingsBox`
- `NerdioTenantIdSettingsBox`
- `NerdioClientIdSettingsBox`
- `NerdioScopeSettingsBox`
- `NerdioSecretSettingsBox`
- `NerdioConnectionStatusLabel`
- `NerdioConnectButton`
- `NerdioDisconnectButton`
- `NerdioPruneKeepCountSettingsBox`

### Phase 3: Recreate Runtime State Contract

In shared `syncHash`, create Nerdio keys:
- `NerdioDefinitions` as `List[PSCustomObject]`
- `NerdioPlanItems` as `List[PSCustomObject]`
- `NerdioPrunePlanItems` as `List[PSCustomObject]`
- `NerdioOauthToken` (nullable string)
- `NerdioSecureSecret` (nullable SecureString)
- `NerdioConnectionValidated` (bool)

Also bind these control refs into `syncHash` for background thread UI updates:
- `NerdioDefinitionsListView`
- `NerdioPlanListView`
- `NerdioPlanSummaryLabel`
- `NerdioApplyImportButton`
- `NerdioApplyPruneButton`
- `NerdioPreviewImportButton`
- `NerdioPreviewPruneButton`
- `NerdioListVersionsButton`
- `NerdioConnectionStatusLabel`
- `NerdioConnectButton`
- `NerdioDisconnectButton`

### Phase 4: Recreate Connection Logic

Implement these helpers in workbench startup script:
- `resolveNerdioModulePath`
  - Use `Config.NerdioSettings.ModulePath` if present
  - Else derive from `DefinitionsRootPath\NerdioShellApps.psm1`
- `setNerdioConnectionState`
  - Toggles validated state, disconnect button, status text and color
- `invalidateNerdioConnectionState`
- `getNerdioConnectionRequirementMessage`
  - Fails if module path missing, token/host/tenant/client/scope/secret missing, or session not validated
- `assertNerdioConnectionReady`

Implement background action `connectNerdioSessionAction`:
- Mode `Connect`:
  - Read settings fields
  - Persist token/host/tenant/client/scope to config
  - Validate token + secret present
  - Cache token in memory and convert secret to `SecureString`
- Mode `Disconnect`:
  - Disconnect and clear in-memory token/secret

In background runspace:
- Dot-source `Write-UILog.ps1` and `Connect-NerdioSession.ps1`
- Call `Connect-NerdioSession -Mode Connect|Disconnect`
- Update UI via Dispatcher
- Always restore button enabled states in `finally`

Important behavior:
- After a successful connect validation, runspace intentionally disconnects in `finally`.
- `NerdioConnectionValidated` remains true as session validation flag.
- Import actions establish their own short-lived runspace session each time.

### Phase 5: Recreate Definitions Discovery

Implement `refreshNerdioDefinitions`:
- Require `DefinitionsRootPath` folder
- Recursively find `Definition.json`
- For each definition folder create row:
  - `Publisher` (from json if present)
  - `AppName` (leaf folder name)
  - `DefinitionPath` (folder path)
- Bind to `NerdioDefinitionsListView`
- Update summary text and logs

Selection behavior:
- `getSelectedDefinitionPaths` returns selected rows.
- If nothing selected, use all loaded definitions.

### Phase 6: Recreate Import And Prune Engine Calls

Implement `startNerdioBackgroundAction` with modes:
- `PlanImport`
- `ApplyImport`
- `PlanPrune`
- `ApplyPrune`
- `ListVersions`

Preconditions:
- No concurrent operation (`syncHash.IsRunning`)
- Module path exists
- `assertNerdioConnectionReady` passes

Background runspace sequence:
1. Dot-source helpers (`Write-UILog`, `Connect-NerdioSession`, `Invoke-NerdioImport`)
2. Connect to Nerdio using current credentials
3. Run `Invoke-NerdioImport` with mode and args
4. Update plan list and summary on UI thread
5. Disconnect in `finally`
6. Re-enable preview/list buttons

Enable/disable rules:
- During run: disable all Nerdio action buttons
- After `PlanImport`: enable `ApplyImport` only if planned rows exist
- After `PlanPrune`: enable `ApplyPrune` only if planned prune rows exist
- After apply actions: disable corresponding apply button

### Phase 7: Recreate Settings Tab Nerdio Behavior

Lost-focus persistence handlers:
- `NerdioDefinitionsPathBox`: persist + invalidate connection
- `NerdioModulePathSettingsBox`: persist + invalidate connection
- `NerdioPruneKeepCountSettingsBox`: parse int >= 1 else default 3, persist
- `NerdioManagerHostSettingsBox`: persist + invalidate connection
- `NerdioTenantIdSettingsBox`: persist + invalidate connection
- `NerdioClientIdSettingsBox`: persist + invalidate connection
- `NerdioScopeSettingsBox`: persist + invalidate connection
- `NerdioOauthTokenSettingsBox`: persist token text only

Change handlers:
- Token `TextChanged`: clear in-memory token and invalidate when empty; otherwise invalidate requiring reconnect
- Secret `PasswordChanged`: clear in-memory secret and invalidate when empty; otherwise invalidate requiring reconnect

Buttons:
- `NerdioConnectButton` -> `connectNerdioSessionAction -Mode Connect`
- `NerdioDisconnectButton` -> `connectNerdioSessionAction -Mode Disconnect`

Settings panel activation:
- On navigation to Settings, repopulate all Nerdio fields from config and current connection state

### Phase 8: Recreate Provider Switching

Implement provider normalization and toggling:
- `normalizeImportProvider`: only `Nerdio` or `Intune`
- `setImportProvider`:
  - Show Nerdio controls when `Nerdio`
  - Show Intune placeholder controls when `Intune`
  - Persist selection when requested

Import panel navigation behavior:
- On opening Import panel, apply provider from config.
- If provider is Nerdio, refresh definitions.

### Phase 9: Recreate Low-Level Import Logic

In `Invoke-NerdioImport` implement:
- Module path validation and module import preserving loaded state
- Result flattening helper for array/item payload variability
- Metadata command fallback:
  - `Get-AppMetadata`
  - or `Get-EvergreenAppDetail`
- `New-ShellApp` metadata parameter detection:
  - `AppMetadata` or `AppDetail`

Mode contracts:
- `PlanImport`
  - Emits `CreateApp+AddVersion`, `UpdateApp+SkipVersion`, or `UpdateApp+AddVersion`
- `ApplyImport`
  - Creates or updates app and conditionally adds version
- `ListVersions`
  - Lists all versions, marks `Preview` or `Stable`
- `PlanPrune`
  - Stable-only prune candidates beyond keep count
- `ApplyPrune`
  - Removes planned versions with `Remove-ShellAppVersion`

Standard output row schema:
- `Action`
- `AppName`
- `Version`
- `Result`
- `Message`
- `DefinitionPath`

## Validation Checklist

Functional checks:
- Settings values persist and reload on restart
- Secret never appears in config file
- Connect updates status label and disconnect button state
- Import provider toggles Nerdio vs Intune UI areas
- Preview import populates plan list and enables Apply import when appropriate
- Apply import runs only after preview plan exists
- Preview prune populates prune plan and enables Apply prune when appropriate
- Apply prune requires confirmation prompt
- List versions requires one selected definition and reads app name from `Definition.json`

Failure-path checks:
- Missing module path shows actionable error
- Missing token/secret/host/tenant/client/scope prevents actions
- Definitions path missing or invalid shows message and clears list
- Background failures log error and restore button enabled states

## Reimplementation Order Recommendation

1. Config schema and defaults
2. XAML control surface and names
3. Sync state initialization
4. Connection helpers and settings handlers
5. Definitions discovery
6. Import/prune action orchestration
7. `Invoke-NerdioImport` action internals
8. Provider switch behavior
9. End-to-end validation and regression checks

## Known Behavioral Notes To Preserve

- Dry-run preview is the intended first step before apply actions.
- Connection is validated for this UI session, but each action runspace reconnects independently.
- `NerdioOauthToken` is persisted as text in current implementation; secret is session-only.
- Apply buttons are never manually enabled outside plan-result logic.
