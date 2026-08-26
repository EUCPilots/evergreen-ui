## Plan: Harden and streamline Evergreen Workbench

The scan found one security-sensitive execution path, one stale test expectation, missing release gates, and concentrated maintainability debt in the 9,000-line `Start-EvergreenWorkbench` function. The recommended approach is an incremental refactor: establish a reliable baseline, replace executable package filters with constrained parsing, consolidate background-operation lifecycle and repeated UI helpers, optimize batch cache I/O, then improve UI validation/accessibility and documentation. A full MVVM/C# rewrite and broad visual redesign are deliberately excluded.

**Steps**

### Phase 1: Establish a trustworthy baseline

1. Reconcile the stale configuration test with the current canonical startup provider. Keep `Authentication` as the default from `Get-UIConfig`, initialize `ImportCurrentProvider` from that configuration rather than a separate `Nerdio` literal, and update the Pester expectation. Add cases for malformed JSON, missing nested sections, `ShowInstallTab` backward compatibility, and blank provider fallback.
2. Split the single test file into focused `*.Tests.ps1` files and add a checked-in Pester configuration with unit/integration tags and code coverage over private helpers. Start with high-risk pure functions: package-filter resolution, definition loading, detection rules, config merge/persistence, and sorting.
3. Add a Windows CI validation workflow for pull requests and before release/tagging. Run `Test-ModuleManifest`, PSScriptAnalyzer, and Pester under Windows PowerShell 5.1 and current PowerShell 7; make tag creation and PSGallery publishing depend on the validation result. Replace line-number-based manifest version extraction with `Import-PowerShellDataFile` in PowerShell.

### Phase 2: Remove executable definition filters

4. Add a private package-filter parser/executor that uses the PowerShell AST only to recognize a deliberately small legacy grammar: one `Get-EvergreenApp` or `Get-VcList` source command with literal named arguments, followed only by supported property predicates/sorting/selection operations. Convert the validated AST into data and invoke approved commands directly with splatted parameters; do not pass the original string to `Invoke-Expression`. Reject command separators, invocation operators, variables, subexpressions, member/type expressions, redirection, and unsupported pipeline commands with a structured error.
5. Route `Get-IntunePackageLatestVersion` through the constrained executor; `Get-InstallPackageLatestVersion`, Intune build, definition update, and local install then inherit the safer behavior. Add positive compatibility fixtures for the repository's current `Get-EvergreenApp | Where-Object | Select-Object` shape and VcRedist filters, plus negative tests for chained commands and process/file/network side effects.
6. Centralize App.json loading and baseline schema validation in a `Read-PackageDefinition` helper returning the repository's existing structured `Succeeded/Definition/Error` shape. Adopt it first in Install and Intune definition discovery/build/update paths; leave workflow-specific validation in the owning function.

### Phase 3: Consolidate asynchronous lifecycle and shutdown

7. Promote the existing `ActiveBackgroundOperations` registry into reusable private helpers for start, poll/complete, cancel, and cleanup. Store operations by feature/operation ID with `PowerShell`, runspace, async result, timer/callback state, and status. Migrate one low-risk workflow first, validate it, then migrate Install, Intune, M365, and Nerdio operations. Enforce one active operation per feature while allowing unrelated features to run concurrently.
8. Replace the repeated `Pending*PS`, `Pending*Runspace`, `Pending*Async`, and `Pending*Timer` quartets and duplicated shutdown blocks as each workflow migrates. Ensure every completion, startup failure, cancellation, and window-close path calls `EndInvoke` when valid, stops the pipeline when needed, disposes `PowerShell` and runspace objects, unregisters handlers, clears state, and logs best-effort cleanup failures with `Write-Verbose`.
9. Harden UI-thread output helpers and startup resource handling. Guard against a null/closing dispatcher and missing/disposed controls in `Write-UILog` and `Write-UpdateOutput`, suppress only expected shutdown failures with verbose diagnostics, dispose the XAML stream in `finally`, and validate critical named controls after `XamlReader.Load` so XAML/code naming drift fails with a useful startup error.

### Phase 4: Extract repeated logic and reduce hot-path I/O

10. Add a private `Set-ListViewSort` helper accepting the list view, property, and direction; replace the eight duplicated sort scriptblocks and cover ascending, descending, empty source, and missing property cases with unit tests.
11. Extract shared loading-state mechanics only where behavior is genuinely common: enabled-state capture/restore, progress visibility, and status text. Keep feature-specific action eligibility in the existing Intune, Install, Nerdio, and M365 handlers rather than introducing a general event bus.
12. Change install latest-version resolution to load `install-latest-cache.json` once per batch, update entries in memory, and write once atomically at batch completion. Preserve cache age logging and best-effort write behavior; add tests for cache hit, stale entry, malformed cache, duplicate definition key, and partial live failures.
13. Introduce feature-scoped state containers gradually for new/migrated code (`Operations`, `Install`, `Intune`, `Nerdio`, `M365`) while leaving WPF control references at the shared root. Avoid a big-bang rename of every `$syncHash` key; remove legacy keys only after each workflow's tests pass.

