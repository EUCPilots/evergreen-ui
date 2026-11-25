Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInfoJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Download', 'Library', 'PackageDefinitions', 'M365Configurations', 'NerdioDefinitions', 'About')][string]$Kind,
        [AllowNull()][System.Collections.IDictionary]$Request = $null
    )

    $slot = $State.InfoJobs[$Kind]
    if ($State.InfoClosed) {
        return
    }
    if ($null -ne $Request) {
        if ($Kind -ne 'About' -and $null -ne $slot.ActiveId -and $null -eq $slot.Pending -and
            $null -ne $slot.ActiveRequest -and $slot.ActiveRequest.Path -ceq $Request.Path -and
            $slot.ActiveRequest.ArgumentList[1] -ceq $Request.ArgumentList[1] -and
            $slot.ActiveRequest.OpenAfterCheck -eq $Request.OpenAfterCheck) {
            try {
                $active = Get-EwJob -Id $slot.ActiveId -ErrorAction Stop
                if ($active.State -in @('NotStarted', 'Running')) {
                    Write-Verbose -Message "EvergreenUI: Reusing the active $Kind folder check"
                    return
                }
            }
            catch {
                Write-EwWorkbenchLog -State $State -Level Warning -PreserveStatus `
                    -Message "Could not read the previous folder check: $($_.Exception.Message)"
            }
        }
        $slot.Generation = [int]$slot.Generation + 1
        $Request.Generation = $slot.Generation
        $slot.Pending = $Request
        if ($Kind -ne 'About' -and $null -ne $slot.ActiveId) {
            Invoke-EwWorkbenchInfoJobCleanup -State $State -Kind $Kind
        }
    }
    if ($null -ne $slot.ActiveId -or $null -eq $slot.Pending) {
        return
    }
    if ($Kind -ne 'About') {
        # Reserve pool capacity for About and the active workflow job.
        $activeChecks = @($State.InfoJobs.Keys | Where-Object {
                $_ -ne 'About' -and $null -ne $State.InfoJobs[$_].ActiveId
            }).Count
        if ($activeChecks -ge 2) {
            return
        }
    }

    $current = $slot.Pending
    $slot.Pending = $null
    try {
        $job = Start-EwJob -Name $current.Name -ScriptBlock $current.ScriptBlock `
            -ArgumentList $current.ArgumentList -NoModuleImport -ErrorAction Stop
        if ($null -eq $job) {
            throw 'The background check did not start.'
        }
        $slot.ActiveId = $job.Id
        $slot.ActiveRequest = $current
    }
    catch {
        Invoke-EwWorkbenchInfoJobResult -State $State -Kind $Kind -Request $current `
            -ErrorMessage $_.Exception.Message
    }
}
