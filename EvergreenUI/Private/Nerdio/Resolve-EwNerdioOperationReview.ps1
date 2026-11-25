Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EwNerdioOperationReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId,

        [Parameter(Mandatory)]
        [ValidateSet('Completed', 'Failed')]
        [string]$Outcome
    )

    Write-Verbose -Message "EvergreenUI: Reviewing Nerdio operation '$OperationId' as '$Outcome'"
    $context = Get-EwNerdioSessionContext
    $state = Invoke-EwNerdioRecoveryStore -Action Read
    $operation = @($state.Operations | Where-Object Id -eq $OperationId | Select-Object -First 1)
    if ($operation.Count -eq 0) {
        throw 'The operation is no longer waiting for review.'
    }
    $operation = $operation[0]
    Assert-EwNerdioRecoveryDestination -Context $context -Destination $operation.Destination

    $offer = $null
    if ($Outcome -eq 'Completed' -and $operation.Type -eq 'Publish') {
        $apps = @(Get-EwNerdioShellApp)
        $appMatches = if ($operation.AppId) {
            @($apps | Where-Object Id -eq $operation.AppId)
        }
        else {
            @($apps | Where-Object {
                    $_.Name -ceq $operation.Name -and $_.Publisher -ceq $operation.Publisher
                })
        }
        if ($appMatches.Count -ne 1) {
            throw 'The refreshed Nerdio Shell App list does not identify exactly one published app.'
        }
        $plan = Get-EwNerdioShellAppVersionPrunePlan -Id $appMatches[0].Id -PublishedVersion $operation.Version
        if (-not $plan.Eligible) {
            throw "The published version could not be verified as the unique newest version: $($plan.Message)"
        }
        $offer = [ordered]@{
            Id = [guid]::NewGuid().ToString()
            Type = 'PruningOffer'
            CreatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Destination = $operation.Destination
            AppId = [string]$appMatches[0].Id
            Name = [string]$appMatches[0].Name
            Publisher = [string]$appMatches[0].Publisher
            DefinitionPath = [string]$operation.DefinitionPath
            PublishedVersion = [string]$operation.Version
        }
    }
    elseif ($Outcome -eq 'Completed' -and $operation.Type -eq 'Delete') {
        $versions = @(Get-EwNerdioShellAppVersion -Id $operation.AppId | ForEach-Object {
                [string](Get-EwFirstPropertyValue -InputObject $_ -Name 'name', 'version', 'displayVersion')
            })
        if ($operation.Version -cin $versions) {
            throw "The refreshed Nerdio version list still contains '$($operation.Version)'; the deletion is not confirmed."
        }
        $offer = @($state.PruningOffers | Where-Object Id -eq $operation.OfferId | Select-Object -First 1)
        if ($offer.Count -gt 0) {
            $offer = $offer[0]
            $plan = Get-EwNerdioShellAppVersionPrunePlan -Id $operation.AppId -KeepVersions ([int]$operation.KeepVersions) `
                -PublishedVersion ([string]$offer.PublishedVersion)
            if ($plan.Eligible -and $plan.Remove.Count -eq 0) {
                $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $OperationId -RemoveOfferId ([string]$offer.Id)
                Write-Verbose -Message "EvergreenUI: Completed deletion review for '$($operation.AppId)' version '$($operation.Version)'"
                return [PSCustomObject]@{ Succeeded = $true; OperationId = $OperationId; Outcome = $Outcome; OfferId = '' }
            }
        }
    }

    if ($null -ne $offer) {
        $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $OperationId -UpsertOffer $offer
    }
    else {
        $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $OperationId
    }
    Write-Verbose -Message "EvergreenUI: Nerdio operation '$OperationId' review saved as '$Outcome'"
    [PSCustomObject]@{
        Succeeded = $true
        OperationId = $OperationId
        Outcome = $Outcome
        OfferId = if ($null -ne $offer) { [string]$offer.Id } else { '' }
    }
}
