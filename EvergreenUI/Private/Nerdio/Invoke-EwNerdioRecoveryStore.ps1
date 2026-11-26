Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwNerdioRecoveryStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Read', 'Update', 'Review')]
        [string]$Action,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [System.Collections.IDictionary]$UpsertOperation,

        [Parameter()]
        [string]$RemoveOperationId,

        [Parameter()]
        [System.Collections.IDictionary]$UpsertOffer,

        [Parameter()]
        [string]$RemoveOfferId,

        [Parameter()]
        [psobject]$Context
    )

    if (-not $Path) {
        if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
            throw 'APPDATA is not set; the Nerdio recovery path cannot be resolved.'
        }
        $Path = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\nerdio-recovery.json'
    }

    $mutex = [System.Threading.Mutex]::new($false, 'Local\EvergreenWorkbench.NerdioRecovery')
    $hasMutex = $false
    try {
        $hasMutex = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
        if (-not $hasMutex) {
            throw 'Timed out waiting to update Nerdio recovery state.'
        }

        $state = if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        else {
            [ordered]@{ SchemaVersion = 1; Operations = @(); PruningOffers = @() }
        }
        if ($state -isnot [System.Collections.IDictionary] -or -not $state.Contains('SchemaVersion') -or
            $state.SchemaVersion -ne 1 -or
            -not $state.Contains('Operations') -or -not $state.Contains('PruningOffers')) {
            throw "Unsupported or invalid Nerdio recovery state in '$Path'."
        }

        if ($Action -eq 'Read') {
            return $state
        }
        if ($Action -eq 'Review') {
            $matchingOperations = @($state.Operations | Where-Object { [string]$_.Id -eq $RemoveOperationId })
            if ($matchingOperations.Count -ne 1 -or $null -eq $Context) {
                throw 'The Nerdio recovery record is missing or ambiguous.'
            }
            $operation = $matchingOperations[0]
            Assert-EwNerdioRecoveryDestination -Context $Context -Destination $operation.Destination
            if ($operation.Contains('HasActiveLease') -and $operation.HasActiveLease) {
                $operationId = [guid]::Empty
                if (-not [guid]::TryParse([string]$operation.Id, [ref]$operationId)) {
                    throw 'The Nerdio recovery operation ID is invalid.'
                }
                $lease = $null
                if ([System.Threading.Semaphore]::TryOpenExisting("Local\EvergreenWorkbench.NerdioOperation.$operationId", [ref]$lease)) {
                    $lease.Dispose()
                    throw 'The Nerdio operation is still running and cannot be acknowledged.'
                }
            }
        }

        $operations = [System.Collections.Generic.List[object]]::new()
        foreach ($operation in @($state.Operations)) {
            if ([string]$operation.Id -ne $RemoveOperationId -and
                ($null -eq $UpsertOperation -or [string]$operation.Id -ne [string]$UpsertOperation.Id)) {
                $operations.Add($operation)
            }
        }
        if ($null -ne $UpsertOperation) {
            $operations.Add($UpsertOperation)
        }

        $offers = [System.Collections.Generic.List[object]]::new()
        foreach ($offer in @($state.PruningOffers)) {
            if ([string]$offer.Id -ne $RemoveOfferId -and
                ($null -eq $UpsertOffer -or [string]$offer.Id -ne [string]$UpsertOffer.Id)) {
                $offers.Add($offer)
            }
        }
        if ($null -ne $UpsertOffer) {
            $offers.Add($UpsertOffer)
        }
        $state.Operations = $operations.ToArray()
        $state.PruningOffers = $offers.ToArray()

        $directory = Split-Path -Path $Path -Parent
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        $temporaryPath = Join-Path -Path $directory -ChildPath ('.nerdio-recovery-{0}.tmp' -f [guid]::NewGuid())
        $backupPath = "$temporaryPath.bak"
        try {
            $json = ConvertTo-Json -InputObject $state -Depth 20 -ErrorAction Stop
            [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
            }
            else {
                [System.IO.File]::Move($temporaryPath, $Path)
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
            }
            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
            }
        }
        Write-Verbose -Message "EvergreenUI: Nerdio recovery state saved to $Path"
        return $state
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}
