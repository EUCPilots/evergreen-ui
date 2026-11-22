# Workbench cache clearing is explicit and coordinated

Evergreen application-data updates retain their existing local catalog reset,
but persistent Workbench cache clearing is a separate action. Clearing affects
Workbench catalog and definition-Artifact data only, not Evergreen application
data, downloaded Artifacts, Library contents, settings or provider recovery.

Invalidation must be visible across runspaces and processes sharing a cache.
Queries already in progress may return their results, but cannot repopulate a
cache invalidated since they started. This avoids cancelling ongoing work while
preventing a clear from being undone by stale writers; coordination metadata
therefore survives cache clearing.
