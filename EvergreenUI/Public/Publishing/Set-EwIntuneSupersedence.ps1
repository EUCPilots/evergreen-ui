Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwIntuneSupersedence {
    <#
    .SYNOPSIS
        Sets an Intune Win32 app supersedence relationship.
    .DESCRIPTION
        Makes the new app replace the previous app through Microsoft Graph.
    .PARAMETER NewAppId
        ID of the app that supersedes the older app.
    .PARAMETER PreviousAppId
        ID of the app being superseded.
    .EXAMPLE
        Set-EwIntuneSupersedence -NewAppId $newId -PreviousAppId $oldId
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires an active Microsoft Graph context.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NewAppId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PreviousAppId
    )

    if ($NewAppId -eq $PreviousAppId) {
        throw 'NewAppId and PreviousAppId must be different.'
    }
    if (-not $PSCmdlet.ShouldProcess("Intune app $PreviousAppId", "Set supersedence to $NewAppId")) {
        return
    }
    try {
        Assert-EwModule -Name Microsoft.Graph.Authentication
        if ($null -eq (Get-MgContext -ErrorAction Stop)) {
            throw 'No active Microsoft Graph context. Call Connect-EwIntune first.'
        }
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$NewAppId/relationships"
        $body = [ordered]@{
            '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
            targetId = $PreviousAppId
            supersedenceType = 'update'
        }
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json) `
            -ContentType 'application/json' -ErrorAction Stop | Out-Null
        [PSCustomObject]@{ Succeeded = $true; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = '' }
    }
    catch {
        [PSCustomObject]@{ Succeeded = $false; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = $_.Exception.Message }
    }
}
