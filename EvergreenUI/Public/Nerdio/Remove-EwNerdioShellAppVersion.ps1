Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-EwNerdioShellAppVersion {
    <#
    .SYNOPSIS
        Removes old versions of a Nerdio Manager Shell App.
    .DESCRIPTION
        Keeps the newest versions of a Shell App and deletes the older ones.
        The exact version snapshot can be required to match the reviewed plan.
        Pending or unknown deletes stop the operation and require manual review.
    .PARAMETER Id
        Shell App ID.
    .PARAMETER KeepVersions
        Number of the newest versions to keep. Defaults to one.
    .PARAMETER ExpectedVersionNames
        Exact version names shown in the reviewed preview.
    .PARAMETER ExpectedRemovalVersions
        Exact version names approved for removal.
    .PARAMETER OfferId
        Pruning offer being processed, if the call follows a successful publish.
    .EXAMPLE
        Remove-EwNerdioShellAppVersion -Id 42 -KeepVersions 3 -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$KeepVersions = 1,

        [Parameter()]
        [string[]]$ExpectedVersionNames,

        [Parameter()]
        [string[]]$ExpectedRemovalVersions,

        [Parameter()]
        [string]$OfferId
    )

    process {
        $context = Get-EwNerdioSessionContext
        Assert-EwNerdioWriteAllowed -Context $context -ShellAppId $Id
        if ($OfferId) {
            $recovery = Invoke-EwNerdioRecoveryStore -Action Read
            $offer = @($recovery.PruningOffers | Where-Object Id -eq $OfferId | Select-Object -First 1)
            if ($offer.Count -eq 0) { throw "Pruning offer '$OfferId' is no longer available." }
            Assert-EwNerdioRecoveryDestination -Context $context -Destination $offer[0].Destination
        }
        $plan = Get-EwNerdioShellAppVersionPrunePlan -Id $Id -KeepVersions $KeepVersions
        if (-not $plan.Eligible) {
            throw "Shell App '$Id' cannot be pruned safely: $($plan.Message)"
        }
        $compareNames = {
            param([string[]]$Names)
            $sortedNames = [string[]]$Names.Clone()
            [Array]::Sort($sortedNames, [System.StringComparer]::Ordinal)
            [string]::Join([char]0, $sortedNames)
        }
        if ($PSBoundParameters.ContainsKey('ExpectedVersionNames') -and
            (& $compareNames -Names $ExpectedVersionNames) -cne (& $compareNames -Names $plan.VersionNames)) {
            throw "Shell App '$Id' versions changed after the pruning preview. Review the versions again."
        }
        if ($PSBoundParameters.ContainsKey('ExpectedRemovalVersions') -and
            (& $compareNames -Names $ExpectedRemovalVersions) -cne (& $compareNames -Names $plan.Remove)) {
            throw "Shell App '$Id' removal selection changed after the pruning preview. Review the versions again."
        }
        $candidates = @($plan.Remove)
        $removed = [System.Collections.Generic.List[string]]::new()
        $failed = [System.Collections.Generic.List[string]]::new()
        $pending = [System.Collections.Generic.List[string]]::new()
        $unknown = [System.Collections.Generic.List[string]]::new()
        $outcomes = [System.Collections.Generic.List[object]]::new()
        $blocked = $false
        foreach ($name in $candidates) {
            if (-not $PSCmdlet.ShouldProcess("Shell App $Id version $name", 'Remove')) {
                continue
            }
            $owner = [System.Diagnostics.Process]::GetCurrentProcess()
            try { $ownerStartTimeTicks = $owner.StartTime.ToUniversalTime().Ticks }
            finally { $owner.Dispose() }
            $operation = [ordered]@{
                Id = [guid]::NewGuid().ToString()
                Type = 'Delete'
                Status = 'InProgress'
                StartedAt = [DateTimeOffset]::UtcNow.ToString('o')
                HasActiveLease = $true
                OwnerProcessId = $PID
                OwnerStartTimeTicks = $ownerStartTimeTicks
                Destination = Get-EwNerdioDestinationIdentity -Context $context
                Name = $Id
                AppId = $Id
                Version = $name
                KeepVersions = $KeepVersions
                OfferId = $OfferId
                JobId = ''
                Error = 'The provider delete started but no final outcome was recorded.'
            }
            $uri = "https://$($context.NmeHost)/api/v1/shell-app/$([uri]::EscapeDataString($Id))/version/$([uri]::EscapeDataString($name))"
            $status = 'Unknown'
            $jobId = ''
            $errorMessage = ''
            $recoveryLease = [System.Threading.Semaphore]::new(0, 1, "Local\EvergreenWorkbench.NerdioOperation.$($operation.Id)")
            try {
                $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $operation
                try {
                    $response = Invoke-EwNerdioApiRequest -Method DELETE -Uri $uri -AccessToken $context.AccessToken
                    $job = Get-EwFirstPropertyValue -InputObject $response -Name 'job'
                    $jobId = [string](Get-EwFirstPropertyValue -InputObject $job -Name 'id')
                    $providerStatus = [string](Get-EwFirstPropertyValue -InputObject $job -Name 'status')
                    $status = switch ($providerStatus) {
                        'Completed' { 'Completed' }
                        'Pending' { 'Pending' }
                        'Failed' { 'Failed' }
                        default { 'Unknown' }
                    }
                    if ($status -eq 'Completed') {
                        $removed.Add($name)
                        $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $operation.Id
                        Write-Verbose -Message "EvergreenUI: Removed Shell App '$Id' version '$name'"
                    }
                    elseif ($status -eq 'Failed') {
                        $failed.Add($name)
                        $errorMessage = "Nerdio returned '$providerStatus'."
                        $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $operation.Id
                        Write-Verbose -Message "EvergreenUI: Removing Shell App '$Id' version '$name' returned status '$providerStatus'"
                    }
                    else {
                        $operation.Status = $status
                        $operation.JobId = $jobId
                        $operation.Error = "Nerdio returned '$providerStatus'; inspect the operation before continuing."
                        $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $operation
                        if ($status -eq 'Pending') { $pending.Add($name) } else { $unknown.Add($name) }
                    }
                }
                catch {
                    $status = 'Unknown'
                    $errorMessage = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
                    $operation.Status = 'Unknown'
                    $operation.Error = $errorMessage
                    $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $operation
                    $unknown.Add($name)
                    Write-Verbose -Message "EvergreenUI: Removing Shell App '$Id' version '$name' has an unknown outcome: $errorMessage"
                }
            }
            finally { $recoveryLease.Dispose() }
            $outcomes.Add([PSCustomObject]@{ Version = $name; Status = $status; JobId = $jobId; Error = $errorMessage })
            if ($status -in @('Pending', 'Unknown')) {
                $blocked = $true
                break
            }
        }
        if ($OfferId -and -not $WhatIfPreference) {
            $state = Invoke-EwNerdioRecoveryStore -Action Read
            $offer = @($state.PruningOffers | Where-Object Id -eq $OfferId | Select-Object -First 1)
            if ($offer.Count -gt 0 -and
                ($candidates.Count -eq 0 -or
                    (-not $blocked -and $failed.Count -eq 0 -and $outcomes.Count -eq $candidates.Count))) {
                $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOfferId $OfferId
            }
        }

        [PSCustomObject]@{
            Id = $Id
            OfferId = $OfferId
            TotalVersions = $plan.TotalVersions
            KeepVersions = $KeepVersions
            RequestedRemovals = $candidates.Count
            RemovedCount = $removed.Count
            RemovedVersions = $removed.ToArray()
            FailedCount = $failed.Count
            FailedVersions = $failed.ToArray()
            PendingVersions = $pending.ToArray()
            UnknownVersions = $unknown.ToArray()
            Outcomes = $outcomes.ToArray()
        }
    }
}
