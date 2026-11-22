Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwM365IntuneRecoveryStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Read', 'Begin', 'Update', 'Remove', 'Finish')][string]$Action,
        [System.Collections.IDictionary]$Record,
        [string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { throw 'APPDATA is not set; Intune recovery state is unavailable.' }
    $path = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\m365-intune-recovery.json'
    $mutex = [System.Threading.Mutex]::new($false, 'Local\EvergreenWorkbench.M365IntuneRecovery')
    $locked = $false
    try {
        $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
        if (-not $locked) { throw 'Timed out waiting for Microsoft 365 Intune recovery state.' }
        $state = if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        } else { [ordered]@{ SchemaVersion = 1; Operations = @() } }
        if ($state -isnot [System.Collections.IDictionary] -or -not $state.Contains('SchemaVersion') -or
            $state.SchemaVersion -ne 1 -or -not $state.Contains('Operations')) {
            throw 'Microsoft 365 Intune recovery state is invalid or unsupported.'
        }
        if ($Action -eq 'Read') { return $state }
        if ($Action -in @('Begin', 'Update') -and $null -eq $Record) { throw 'A recovery record is required.' }
        if ($Action -eq 'Begin' -and @($state.Operations | Where-Object {
                    [string]$_.TenantId -ieq [string]$Record.TenantId -and
                    [string]$_.ConfigurationId -ieq [string]$Record.ConfigurationId
                }).Count -gt 0) {
            throw 'A previous Microsoft 365 Intune outcome needs explicit review before another write.'
        }
        if ($Action -eq 'Update' -and @($state.Operations | Where-Object { $_.Id -eq $Record.Id }).Count -ne 1) {
            throw 'The Microsoft 365 Intune recovery record is missing or ambiguous.'
        }
        if ($Action -in @('Remove', 'Finish') -and @($state.Operations | Where-Object { $_.Id -eq $Id }).Count -ne 1) {
            throw 'The Microsoft 365 Intune recovery record is missing or ambiguous.'
        }
        if ($Action -eq 'Remove') {
            $item = @($state.Operations | Where-Object { $_.Id -eq $Id })[0]
            if ($item.Status -eq 'InProgress') {
                try {
                    $owner = [System.Diagnostics.Process]::GetProcessById([int]$item.OwnerProcessId)
                    try {
                        if ($owner.StartTime.ToUniversalTime().Ticks -eq [long]$item.OwnerStartTimeTicks) {
                            throw 'The Intune operation is still running and cannot be acknowledged.'
                        }
                    }
                    finally { $owner.Dispose() }
                }
                catch [System.ArgumentException] {
                    Write-Verbose -Message 'EvergreenUI: The recovery operation owner is no longer running.'
                }
            }
        }
        $recordId = if ($Action -in @('Remove', 'Finish')) { $Id } else { [string]$Record.Id }
        $operations = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($state.Operations)) {
            if ([string]$item.Id -ne $recordId) { $operations.Add($item) }
        }
        if ($Action -notin @('Remove', 'Finish')) { $operations.Add($Record) }
        $state.Operations = $operations.ToArray()
        $directory = Split-Path -Path $path -Parent
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        $temporaryPath = Join-Path -Path $directory -ChildPath ('.m365-intune-recovery-{0}.tmp' -f [guid]::NewGuid())
        $backupPath = "$temporaryPath.bak"
        try {
            [IO.File]::WriteAllText($temporaryPath, (ConvertTo-Json -InputObject $state -Depth 10 -ErrorAction Stop),
                [Text.UTF8Encoding]::new($false))
            if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::Replace($temporaryPath, $path, $backupPath) }
            else { [IO.File]::Move($temporaryPath, $path) }
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop }
        }
        Write-Verbose -Message 'EvergreenUI: Microsoft 365 Intune recovery state saved.'
        return $state
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
