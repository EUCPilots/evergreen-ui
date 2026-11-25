Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInfoJobCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [ValidateSet('Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions', 'About')]
        [string[]]$Kind = @('Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions', 'About'),
        [switch]$Closing
    )

    if ($Closing) {
        $State.InfoClosed = $true
    }
    foreach ($jobKind in $Kind) {
        $slot = $State.InfoJobs[$jobKind]
        if ($Closing) {
            $slot.Pending = $null
        }
        if ($null -eq $slot.ActiveId) {
            continue
        }
        try {
            $job = Get-EwJob -Id $slot.ActiveId -ErrorAction Stop
            if ($job.State -in @('NotStarted', 'Running', 'Stopping')) {
                $job = Stop-EwJob -Id $slot.ActiveId -Confirm:$false -ErrorAction Stop
            }
            Remove-EwJob -Id $job.Id -Confirm:$false -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Removed background check $($job.Id)"
            $slot.ActiveId = $null
            $slot.ActiveRequest = $null
        }
        catch {
            $detail = $_.Exception.Message
            $message = "Could not remove background check $($slot.ActiveId): $detail"
            if ($Closing) {
                Write-Verbose -Message "EvergreenUI: $message"
            }
            else {
                Write-EwWorkbenchLog -State $State -Message $message -Level Warning -PreserveStatus
                if ($jobKind -ne 'About') {
                    $State["${jobKind}FolderStatusLabel"].Text = "Could not replace the previous folder check: $detail"
                }
            }
        }
    }
}
