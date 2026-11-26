# Changelog

## [2.0.4-preview]

- Show safe Nerdio validation details when a publish request fails, without automatically retrying uncertain writes.
- Resolve a newly created Microsoft 365 Nerdio Shell App after a completed response omits its ID, while keeping ambiguous outcomes blocked for review.
- Add explicit acknowledgment of unresolved Nerdio operations from both Nerdio workflows and PowerShell, with active-operation protection and duplicate-write warnings.
- Expand Settings with a confirmed defaults reset, window-layout reset, and Evergreen and cache maintenance actions. Place Saved folders first, followed by Maintenance and Window layout, and remove the Startup view control.
- Keep the Apps navigation label visible when its tooltip opens.
- Keep the Apps download destination picker on the Apps page and label its button "Change destination".
- Apply Fluent styling to the Clear Workbench cache confirmation dialog.
- Show sidebar focus outlines only for keyboard navigation, not mouse selection.
- Animate the sidebar selection indicator between navigation items, respecting Windows animation settings.
- Animate the selected tab indicator on the Packages, Intune and Nerdio pages.

## [2.0.2-preview]

- Fix confirmed Microsoft 365 builds replacing the application name with a preview field name. Calculate names from products, Outlook exclusions, Desktop or VDI licensing, channel and architecture, retaining the Office version when published to Intune.
- Use Intune's `updateRelationships` action for supersedence instead of the unsupported relationship POST route. Preserve existing dependencies and supersedence relationships, include the relationship direction, and retain Graph error details when a request fails.
- Fix Microsoft 365 Intune publishing failing when the template omits `Program.AllowAvailableUninstall`; omitted values default to false.
- Show install status and recovery guidance in the shared status instead of a duplicate label.
- Match the selected navigation indicator to the theme accent colour.

## [2.0.1-preview]

- Remove the obsolete test suite and update project guidance.
- Fix background jobs occasionally reporting completion before their results were available, which could mark install reviews as failed.
- Show all properties returned for the selected app in the Apps version table, with app-specific columns supported by column visibility preferences and CSV export.
- Manage the Packages definitions, Microsoft 365 configurations, and Nerdio Shell App definitions folders in Settings.
- Limit header status messages to two wrapped lines with an ellipsis and show the full message in a tooltip.
- Show the publisher beside each definition in the Intune Win32 Apps comparison table.
- Apply Fluent styling to Intune and shared Microsoft 365 confirmation dialogs.
- Make Microsoft 365 form labels follow native light and dark themes in Intune and Nerdio.
- Use the Evergreen bulb as the Workbench window icon.
- Size the confirmation, Library removal and Nerdio pruning dialogs to their content, with fixed non-resizable borders. Long content scrolls with the actions visible.
- Show local installer paths in the Library versions table.
- Add an **Open folder** right-click action to the Library applications and versions tables.
- Fix Intune package builds failing when Evergreen saves the installer in channel, version or architecture subfolders. Packages are now built from the installer's download folder.

- Add confirmed Library removal for a selected application or selected artifact
  rows, independently of Evergreen's retention command. Preserve shared and
  unrecorded files, reject stale selections and unsafe paths, and refresh
  inventory after full or partial outcomes without automatic retries. The
  confirmation follows the Workbench's Fluent light, dark and system themes.

- Combine and right-align the Intune Win32 connection and comparison controls,
  with consistent horizontal spacing, one Connect/Disconnect button and the
  signed-in UPN on the left.
