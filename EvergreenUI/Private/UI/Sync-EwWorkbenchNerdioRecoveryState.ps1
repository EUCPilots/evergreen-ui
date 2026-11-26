Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Sync-EwWorkbenchNerdioRecoveryState {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    try {
        $recovery = Invoke-EwNerdioRecoveryStore -Action Read
        $State.NerdioRecoveryError = ''
        $State.NerdioPruningOffers = @($recovery.PruningOffers)
        $State.NerdioBlockedOutcomes = @{}
        for ($index = $State.NerdioResults.Count - 1; $index -ge 0; $index--) {
            if ($State.NerdioResults[$index].Status -in @('Pending', 'Unknown', 'InProgress')) {
                $State.NerdioResults.RemoveAt($index)
            }
        }
        foreach ($operation in @($recovery.Operations)) {
            $status = if ($operation.Status -eq 'InProgress') { 'Unknown' } else { [string]$operation.Status }
            $row = [PSCustomObject]@{
                Name = [string]$operation.Name
                Version = [string]$operation.Version
                Status = $status
                Operation = [string]$operation.Type
                AppId = [string]$operation.AppId
                JobId = [string]$operation.JobId
                BlobName = [string]$operation.BlobName
                NmeHost = [string]$operation.Destination.NmeHost
                Destination = (@('TenantId', 'SubscriptionId', 'NmeHost', 'ResourceGroupName', 'StorageAccountName', 'ContainerName') |
                    ForEach-Object { [string]$operation.Destination[$_] }) -join ' / '
                Error = [string]$operation.Error
                DefinitionPath = [string]$operation.DefinitionPath
                RecoveryOperationId = [string]$operation.Id
                OutcomeKey = [string]$operation.Id
            }
            $State.NerdioResults.Add($row)
            $State.NerdioBlockedOutcomes[$row.OutcomeKey] = [PSCustomObject]@{
                Type = [string]$operation.Type
                AppId = [string]$operation.AppId
            }
        }
        $State.NerdioPublishResultsListView.Items.Refresh()
        return $true
    }
    catch {
        $State.NerdioRecoveryError = $_.Exception.Message
        $State.NerdioBlockedOutcomes['RecoveryStoreError'] = [PSCustomObject]@{ Type = 'Error'; AppId = '' }
        $State.NerdioConnectionStatusLabel.Text = "Recovery state unavailable: $($State.NerdioRecoveryError)"
        Write-EwWorkbenchLog -State $State -Message "Nerdio recovery state could not be loaded: $($State.NerdioRecoveryError)" -Level Error
        return $false
    }
}
