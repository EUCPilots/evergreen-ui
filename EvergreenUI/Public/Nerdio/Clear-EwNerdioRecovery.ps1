Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwNerdioRecovery {
    <#
    .SYNOPSIS
        Acknowledges an unresolved Nerdio operation without asserting its outcome.
    .DESCRIPTION
        Removes one recovery record for the connected destination. This does not verify, retry, or cancel the provider operation.
        A retry can duplicate or conflict with a provider operation that is still running.
    .PARAMETER OperationId
        The exact recovery operation ID.
    .EXAMPLE
        Clear-EwNerdioRecovery -OperationId $record.Id
    .NOTES
        Confirmed active local operations cannot be acknowledged.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OperationId)

    $context = Get-EwNerdioSessionContext
    Write-Warning -Message 'The Nerdio outcome is not verified. Retrying may duplicate or conflict with a provider operation still running.'
    if ($PSCmdlet.ShouldProcess($OperationId, 'Acknowledge an unresolved Nerdio outcome without verification')) {
        $null = Invoke-EwNerdioRecoveryStore -Action Review -Context $context -RemoveOperationId $OperationId
        Write-Verbose -Message "EvergreenUI: Acknowledged unresolved Nerdio operation '$OperationId' without asserting its outcome."
    }
}
