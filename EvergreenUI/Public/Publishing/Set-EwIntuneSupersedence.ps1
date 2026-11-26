Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-EwIntuneSupersedence {
    <#
    .SYNOPSIS
        Sets an Intune Win32 app supersedence relationship.
    .DESCRIPTION
        Makes the new app replace the previous app through the Microsoft Graph
        updateRelationships action, preserving existing app relationships.
    .PARAMETER NewAppId
        ID of the app that supersedes the older app.
    .PARAMETER PreviousAppId
        ID of the app being superseded.
    .PARAMETER SkipIfExists
        Returns success without writing when the requested relationship already
        exists, allowing a safe retry.
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
        $relationships = [System.Collections.Generic.List[object]]::new()
        $nextUri = $uri
        while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
            Write-Verbose -Message "EvergreenUI: Reading existing relationships for '$NewAppId' before updating supersedence"
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
                    if (-not $SkipIfExists) {
                        throw 'Supersedence already exists. Use SkipIfExists after reviewing the existing relationship.'
                    }
                    Write-Verbose -Message "EvergreenUI: Supersedence already exists for '$NewAppId' and '$PreviousAppId'"
                    return [PSCustomObject]@{ Succeeded = $true; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = '' }
                }
                $relationships.Add($relationship)
            }
            $nextUri = [string](Get-EwObjectPropertyValue -Object $response -Name '@odata.nextLink' -Default '')
        }
        Write-Verbose -Message "EvergreenUI: Preserving $($relationships.Count) existing relationships for '$NewAppId'"
        $relationships.Add([ordered]@{
            '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
            targetId = $PreviousAppId
            targetType = 'parent'
            supersedenceType = 'update'
        })
        $body = @{ relationships = $relationships.ToArray() }
        $updateUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$NewAppId/updateRelationships"
        Write-Verbose -Message "EvergreenUI: Creating update supersedence from '$NewAppId' to previous app '$PreviousAppId' (targetType=parent)"
        Invoke-MgGraphRequest -Method POST -Uri $updateUri -Body ($body | ConvertTo-Json -Depth 20) `
            -ContentType 'application/json' -ErrorAction Stop | Out-Null
        Write-Verbose -Message "EvergreenUI: Supersedence created for '$NewAppId' and '$PreviousAppId'"
        [PSCustomObject]@{ Succeeded = $true; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = '' }
    }
    catch {
        $message = $_.Exception.Message
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $message = "$message $($_.ErrorDetails.Message)"
        }
        Write-Verbose -Message "EvergreenUI: Supersedence failed for '$NewAppId' and '$PreviousAppId': $message"
        [PSCustomObject]@{ Succeeded = $false; NewAppId = $NewAppId; PreviousAppId = $PreviousAppId; Error = $message }
    }
}
