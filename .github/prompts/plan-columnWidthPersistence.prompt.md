## Plan: Persist GridView Column Widths

Add durable per-list-view column width persistence for Download, Library, Install, and Import list views by extending the existing UI config schema and wiring capture/restore into current startup and autosave flows in Start-EvergreenWorkbench. Reuse established config merge and snapshot patterns to keep behavior backward-compatible and low-risk.

**Steps**
1. Phase 1 - Extend config schema (*blocks later steps*):
1. Add a new top-level config section in `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-UIConfig.ps1` named `GridViewColumnWidths` with nested objects for each target list view and its default column widths.
2. Ensure the new section is merged forward-compatibly when reading existing settings files by using existing merge behavior for nested sections (same pattern used by `NerdioSettings`, `IntuneSettings`, and others).

2. Phase 2 - Add column width helper logic (*depends on Phase 1*):
1. In `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Public\Start-EvergreenWorkbench.ps1`, add a helper to capture current column widths from each target `ListView` `GridView` into a serializable hashtable/PSCustomObject keyed by list view name and column header.
2. Add a companion helper to restore saved widths from config to each target `ListView` `GridView`, with safety guards for missing lists, missing columns, invalid widths, and schema drift.
3. Use stable keys for columns that work with both `DisplayMemberBinding` and `CellTemplate` columns; default to header text and fallback to index when needed.

3. Phase 3 - Wire persistence into existing lifecycle (*depends on Phase 2*):
1. Call the restore helper during startup after controls are resolved and before normal user interaction, so widths are present immediately.
2. Integrate capture into the existing `persistUiSettingsSnapshot` workflow so autosave timer and closing save path both persist resized widths without introducing a second save mechanism.
3. Keep serialization depth consistent with existing config writes and avoid extra file I/O by relying on current snapshot-diff logic (`SettingsLastSavedJson`).

4. Phase 4 - Handle dynamic Library Details columns (*depends on Phase 3*):
1. After dynamic `LibraryDetailsListView` column rebuild (in `loadLibraryAppDetails`), reapply stored widths for matching headers so regenerated columns honor saved user sizing.
2. Keep default width behavior for newly introduced columns not previously seen in settings.

5. Phase 5 - Validation (*depends on all prior phases*):
1. Verify first-run behavior: defaults load when settings file has no `GridViewColumnWidths` section.
2. Verify upgrade behavior: older settings files merge cleanly with no errors and new widths start saving after resize.
3. Verify persistence behavior for all target views: resize one or more columns, wait for autosave or close app, relaunch, confirm exact widths restored.
4. Verify resilience: corrupted/non-numeric width values are ignored and replaced by defaults at runtime without blocking startup.

**Relevant files**
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Private\Get-UIConfig.ps1` - add defaults and nested merge support for `GridViewColumnWidths`.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Public\Start-EvergreenWorkbench.ps1` - add capture/restore helpers, integrate into startup and snapshot persistence, and handle dynamic Library details columns.
- `c:\projects\_EUCPilots\evergreen-ui\EvergreenUI\Resources\EvergreenUI.xaml` - source of target list views/columns used for mapping and defaults; no structural change required unless naming adjustments are needed.

**Verification**
1. Launch Workbench, resize columns in Download (`DownloadQueueListView`), Library (`LibraryContentsListView`, `LibraryDetailsListView`), Install (`InstallPackagesListView`), and Import (`IntuneWin32AppsListView`, `NerdioDefinitionsListView`, `M365ConfigsListView`).
2. Wait >5 seconds (autosave interval) and close Workbench.
3. Reopen Workbench and confirm resized widths are restored in each target list.
4. Repeat with immediate close (without waiting for timer) to validate closing-force-save path.
5. Manually remove `GridViewColumnWidths` from `%APPDATA%\EvergreenUI\settings.json`, relaunch, and confirm defaults are applied without errors.

**Decisions**
- Included scope: only column width persistence for Download, Library, Install, and Import tab list views listed above.
- Excluded scope: sort order persistence changes, row selection persistence, additional tabs not requested, and UI redesign.
- Persistence approach: reuse existing `Get-UIConfig`/`Set-UIConfig` and `persistUiSettingsSnapshot` flow rather than introducing separate storage files.
- Mapping strategy: persist widths by list-view name + column identity (header with index fallback) to support mixed template/binding columns.

**Further Considerations**
1. Optional enhancement: also persist Apps view `VersionsListView` column widths for consistency with other list-heavy tabs.
2. Optional enhancement: add min/max width clamping to prevent unusable layouts from accidental extreme resizing.
