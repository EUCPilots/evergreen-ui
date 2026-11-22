Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Disconnect-EwAzure {
    <#
    .SYNOPSIS
        Signs out of the Azure process context.
    .DESCRIPTION
        Disconnects Az.Accounts and clears the process-scoped Azure context.
        The Nerdio Manager token is also cleared because it depends on the
        Azure storage context.
    .EXAMPLE
        Disconnect-EwAzure
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Az.Accounts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $nerdioWasConnected = $null -ne $script:ewNerdioSession.Context
    $script:ewNerdioSession.Context = $null
    if ($nerdioWasConnected) {
        Write-Verbose -Message 'EvergreenUI: Cleared Nerdio Manager token during Azure sign-out.'
    }

    try {
        Assert-EwModule -Name Az.Accounts
        $context = Get-AzContext -ErrorAction Stop
        $wasConnected = $null -ne $context
        if ($wasConnected) {
            Write-Verbose -Message "EvergreenUI: Disconnecting Azure account '$($context.Account.Id)'."
            Disconnect-AzAccount -Scope Process -ErrorAction Stop | Out-Null
        }
        else {
            Write-Verbose -Message 'EvergreenUI: No Azure context found; clearing process context only.'
        }
        Clear-AzContext -Scope Process -Force -ErrorAction Stop | Out-Null
        Write-Verbose -Message 'EvergreenUI: Azure process context cleared.'
        [PSCustomObject]@{ Succeeded = $true; WasConnected = $wasConnected; Error = '' }
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Azure sign-out failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Succeeded = $false; WasConnected = $nerdioWasConnected; Error = $_.Exception.Message }
    }
}