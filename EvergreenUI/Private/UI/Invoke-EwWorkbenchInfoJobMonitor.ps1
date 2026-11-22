Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInfoJobMonitor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    foreach ($kind in 'Download', 'Library', 'About') {
        $slot = $State.InfoJobs[$kind]
        if ($null -eq $slot.ActiveId) {
            continue
        }
        $job = $null
        $errorMessage = ''
        try {
            $job = Get-EwJob -Id $slot.ActiveId -ErrorAction Stop
        }
        catch {
            $errorMessage = "Could not read the background check: $($_.Exception.Message)"
        }
        if ($null -ne $job -and $job.State -in @('NotStarted', 'Running', 'Stopping')) {
            continue
        }

        $request = $slot.ActiveRequest
        $slot.ActiveId = $null
        $slot.ActiveRequest = $null
        if ($null -ne $job) {
            if ($job.State -ne 'Completed' -or $null -ne $job.TerminatingError -or @($job.Errors).Count -gt 0) {
                if ($null -ne $job.TerminatingError) {
                    $errorMessage = $job.TerminatingError.Exception.Message
                }
                elseif (@($job.Errors).Count -gt 0) {
                    $errorMessage = $job.Errors[0].Exception.Message
                }
                else {
                    $errorMessage = "The background check finished with state '$($job.State)'."
                }
            }
            try {
                Remove-EwJob -Id $job.Id -Confirm:$false -ErrorAction Stop
            }
            catch {
                Write-EwWorkbenchLog -State $State -Level Warning -PreserveStatus `
                    -Message "Could not remove completed background check $($job.Id): $($_.Exception.Message)"
            }
        }

        if ([int]$request.Generation -eq [int]$slot.Generation) {
            $output = @(if ($null -ne $job) { $job.Output })
            try {
                Invoke-EwWorkbenchInfoJobResult -State $State -Kind $kind -Request $request `
                    -Output $output -ErrorMessage $errorMessage
            }
            catch {
                $message = "Could not display the background check: $($_.Exception.Message)"
                Invoke-EwWorkbenchInfoJobResult -State $State -Kind $kind -Request $request -ErrorMessage $message
            }
        }
        if ($null -ne $slot.Pending) {
            Invoke-EwWorkbenchInfoJob -State $State -Kind $kind
        }
    }
}
