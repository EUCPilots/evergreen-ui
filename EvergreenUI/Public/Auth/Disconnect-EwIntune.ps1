Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Disconnect-EwIntune {
    <#
    .SYNOPSIS
        Disconnects the current Microsoft Graph session.
    .DESCRIPTION
        Signs out of Microsoft Graph in the current PowerShell process.
    .EXAMPLE
        Disconnect-EwIntune
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Microsoft.Graph.Authentication.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        Assert-EwModule -Name Microsoft.Graph.Authentication
        $context = Get-MgContext -ErrorAction Stop
        if ($null -eq $context) {
            return [PSCustomObject]@{ Succeeded = $true; WasConnected = $false; Error = '' }
        }
        Disconnect-MgGraph -ErrorAction Stop | Out-Null
        [PSCustomObject]@{ Succeeded = $true; WasConnected = $true; Error = '' }
    }
    catch {
        [PSCustomObject]@{ Succeeded = $false; WasConnected = $false; Error = $_.Exception.Message }
    }
}