### Phase 5: UI, dependency, and documentation cleanup

14. Add an automated XAML smoke test that loads the resource in STA and verifies every control name requested by `FindName`. Explicitly enable recycling virtualization only after measuring large-list behavior because WPF `ListView` commonly virtualizes by default; retain it where profiling shows benefit.
15. Fill concrete accessibility gaps: name all progress indicators and state dots, ensure status is conveyed by text as well as color, verify keyboard order, and move focus into runtime dialogs. Manually test with Windows Narrator, keyboard-only navigation, light/dark themes, and high-contrast mode.
16. Document optional feature dependencies (`Microsoft.Graph.Authentication`, `IntuneWin32App`, `Az.Accounts`, `Az.Resources`, and `Az.Storage`) separately from the required Evergreen module, expose a prerequisite checker with actionable messages, and list optional modules in manifest metadata where supported.
17. After the behavior-preserving extractions are stable, split `Start-EvergreenWorkbench` by feature registration/orchestration into private files. Keep the public function responsible for STA enforcement, config/XAML startup, shared state construction, feature registration, window lifetime, and final cleanup. Extract XAML styles/resources before considering separate view files, since runtime `XamlReader` resource resolution must remain compatible with packaged PowerShell modules.

**Relevant files**

- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-IntunePackageLatestVersion.ps1` — replace the permissive regex plus `Invoke-Expression` path.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-InstallPackageLatestVersion.ps1` — consume safe resolution and batch-oriented cache state.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-InstallPackageDefinitions.ps1` — first consumer of shared definition loading/validation.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Invoke-IntuneDefinitionUpdate.ps1` — reuse shared definition parsing and safe filter execution.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Invoke-IntunePackageBuild.ps1` — reuse shared definition parsing and prerequisite checks.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Invoke-LocalPackageInstall.ps1` — reuse shared definition parsing.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\New-WpfRunspace.ps1` — retain as the runspace factory and build lifecycle helpers around it.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Write-UILog.ps1` — shutdown-safe dispatch.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Write-UpdateOutput.ps1` — match logging dispatch behavior.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-UIConfig.ps1` — canonical provider default and expanded tests.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Public\Start-EvergreenWorkbench.ps1` — operation registry, state migration, helper extraction, control validation, and eventual feature registration split.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Resources\EvergreenUI.xaml` — accessibility names, measured virtualization changes, and later resource extraction.
- `c:\projects\_EUCPilots\evergreen-ui\tests\EvergreenUI.tests.ps1` — split and correct stale provider assertion.
- `c:\projects\_EUCPilots\evergreen-ui\.github\workflows\tag-release.yml` — depend on validated builds and robustly read manifest version.
- `c:\projects\_EUCPilots\evergreen-ui\.github\workflows\publish-psgallery.yml` — validate the exact tagged artifact before publish.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\EvergreenUI.psd1` — optional dependency metadata and new helper file entries.
- `c:\projects\_EUCPilots\evergreen-ui\README.md` — optional prerequisites, troubleshooting, and resource filename correction.

**Verification**

1. Run `Invoke-Pester -Path .\tests -Output Detailed` under Windows PowerShell 5.1 and PowerShell 7; require all unit tests to pass and integration tests to be explicitly tagged/skippable when credentials are unavailable.
2. Run malicious-filter tests proving semicolons, `&`, dot-sourcing, subexpressions, type/member invocation, redirection, and unapproved commands are rejected without side effects.
3. Run `Invoke-ScriptAnalyzer -Path .\EvergreenUI -Recurse` and `Test-ModuleManifest -Path .\EvergreenUI\EvergreenUI.psd1` in CI and locally.
4. Exercise each migrated async workflow through success, failure, cancellation, repeated-click, and window-close scenarios; verify no operation remains in the registry and no disposed dispatcher exception escapes.
5. Measure Install batch cache reads/writes with mocks and verify one read plus at most one atomic write per batch.
6. Import the module and launch `Start-EvergreenWorkbench`; smoke-test all eight navigation views, each Import provider, Settings persistence, and log/update output.
7. Test large Intune/Install/Nerdio lists before and after any virtualization change, then run keyboard-only, Narrator, light/dark, and high-contrast checks.
8. Validate a packed module in a clean Windows sandbox with core-only dependencies and with each optional feature dependency set.

**Decisions**

- Treat package definitions as untrusted input; the substring whitelist around `Invoke-Expression` is the highest-risk issue.
- Treat `Authentication` as the canonical default provider because it is the current persisted-config default; remove the separate in-memory `Nerdio` default.
- Reuse and extend the existing background-operation registry instead of introducing a new queue or event bus.
- Preserve PowerShell 5.1 support, existing structured-result conventions, lazy Az module loading, and current user-visible workflows.
- Include security, reliability, test/CI, targeted performance, accessibility, dependency documentation, and incremental decomposition.
- Exclude a C#/MVVM rewrite, a full visual redesign, localization, and a one-shot split of the XAML or `$syncHash`; those have high migration cost and weaker immediate payoff.
