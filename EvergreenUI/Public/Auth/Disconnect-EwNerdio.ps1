Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Disconnect-EwNerdio {
    <#
    .SYNOPSIS
        Disconnects the Nerdio Manager session and any associated Azure session.
    .DESCRIPTION
        Clears the in-memory Nerdio token. For a full connection, also signs
        out of the current Azure process context. An API-only disconnect does
        not change Azure context.
    .EXAMPLE
        Disconnect-EwNerdio
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        A full connection requires Az.Accounts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $context = $script:ewNerdioSession.Context
    $wasConnected = $null -ne $context
    $apiOnly = [bool]$script:ewNerdioSession.ApiOnly
    $script:ewNerdioSession.Context = $null
    $script:ewNerdioSession.ApiOnly = $false
    if ($apiOnly) {
        return [PSCustomObject]@{ Succeeded = $true; WasConnected = $wasConnected; Error = '' }
    }
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
