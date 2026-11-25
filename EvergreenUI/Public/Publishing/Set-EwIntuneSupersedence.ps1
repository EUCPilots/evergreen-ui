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
    .PARAMETER SkipIfExists
        Checks existing relationships before posting, allowing a safe retry.
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
        [string]$PreviousAppId,

        [Parameter()]
        [switch]$SkipIfExists
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
        if ($SkipIfExists) {
            $nextUri = $uri
            while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
                $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri -OutputType PSObject -ErrorAction Stop
                foreach ($relationship in @($response.value)) {
                    if ($null -eq $relationship) { continue }
                    $targetId = [string](Get-EwObjectPropertyValue -Object $relationship -Name targetId -Default '')
                    $relationshipType = [string](Get-EwObjectPropertyValue -Object $relationship -Name '@odata.type' -Default '')
                    if ($targetId -eq $PreviousAppId -and [string]::IsNullOrWhiteSpace($relationshipType)) {
                        throw 'An existing relationship to the previous app has no type. Review it before retrying.'
                    }
                    if ($relationshipType -eq '#microsoft.graph.mobileAppSupersedence' -and $targetId -eq $PreviousAppId) {
                        $targetType = [string](Get-EwObjectPropertyValue -Object $relationship -Name targetType -Default '')
                        if ($targetType -ne 'parent') {
                            throw 'An existing supersedence relationship has an unexpected direction. Review it before retrying.'
                        }
                        Write-Verbose -Message "EvergreenUI: Supersedence already exists for '$NewAppId' and '$PreviousAppId'"
                        return [PSCustomObject]@{ Succeeded = $true; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = '' }
                    }
                }
                $nextUri = [string](Get-EwObjectPropertyValue -Object $response -Name '@odata.nextLink' -Default '')
            }
        }
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
