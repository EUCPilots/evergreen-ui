# Nerdio Manager Implementation Memory (Evergreen Workbench)

Last verified against code: 2026-03-15
Purpose: implementation memory for rebuilding Nerdio support without reverse engineering again.

## Quick Snapshot

The current Nerdio support is implemented as:
- UI in Import and Settings panels (`EvergreenUI.xaml`)
- Event/state orchestration in `Start-EvergreenWorkbench.ps1`
- Session connection helper in `Connect-NerdioSession.ps1`
- Import/prune/list logic in `Invoke-NerdioImport.ps1`
- Persisted settings in `%APPDATA%\EvergreenUI\settings.json` via `Get-UIConfig`/`Set-UIConfig`

The architecture uses STA WPF UI + background runspaces with Dispatcher marshaling for UI updates.

## State Model

Nerdio runtime state in `syncHash`:
- `NerdioDefinitions` : `List[PSCustomObject]`
- `NerdioPlanItems` : `List[PSCustomObject]`
- `NerdioPrunePlanItems` : `List[PSCustomObject]`
- `NerdioOauthToken` : nullable string (session memory)
- `NerdioSecureSecret` : nullable `SecureString` (session memory)
- `NerdioConnectionValidated` : bool

UI refs copied into `syncHash` for background updates:
- definitions list, plan list, summary label
- preview/apply/list buttons
- connect/disconnect buttons
- connection status label

## Persisted Config Contract

Config path:
- `%APPDATA%\EvergreenUI\settings.json`

Nerdio persisted fields (`Config.NerdioSettings`):
- `DefinitionsRootPath`
- `ModulePath`
- `NmeHost`
- `OauthToken`
- `PruneKeepCount`
- `DefaultDryRun`
- `TenantId`
- `ClientId`
- `Scope`

Import provider persisted field (`Config.ImportSettings`):
- `CurrentProvider` (`Nerdio` or `Intune`)

Not persisted:
- Secret from `NerdioSecretSettingsBox`
- Any active connected token object/session in Nerdio module

## Settings Tab Behavior (Nerdio Updates)

Nerdio section fields:
- `NerdioModulePathSettingsBox`
- `NerdioManagerHostSettingsBox`
- `NerdioOauthTokenSettingsBox`
- `NerdioTenantIdSettingsBox`
- `NerdioClientIdSettingsBox`
- `NerdioScopeSettingsBox`
- `NerdioSecretSettingsBox`
- `NerdioPruneKeepCountSettingsBox`

Connection controls:
- `NerdioConnectButton`
- `NerdioDisconnectButton`
- `NerdioConnectionStatusLabel`

Persistence and invalidation rules:
- Most Nerdio text fields persist on `LostFocus`.
- Host, tenant, client, scope, module path, definitions path changes invalidate connection state.
- Token text change invalidates connection state; empty token clears in-memory token.
- Secret password change invalidates connection state; empty secret clears in-memory secret.
- Prune keep count is normalized to int >= 1, fallback 3.

Connection status UX:
- Connected state text is green.
- Not connected / invalid state text is dark goldenrod.
- Disconnect button is enabled only when validated.

## Import View Behavior

Provider selector:
- `ImportProviderComboBox`
- Nerdio and Intune options

Provider toggling:
- Nerdio mode shows:
  - `NerdioHeaderCommandPanel`
  - `NerdioImportPathCommandGrid`
  - `NerdioDefinitionsBorder`
  - `NerdioPlanSummaryLabel`
  - `NerdioPlanBorder`
- Intune mode shows placeholder panels only.

Nerdio action controls:
- `NerdioRefreshDefinitionsButton`
- `NerdioPreviewImportButton`
- `NerdioApplyImportButton`
- `NerdioPreviewPruneButton`
- `NerdioApplyPruneButton`
- `NerdioListVersionsButton`

Definitions source:
- Root path from `Config.NerdioSettings.DefinitionsRootPath`
- Finds all `Definition.json` recursively
- Row schema in UI list:
  - `Publisher`
  - `AppName`
  - `DefinitionPath`

Selection semantics:
- If no selected rows, operations target all loaded definitions.

