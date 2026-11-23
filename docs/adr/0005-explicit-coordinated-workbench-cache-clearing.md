# Workbench cache clearing is explicit and coordinated

Evergreen application-data updates retain their existing local catalog reset
and also clear the per-application version cache, but persistent Workbench
cache clearing is a separate action. Clearing affects Workbench catalog,
per-application version and definition-Artifact data only, not Evergreen application
data, downloaded Artifacts, Library contents, settings or provider recovery.

Invalidation must be visible across runspaces and processes sharing a cache.
Queries already in progress may return their results, but cannot repopulate a
cache invalidated since they started. This avoids cancelling ongoing work while
preventing a clear from being undone by stale writers; coordination metadata
therefore survives cache clearing.

Per-application version results from `Get-EvergreenApp` are cached as one
JSON file per application in the `Apps` subfolder for 24 hours. They share the
same epoch rule: a lookup that started before a clear never writes its result.
Force and NoCache lookups skip reading the cache but save their fresh results.
