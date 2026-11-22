Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Disconnect-EwNerdio {
    <#
    .SYNOPSIS
        Disconnects the Azure and Nerdio Manager sessions.
    .DESCRIPTION
        Clears the in-memory Nerdio token and signs out of the current Azure
        process context.
    .EXAMPLE
        Disconnect-EwNerdio
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Az.Accounts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $wasConnected = $null -ne $script:ewNerdioSession.Context
    $script:ewNerdioSession.Context = $null
    try {
        Assert-EwModule -Name Az.Accounts
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context) {
            return [PSCustomObject]@{ Succeeded = $true; WasConnected = $wasConnected; Error = '' }
        }
        Disconnect-AzAccount -Scope Process -ErrorAction Stop | Out-Null
        Clear-AzContext -Scope Process -Force -ErrorAction Stop | Out-Null
        [PSCustomObject]@{ Succeeded = $true; WasConnected = $true; Error = '' }
    }
    catch {
        [PSCustomObject]@{ Succeeded = $false; WasConnected = $wasConnected; Error = $_.Exception.Message }
    }
}