## Action Pipeline

Central action starter in startup script:
- `startNerdioBackgroundAction`

Modes:
- `PlanImport`
- `ApplyImport`
- `PlanPrune`
- `ApplyPrune`
- `ListVersions`

Preconditions before any Nerdio action:
- Module path exists
- In-memory token present
- Host, tenant, client, scope exist
- Secret present
- `NerdioConnectionValidated` is true

Execution flow for each action:
1. Disable Nerdio action buttons and set `IsRunning`
2. Start background runspace
3. Dot-source `Write-UILog`, `Connect-NerdioSession`, `Invoke-NerdioImport`
4. Connect via `Connect-NerdioSession -Mode Connect`
5. Execute `Invoke-NerdioImport` with mode args
6. Marshal results to UI thread and refresh plan list
7. Disconnect in `finally`
8. Re-enable preview/list buttons and clear running state

Apply button enablement:
- `ApplyImport` enabled only after `PlanImport` returns planned rows.
- `ApplyPrune` enabled only after `PlanPrune` returns planned prune rows.
- Apply actions disable their apply button when done.

Prune confirmation:
- `ApplyPrune` prompts user with count of versions to be removed.

## Connect-NerdioSession Contract

Input:
- `Mode` = `Connect` | `Disconnect`
- `NerdioModulePath`
- OAuth fields: token, tenant, client, scope, host
- `SecureSecret`

Connect behavior:
- Imports Nerdio module from explicit path
- Verifies module exposes `Set-NmeCredentials` and `Connect-Nme`
- Builds exact OAuth parameter map:
  - `OAuthToken`
  - `TenantId`
  - `ClientId`
  - `ApiScope`
  - `ClientSecret`
  - `NmeHost`
- Calls `Set-NmeCredentials` then `Connect-Nme`

Disconnect behavior:
- Calls `Remove-NerdioManagerSecretsFromMemory` if present

Output object:
- `Connected` bool
- `Message` string

## Invoke-NerdioImport Contract

Purpose:
- Execute Nerdio definition import and prune operations once a runspace is authenticated.

Modes and key behavior:
- `PlanImport`
  - Reads each definition
  - Resolves metadata using `Get-AppMetadata` or fallback `Get-EvergreenAppDetail`
  - Decides create/update and version add/skip plan rows
- `ApplyImport`
  - Creates or updates shell app
  - Adds version when missing
- `ListVersions`
  - Lists versions for selected app name, marks Preview/Stable
- `PlanPrune`
  - Stable versions only, sorted descending, keep newest `KeepCount`
- `ApplyPrune`
  - Removes planned stale stable versions

Compatibility guards:
- Handles both `AppMetadata` and `AppDetail` parameter names for `New-ShellApp` / `New-ShellAppVersion`
- Flattens Nerdio responses that may come as arrays or `{ items = ... }`

Standard result row schema:
- `Action`
- `AppName`
- `Version`
- `Result`
- `Message`
- `DefinitionPath`

## Important Reimplementation Nuances

- Connection validation and action execution are intentionally decoupled:
  - Connect button validates credentials for current session state.
  - Actual actions still create a new runspace, reconnect, execute, disconnect.
- Token is currently persisted in config as plain text (current behavior, not ideal from security perspective).
- Secret is never written to config and must remain session-only.
- Any credentials-path change should force reconnect before actions.
- Plan list is used as source-of-truth for enabling apply actions.

## UI Text/Behavior Expectations

Messages shown to user should remain actionable, including:
- Missing module path guidance
- Missing token/secret guidance
- Reconnect required after settings changes
- Dry-run summary text before apply
- Apply completion summary with applied/failed counts

## Minimal Regression Checklist

- Import panel loads definitions from configured path.
- Connect succeeds with valid credentials and updates status label.
- Preview import generates rows and enables Apply import.
- Apply import runs and reports applied/failed rows.
- Preview prune identifies stale stable versions per keep count.
- Apply prune requires confirmation and removes versions.
- List versions works from selected definition's `Definition.json` name.
- Switching provider to Intune hides Nerdio controls and persists provider.
- Restart restores Nerdio settings and provider selection.
