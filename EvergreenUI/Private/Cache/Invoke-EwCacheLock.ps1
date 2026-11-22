Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwCacheLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $identity = [System.IO.Path]::GetFullPath($Path).ToUpperInvariant()
    $hash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($identity)))
    $mutex = [System.Threading.Mutex]::new($false, "Global\EvergreenWorkbench.Cache.$hash")
    $hasMutex = $false
    try {
        try {
            $hasMutex = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
        }
        catch [System.Threading.AbandonedMutexException] {
            # The previous owner exited; WaitOne has still acquired the mutex.
            $hasMutex = $true
            Write-Verbose -Message "EvergreenUI: Acquired abandoned cache lock for '$Path': $($_.Exception.Message)"
        }
        if (-not $hasMutex) {
            throw "Timed out waiting for cache lock for '$Path'."
        }
        & $ScriptBlock
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}
