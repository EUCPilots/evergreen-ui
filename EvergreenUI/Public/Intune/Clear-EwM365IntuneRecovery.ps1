Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwM365IntuneRecovery {
    <#
    .SYNOPSIS
        Acknowledges a reviewed Microsoft 365 Intune outcome.
    .DESCRIPTION
        Removes one recovery record after an operator has inspected the
        provider. Does not retry, modify or delete any Intune app.
    .PARAMETER Id
        Recovery record ID belonging to the active Intune tenant.
    .PARAMETER Reviewed
        Confirms that the operator reviewed the outcome in Intune.
    .EXAMPLE
        Clear-EwM365IntuneRecovery -Id $record.Id -Reviewed
    .NOTES
        Active in-progress operations cannot be acknowledged.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Id,
        [Parameter(Mandatory)][switch]$Reviewed
    )

    if (-not $Reviewed) { throw 'Review the provider outcome before acknowledging it.' }
    $records = @(Get-EwM365IntuneRecovery | Where-Object { $_.Id -eq $Id })
    if ($records.Count -ne 1) { throw 'The recovery record is unavailable for the connected tenant.' }
    if ($PSCmdlet.ShouldProcess($Id, 'Acknowledge reviewed Intune outcome')) {
        $null = Invoke-EwM365IntuneRecoveryStore -Action Remove -Id $Id
    }
}