- Add icons to the Packages, Intune, and Nerdio tabs while retaining their text labels.
- Remember the 10 most recently saved Library locations and offer them in a dropdown on the Library page. `Set-EwSetting -Name LibraryPath` records each non-empty path in the new `LibraryPathHistory` setting.
- Move Nerdio Azure storage and API setup to a Settings tab.
- Move the Nerdio Shell App definitions folder, Browse and Save setup controls above the Shell Apps table. The Settings tab has its own Save setup button.
- Reduce the height of Nerdio publishing results to give the Shell Apps table more space.
- Show Nerdio version pruning actions beside Review outcome instead of in an expander.
- Apply Fluent light and dark styling to Nerdio publishing, outcome review and version pruning dialogs.
- Fix Nerdio Review outcome failing to resolve its private recovery helper in a background job.
- Fix Nerdio version pruning previews and deletions failing to resolve private destination and recovery helpers in background jobs.
- Show each definition's application architecture in the Packages Definitions tab.
- Fix definition updates rejecting `Application.Filter` values that pass literal `-ErrorAction` or `-WarningAction` arguments to `Get-EvergreenApp` or `Get-VcList`.
- Left-align the Intune and Nerdio Microsoft 365 forms and the Settings and About pages.
- Centre the Update app check boxes in the Intune Win32 Apps comparison grid.
- Combine Packages and local Install into Definitions and Install tabs under one sidebar destination. Refresh local detection after definition changes, defer refresh during active operations, and retain legacy Install startup navigation and installation safeguards.
- Right-align the download queue toggle and path, with 16 pixels above the queue table and consistent header spacing when the queue is shown or hidden.
- Export the current filtered Apps artifact grid and visible columns to CSV.
- Match the Apps Actions menu to the Columns menu's light and dark styling.
- Add an Apps Columns menu to hide or show optional artifact columns and remember choices between sessions. Version and URI always remain visible.
- Give Intune and Nerdio tabs a WinUI-style accent underline and matching content-sized header widths.
- Cache `Get-EvergreenApp` results as one JSON file per application in the Workbench cache folder for 24 hours. `Get-EwApp -Force` and `-NoCache` lookups refresh the cache, Clear Workbench cache and Update Evergreen remove it, and the Apps menu adds Reload selected app versions.
- Begin the PowerShell 7.6 v2 rewrite with headless settings, bounded background jobs, Apps, downloads, and Library commands.
- Combine Apps discovery and downloads in one view with a resizable queue tray, inline queue actions, navigation count, and editable saved folders in Settings.
- Group the Apps queue and download actions on one line, with separators between action groups.
- Place the Library path and its actions on one line.
- Fix the expanded Apps download queue not scrolling when it contains more rows than fit.
- Let the Packages definitions list fill the view so the output folder sits directly above the activity log.
- Add consistent cell spacing and vertically centered text to all v2 data grids.
- Centre Apps favourite stars and use native Fluent colours in light and dark modes, including while application versions load.
- Remove the Application and Favourite column headers from the Apps list.
- Remember the Apps application list width between sessions, adapting it to smaller windows.
- Fix errors when resizing the Apps queue tray, opening an artifact URI, or browsing for a folder in Settings.
- Store Workbench settings separately and load optional integration modules only when required.
- Add App.json discovery, constrained filter evaluation, artifact resolution and definition updates, local detection and installation, and Intune/Microsoft 365 package building.
- Add Intune and Nerdio authentication and publishing APIs, including Intune supersedence and Nerdio Shell App uploads.
- Keep `IntuneWin32App`, Microsoft Graph Authentication, and Az modules optional; require them only for the matching package or provider workflow.
- Add headless parity commands: favourite apps, dependency status and Evergreen updates, Microsoft 365 configuration discovery, Intune app listing and comparison, Azure resource discovery, and Nerdio definition, Shell App, comparison, and version cleanup commands.
- `Publish-EwNerdioApp` can now add a version to an existing Shell App and download the package from the definition source when `-PackagePath` is omitted.
- Add the initial v2 WPF interface for Apps, Download, and Library, with native WPF theme modes and background work through the shared job pool.
- Expand the v2 WPF shell with Intune Packages setup and local Install views, including shared App.json definitions, local detection, separate latest-version lookup, and confirmed batch installation.
- Check native Windows architecture before local installs, with per-application approval for missing requirements or x64 emulation on Arm64 and explicit unattended opt-ins. Show and optionally hide incompatible Install rows.
- Restore metadata-driven artifact filters, show Library version details and queued architecture/URI, and improve path-row sizing and theme contrast.
- Add the Intune Publish view with connection, comparison, confirmed sequential build-and-publish batches, optional update apps, and supersedence retry.
- Preserve partial Intune app IDs and Definition update failures, and distinguish linked supersedence chains from ambiguous Intune matches.
- Match the v2 title bar to the form background on Windows 11 and correct sidebar text and hover colours in light and dark modes.
- Use multi-select check box dropdowns for Apps artifact filters; values combine with OR within a property and AND across properties, and no selection means All.
- Add a Clear queue action that removes every queued row unless a download is running; Clear completed now removes only downloaded and failed rows.
- Restore the window size and maximised state, the last selected application, and the last viewed page when the Workbench starts.
- Rename the Publish view to Intune and add a dedicated Nerdio view with staged Azure/API connection, storage discovery and saved non-secret setup.
- Add read-only Nerdio publishing plans and confirmed sequential batches for Evergreen-backed Shell Apps, with source/file/target rechecks and cancellation between items.
- Share Nerdio sessions across Job workers and preserve partial blob, app and job identifiers; block pending or unknown outcomes until reviewed rather than retrying automatically.
- Persist Nerdio publish and delete attempts before provider writes, restore unresolved outcomes and pruning offers after restart, and require reconnection to the same destination.
- Add optional post-publish Shell App version pruning with a default retention of one, explicit app selection, exact-version preview and recheck, and separate confirmation.
- Add standalone version pruning for a selected, matched existing Shell App in the Nerdio view, with the same retention preview, confirmation and recovery safeguards, and automatic comparison refresh.
- Stop on pending or unknown deletion outcomes, require manual review, and skip apps with duplicate, unorderable or non-newest published versions.
- Add API-only Nerdio authentication without changing an unrelated Azure context on disconnect.
- Require valid Microsoft 365 configuration IDs and use the Office channel version for package metadata and detection. Stage rolling-channel configurations and reject `DownloadPath`, which requires a pinned version.
- Add Microsoft 365 build and confirmed publishing tabs for Intune and Nerdio, with separate Office and deployment-tool versions, input and target rechecks, and cooperative cancellation.
- Preserve partial provider outcomes and require explicit review of uncertain Intune and Nerdio writes; do not retry, roll back or remove provider resources automatically.
- Add Settings with read-only saved Download and Library paths and checked folder-opening actions.
- Add About with Workbench metadata and independently refreshed local dependency status, including versions loaded in the window runspace.
- Add Apps maintenance controls for Evergreen application-data updates, confirmed Workbench cache clearing, and opening the cache folder without upgrading the installed module.
- Add headless cache clearing with cross-runspace/process invalidation, protection against stale in-flight cache writes, targeted custom paths, and explicit partial outcomes.
- Refresh Apps after maintenance while preserving valid filters and queued Artifacts; distinguish refresh failures from maintenance outcomes and mark retained data stale.
- Refresh the WPF interface with adaptive icon navigation, themed primary
  actions, grouped provider forms, and a collapsible, resizable activity log.
  Theme selection is now in Settings.
- Restore standard Windows chrome in v2 with a solid title bar matching the
  themed form background. Retain Mica in the window body when supported, with
  an opaque fallback for accessibility settings and unavailable backdrops.
- Keep the Windows taskbar visible when the Workbench is maximised.
