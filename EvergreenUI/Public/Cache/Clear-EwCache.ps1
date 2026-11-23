Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwCache {
    <#
    .SYNOPSIS
        Clears Workbench catalog, application version, and definition artifact caches.
    .DESCRIPTION
        Invalidates every Workbench catalog and only the selected persistent
        definition cache, including caches in other runspaces and processes.
        Deletes definition-artifact-cache.json and the per-application version
        files in the Apps subfolder. Coordination metadata and
        unrelated files are preserved. Does not update Evergreen or delete its
        application data, downloads, Library, settings, or provider recovery.
        Failed steps are reported without retries.
        DefinitionCacheRemoved reports the payload deletion step separately
        from invalidation. RemovedEntryCount counts deleted definition entries
        when EntryCountKnown is true, not catalogs in other processes.
        AppCacheInvalidated and AppCacheRemovedCount report the application
        version cache separately.
    .PARAMETER CachePath
        Explicit definition cache directory. Defaults to the local
        EvergreenWorkbench cache. Other cache directories are not discovered.
    .EXAMPLE
        Clear-EwCache -Confirm:$false
    .EXAMPLE
        Clear-EwCache -CachePath .\Cache -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        In-flight lookups may return their original result but cannot cache it
        after successful invalidation. WhatIf does not create any files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CachePath
    )

    $fail = {
        param([string]$Message)
        [PSCustomObject]@{
            Succeeded = $false; CachePath = $CachePath
            CatalogInvalidated = $false; DefinitionCacheInvalidated = $false
            DefinitionCacheRemoved = $false; RemovedFiles = [string[]]@()
            AppCacheInvalidated = $false; AppCacheRemovedCount = 0
            RemovedEntryCount = 0; EntryCountKnown = $false; Changed = $false
            Error = $Message; Errors = [string[]]@($Message)
        }
    }
    try {
        $CachePath = Get-EwCachePath -CachePath $CachePath -ErrorAction Stop
    }
    catch {
        return (& $fail -Message $_.Exception.Message)
    }
    if (-not $PSCmdlet.ShouldProcess($CachePath, 'Invalidate all Workbench catalogs and clear this application version and definition artifact cache')) {
        return
    }
    $ConfirmPreference = 'None'
    $result = & $fail -Message ''
    $errors = [System.Collections.Generic.List[string]]::new()
    Write-Verbose -Message "EvergreenUI: Clearing Workbench caches; definition path '$CachePath'"
    try {
        Invoke-EwCatalogCache -Action Clear -ErrorAction Stop
        $result.CatalogInvalidated = $true
        $result.Changed = $true
    }
    catch {
        $errors.Add("Catalog invalidation failed: $($_.Exception.Message)")
        Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
    }
    try {
        $appClear = Invoke-EwAppVersionCache -Action Clear -CachePath $CachePath -ErrorAction Stop
        $result.AppCacheInvalidated = $true
        $result.AppCacheRemovedCount = $appClear.RemovedCount
        $result.Changed = $true
        foreach ($appError in @($appClear.Errors)) {
            $errors.Add("Application version cache file deletion failed: $appError")
            Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
        }
    }
    catch {
        $errors.Add("Application version cache invalidation failed: $($_.Exception.Message)")
        Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
    }
    $epochFile = Join-Path -Path $CachePath -ChildPath 'definition-cache-epoch.json'
    $cacheFile = Join-Path -Path $CachePath -ChildPath 'definition-artifact-cache.json'
    try {
        Invoke-EwCacheLock -Path $epochFile -ScriptBlock {
            try {
                $null = Invoke-EwCacheInvalidation -Path $epochFile -ErrorAction Stop
                $result.DefinitionCacheInvalidated = $true
                $result.Changed = $true
                Write-Verbose -Message "EvergreenUI: Definition artifact cache invalidated at '$CachePath'"
            }
            catch {
                $errors.Add("Definition invalidation failed: $($_.Exception.Message)")
                Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
            }
            try {
                if (Test-Path -LiteralPath $cacheFile -ErrorAction Stop) {
                    if (-not (Test-Path -LiteralPath $cacheFile -PathType Leaf -ErrorAction Stop)) {
                        throw "Owned cache payload is not a file: '$cacheFile'."
                    }
                    $entryCount = 0
                    $countKnown = $false
                    try {
                        $entries = @(Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
                        $entryCount = $entries.Count
                        $countKnown = $true
                    }
                    catch {
                        # Invalid payloads can still be deleted; their entry count is unknown.
                        Write-Verbose -Message "EvergreenUI: Cache entry count unavailable: $($_.Exception.Message)"
                    }
                    [System.IO.File]::Delete($cacheFile)
                    $result.RemovedFiles = [string[]]@($cacheFile)
                    $result.RemovedEntryCount = $entryCount
                    $result.EntryCountKnown = $countKnown
                    $result.Changed = $true
                    Write-Verbose -Message "EvergreenUI: Definition artifact cache payload removed: '$cacheFile'"
                }
                else {
                    $result.EntryCountKnown = $true
                    Write-Verbose -Message "EvergreenUI: No definition artifact cache payload at '$cacheFile'"
                }
                $result.DefinitionCacheRemoved = $true
            }
            catch {
                $errors.Add("Definition payload deletion failed: $($_.Exception.Message)")
                Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
            }
        } -ErrorAction Stop
    }
    catch {
        $errors.Add("Definition cache coordination failed; invalidation and deletion skipped: $($_.Exception.Message)")
        Write-Verbose -Message "EvergreenUI: $($errors[$errors.Count - 1])"
    }
    $result.Errors = [string[]]$errors.ToArray()
    $result.Error = $result.Errors -join '; '
    $result.Succeeded = $result.CatalogInvalidated -and $result.AppCacheInvalidated -and $result.DefinitionCacheInvalidated -and $result.DefinitionCacheRemoved
    Write-Verbose -Message "EvergreenUI: Workbench cache clear completed; succeeded: $($result.Succeeded)"
    return $result
}
