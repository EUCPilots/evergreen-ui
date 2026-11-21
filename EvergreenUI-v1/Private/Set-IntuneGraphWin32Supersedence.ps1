#Requires -Version 5.1
<#
.SYNOPSIS
    Configures a supersedence relationship between two Intune Win32 apps via the
    Microsoft Graph API using the active Connect-MgGraph session.

.DESCRIPTION
    Posts a mobileAppSupersedence relationship from the new app (NewAppId) to the
    old app (PreviousAppId) with supersedenceType 'update', so Intune replaces
    the old installation with the new one on enrolled devices.

    The call uses Invoke-MgGraphRequest only; Connect-MSIntuneGraph is never used.

.PARAMETER NewAppId
    The Intune app ID of the newly imported Win32 app (the superseding app).

.PARAMETER PreviousAppId
    The Intune app ID of the existing Win32 app to be superseded.

.PARAMETER SyncHash
    The shared UI synchronised hashtable used by Write-UILog.

.OUTPUTS
    PSCustomObject with:
        Succeeded : bool
        Error     : string - populated on failure
#>
function Set-IntuneGraphWin32Supersedence {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$NewAppId,

        [Parameter(Mandatory)]
        [string]$PreviousAppId,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    $fail = {
        param([string]$Msg)
        return [PSCustomObject]@{ Succeeded = $false; Error = $Msg }
    }

    if ([string]::IsNullOrWhiteSpace($NewAppId)) {
        return (& $fail 'NewAppId is required.')
    }
    if ([string]::IsNullOrWhiteSpace($PreviousAppId)) {
        return (& $fail 'PreviousAppId is required.')
    }
    if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
        return (& $fail 'Invoke-MgGraphRequest is not available.')
    }

    Write-UILog -Message "Configuring supersedence: new app '$NewAppId' supersedes '$PreviousAppId'..." -Level Info -SyncHash $SyncHash

    $uri  = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$NewAppId/relationships"
    $body = [ordered]@{
        '@odata.type'     = '#microsoft.graph.mobileAppSupersedence'
        'targetId'        = $PreviousAppId
        'supersedenceType' = 'update'
    }

    Write-UILog -Message "POST $uri" -Level Cmd -SyncHash $SyncHash

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri $uri `
            -Body ($body | ConvertTo-Json) `
            -ContentType 'application/json' `
            -ErrorAction Stop | Out-Null
    }
    catch {
        return (& $fail "Failed to set supersedence from '$NewAppId' -> '$PreviousAppId': $($_.Exception.Message)")
    }

    Write-UILog -Message "Supersedence configured successfully." -Level Info -SyncHash $SyncHash

    return [PSCustomObject]@{ Succeeded = $true; Error = '' }
}


