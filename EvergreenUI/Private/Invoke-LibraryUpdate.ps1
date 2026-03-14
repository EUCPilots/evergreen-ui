#Requires -Version 5.1
<#
.SYNOPSIS
    Runs Start-EvergreenLibraryUpdate against the configured library path.

.DESCRIPTION
    Wraps Start-EvergreenLibraryUpdate -Path, running the update on a background
    runspace created by New-WpfRunspace so the UI thread stays responsive. Each
    significant event is forwarded to Write-UILog.

    Should be called from a runspace variable block (see New-WpfRunspace). The
    function is synchronous within that runspace - it runs the library update to
    completion (or error) before returning.

.PARAMETER SyncHash
    Shared synchronised hashtable. Reads:
        Config.LibraryPath  - string path to the Evergreen library root
        IsRunning           - bool set True during execution, False on completion

.EXAMPLE
    # Typically called inside a New-WpfRunspace scriptblock:
    $rs = New-WpfRunspace -SyncHash $syncHash -Script {
        Invoke-LibraryUpdate -SyncHash $syncHash
    }
#>
function Invoke-LibraryUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $libraryPath = $SyncHash.Config.LibraryPath

    if ([string]::IsNullOrWhiteSpace($libraryPath)) {
        Write-UILog -SyncHash $SyncHash -Message 'Library path is not configured. Set a library path in Settings before updating.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $libraryPath -PathType Container)) {
        Write-UILog -SyncHash $SyncHash -Message "Library path does not exist: $libraryPath" -Level Error
        return
    }

    $SyncHash.IsRunning = $true
    Write-UILog -SyncHash $SyncHash -Message "Starting library update: $libraryPath" -Level Info
    Write-UILog -SyncHash $SyncHash -Message "Start-EvergreenLibraryUpdate -Path '$libraryPath'" -Level Cmd

    try {
        Start-EvergreenLibraryUpdate -Path $libraryPath -ErrorAction Stop

        Write-UILog -SyncHash $SyncHash -Message 'Library update completed successfully.' -Level Info
    }
    catch {
        Write-UILog -SyncHash $SyncHash -Message "Library update failed: $_" -Level Error
    }
    finally {
        $SyncHash.IsRunning = $false
    }
}
