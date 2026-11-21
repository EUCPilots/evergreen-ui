Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EwIntune {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for Intune app management.
    .DESCRIPTION
        Starts a delegated Microsoft Graph session using the Intune app write
        scope and returns non-secret connection metadata.
    .PARAMETER TenantId
        Optional Entra tenant ID used to scope sign-in.
    .PARAMETER UseDeviceCode
        Uses device-code authentication instead of the default browser flow.
    .EXAMPLE
        Connect-EwIntune -TenantId '00000000-0000-0000-0000-000000000000'
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Microsoft.Graph.Authentication.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$UseDeviceCode
    )

    try {
        Assert-EwModule -Name Microsoft.Graph.Authentication
        $parameters = @{
            Scopes = @('DeviceManagementApps.ReadWrite.All')
            ContextScope = 'Process'
            NoWelcome = $true
            ErrorAction = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $parameters.TenantId = $TenantId.Trim()
        }
        if ($UseDeviceCode) {
            $parameters.UseDeviceCode = $true
        }
        Connect-MgGraph @parameters | Out-Null
        $context = Get-MgContext -ErrorAction Stop
        if ($null -eq $context) {
            throw 'Connect-MgGraph completed without an active Graph context.'
        }
        [PSCustomObject]@{
            Succeeded = $true
            AccountId = [string]$context.Account
            TenantId = [string]$context.TenantId
            AuthMethod = 'Connect-MgGraph'
            Error = ''
        }
    }
    catch {
        [PSCustomObject]@{
            Succeeded = $false
            AccountId = ''
            TenantId = ''
            AuthMethod = ''
            Error = $_.Exception.Message
        }
    }
}
