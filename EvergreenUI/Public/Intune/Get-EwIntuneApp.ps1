Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntuneApp {
    <#
    .SYNOPSIS
        Lists PSPackageFactory Win32 apps in Microsoft Intune.
    .DESCRIPTION
        Queries Microsoft Graph for Win32 line-of-business apps and returns the
        apps whose notes identify PSPackageFactory as their creator, including
        the definition GUID stored in the notes JSON.
    .EXAMPLE
        Connect-EwIntune -TenantId $tenantId
        Get-EwIntuneApp
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires an active Microsoft Graph context. Follows Graph paging.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Assert-EwModule -Name Microsoft.Graph.Authentication
    if ($null -eq (Get-MgContext -ErrorAction Stop)) {
        throw 'No active Microsoft Graph context. Call Connect-EwIntune first.'
    }

    $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$filter=isOf(''microsoft.graph.win32LobApp'')&$top=999'
    $applications = [System.Collections.Generic.List[object]]::new()
    $page = 0
    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $page++
        Write-Verbose -Message "EvergreenUI: Retrieving Intune Win32 apps page $page"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        foreach ($application in @($response.value)) {
            if ($null -ne $application) {
                $applications.Add($application)
            }
        }
        $uri = if ($response.PSObject.Properties.Name -contains '@odata.nextLink') { [string]$response.'@odata.nextLink' } else { '' }
    }
    Write-Verbose -Message "EvergreenUI: Retrieved $($applications.Count) Intune Win32 apps"

    $property = {
        param([object]$Object, [string]$Name)
        if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
        $Object.PSObject.Properties[$Name].Value
    }
    $rows = foreach ($application in $applications) {
        $notesText = [string](& $property -Object $application -Name 'notes')
        $notes = $null
        $notesValid = 'No'
        if (-not [string]::IsNullOrWhiteSpace($notesText)) {
            try {
                $notes = $notesText | ConvertFrom-Json -ErrorAction Stop
                $notesValid = 'Yes'
            }
            catch {
                # notes are free text in Intune; invalid JSON is reported through NotesValid
                Write-Verbose -Message "EvergreenUI: Intune app '$($application.id)' notes are not JSON: $($_.Exception.Message)"
            }
        }
        $createdBy = [string](& $property -Object $notes -Name 'CreatedBy')
        if (-not ($notesText -match 'PSPackageFactory' -or $createdBy -ieq 'PSPackageFactory')) {
            continue
        }
        $isUpdateApp = & $property -Object $notes -Name 'IsUpdateApp'
        [PSCustomObject]@{
            IntuneAppId = [string]$application.id
            DisplayName = [string](& $property -Object $application -Name 'displayName')
            Publisher = [string](& $property -Object $application -Name 'publisher')
            DisplayVersion = [string](& $property -Object $application -Name 'displayVersion')
            NotesGuid = [string](& $property -Object $notes -Name 'Guid')
            NotesValid = $notesValid
            IsUpdateApp = ($null -ne $isUpdateApp -and [bool]$isUpdateApp)
        }
    }
    @($rows) | Sort-Object -Property Publisher, DisplayName, IntuneAppId
}
