# Workflow: Import Nerdio Manager Shell App

## Context

Documents the end-to-end workflow triggered by clicking the **Import Nerdio Manager Shell App** button (`M365ImportNerdioButton`) on the Import / Microsoft 365 Apps tab. Written for planning future modifications.

## Phase 1: Pre-flight Validation (synchronous, UI thread)

File: `EvergreenUI/Public/Start-EvergreenWorkbench.ps1`

1. **Auth check** - `$requireImportAuth` verifies `$syncHash.NerdioApiAuthState.IsAuthenticated`. Aborts with warning if not authenticated.
2. **Concurrency guard** - checks `$syncHash.IsM365ImportLoading`; prevents a second import if one is running.
3. **Config selection** - validates a config is selected in `$m365ConfigsListView` and its `Status` is `'Valid'`.
4. **Paths** - validates `$m365ConfigPathBox` (config XML directory) and `$intunePackageOutputPathBox` (output path); creates output directory if missing.
5. **Module check** - confirms IntuneWin32App module is loadable via `$loadIntuneWin32AppModule`.
6. **Bundled module check** - confirms `EvergreenUI/Resources/NerdioShellApps.psm1` exists.

## Phase 2: UI State Update

- Sets `$syncHash.IsM365ImportLoading = $true`
- Shows loading overlay panel, updates status labels
- Disables both import buttons via `$updateM365ActionButtons`

## Phase 3: Background Runspace (async STA thread via `New-WpfRunspace`)

### 3a. Module Loading
- Imports `Evergreen` and `IntuneWin32App` if not already loaded.

### 3b. Package Build (`Invoke-M365AppPackageBuild.ps1`)

| Step | Action |
|------|--------|
| Evergreen query | `Get-EvergreenApp -Name 'Microsoft365Apps'`, filtered by selected channel, picks highest version |
| Working dirs | Creates `$OutputPath\$safeName\Source` and `...\Output` |
| Download | `Save-EvergreenApp` downloads `setup.exe` into Source |
| Copy XMLs | Copies `Install-Microsoft365Apps.xml` (and Uninstall XML if present) into Source |
| Patch XML | Updates `Channel`, `TenantId`, and `CompanyName` in the XML |
| IntuneWin package | `New-IntuneWin32AppPackage` wraps Source into a `.intunewin` file in Output |
| App.json | Copies template and injects version, display name, commands, detection rules |

### 3c. UI status update (Dispatcher.Invoke)
- Updates labels to "Uploading to Nerdio Manager..."

### 3d. Nerdio Manager upload (via bundled `NerdioShellApps.psm1`)

| Step | Function |
|------|----------|
| Set credentials | `Set-NmeCredentials` with all Nerdio/Azure fields from the UI |
| Authenticate | `Connect-Nme` |
| Upload blob | `New-ShellAppFile -FilePath <.intunewin path>` - returns blob URI |
| Create Shell App | `New-ShellApp -Name -Version -InstallCmd -UninstallCmd -FileUri` |

## Phase 4: Completion Polling (DispatcherTimer, 500ms interval)

- Timer polls `EndInvoke` to detect when the runspace finishes.
- On success: logs "M365: Nerdio Shell App created for '$DisplayName' v$version."
- On failure: logs the error message.
- Either way: disposes the PowerShell instance and runspace, clears `syncHash` references, calls `$setM365LoadingState -IsLoading $false` to restore UI.

## Key Files

| File | Role |
|------|------|
| `EvergreenUI/Public/Start-EvergreenWorkbench.ps1` | Button click handler, pre-flight, runspace setup, polling timer |
| `EvergreenUI/Private/Invoke-M365AppPackageBuild.ps1` | Package build logic (Evergreen query, XML patching, IntuneWin wrapping, App.json) |
| `EvergreenUI/Private/New-WpfRunspace.ps1` | STA runspace factory |
| `EvergreenUI/Private/Write-UILog.ps1` | Thread-safe UI logging |
| `EvergreenUI/Resources/NerdioShellApps.psm1` | Bundled Nerdio Manager API module |
| `EvergreenUI/Resources/EvergreenUI.xaml` | Button definition (line ~2658), loading panel, status labels |

## Key SyncHash Variables

| Variable | Purpose |
|----------|---------|
| `$syncHash.IsM365ImportLoading` | Concurrency lock |
| `$syncHash.NerdioApiAuthState.IsAuthenticated` | Auth gate |
| `$syncHash.Config.AzureAuthSettings.TenantId` | Azure tenant for XML patching |
| `$syncHash.PendingM365ImportPS` | Active PowerShell instance |
| `$syncHash.PendingM365ImportRunspace` | Active runspace |
| `$syncHash.PendingM365ImportAsync` | Async invoke handle |
| `$syncHash.PendingM365ImportTimer` | Polling timer |

## UI Controls Involved

| Control | Property | Use |
|---------|----------|-----|
| `m365ConfigsListView` | SelectedItem | Selected M365 config |
| `m365ConfigPathBox` | Text | Config XML directory |
| `intunePackageOutputPathBox` | Text | Package output path |
| `m365ChannelCombo` | SelectedItem.Content | Office 365 update channel |
| `m365CompanyNameBox` | Text | Company name for XML |
| `m365ConfigsLoadingPanel` | Visibility | Loading overlay |
| `m365ConfigsLoadingLabel` | Text | Loading status message |
| `m365ActionStatusLabel` | Text | Action status message |
| `m365ImportNerdioButton` | IsEnabled | This button |
| `nerdioTenantIdBox` | Text | Nerdio Tenant ID |
| `nmeHostBox` | Text | Nerdio host URL |
| `nmeClientIdBox` | Text | Nerdio Client ID |
| `nmeApiScopeBox` | Text | Nerdio API scope |
| `nmeOAuthTokenUrlBox` | Text | OAuth token URL |
| `nmeClientSecretBox` | Password | Nerdio client secret |
| `nmeSubscriptionIdBox` | Text | Azure subscription ID |
| `nmeResourceGroupCombo` | SelectedItem | Azure resource group |
| `nmeStorageAccountCombo` | SelectedItem | Azure storage account |
| `nmeContainerCombo` | SelectedItem | Azure blob container |
