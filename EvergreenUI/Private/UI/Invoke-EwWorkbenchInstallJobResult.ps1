Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInstallJobResult {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet('InstallReview', 'InstallPackages')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [psobject]$Job
    )

    $completed = $Job.State -eq 'Completed' -and $null -eq $Job.TerminatingError
    $markResult = {
        param($Item, [string]$Status, [string]$Message, [string]$Version = '')
        $row = $State.InstallDefinitions |
            Where-Object DefinitionPath -eq $Item.DefinitionPath |
            Select-Object -First 1
        if ($null -ne $row) {
            $row.Error = $Message
            switch ($Status) {
                'Installed' {
                    $row.IsInstalled = $true
                    $row.InstalledVersion = $Version
                    $row.InstallStatus = 'Installed'
                    $row.InstallAction = 'Installed'
                }
                'Blocked' {
                    $row.InstallStatus = 'Architecture blocked'
                    $row.InstallAction = 'Unavailable'
                    $row.ArchitectureAssessment = 'Blocked'
                    $row.ArchitectureStatus = 'Blocked'
                    $row.ArchitectureError = $Message
                }
                'Skipped' {
                    $row.InstallStatus = 'Skipped'
                    $row.InstallAction = 'Review'
                }
                'Unknown' {
                    $row.InstallStatus = 'Installation outcome unknown'
                    $row.InstallAction = 'Check device'
                }
                default {
                    $row.InstallStatus = 'Installation failed'
                    $row.InstallAction = 'Retry'
                }
            }
        }
        $State.InstallBatchCounts[$Status] = [int]$State.InstallBatchCounts[$Status] + 1
        $level = if ($Status -in @('Failed', 'Unknown')) { 'Error' }
            elseif ($Status -in @('Blocked', 'Skipped')) { 'Warning' } else { 'Info' }
        $text = switch ($Status) {
            'Installed' { "Installed $($Item.Name) $Version." }
            'Blocked' { "Blocked installation for $($Item.Name): $Message" }
            'Skipped' { "Skipped installation for $($Item.Name): $Message" }
            'Unknown' { "Installation outcome for $($Item.Name) is unknown: $Message" }
            default { "Installation failed for $($Item.Name): $Message" }
        }
        Write-EwWorkbenchLog -State $State -Message $text -Level $level
    }
    $retryReview = {
        param($Item, [string]$Message)
        if ([int]$Item.Reconfirmations -ge 2) {
            & $markResult $Item 'Skipped' "Inputs changed repeatedly; the two re-confirmation limit was reached. $Message"
            return
        }
        $null = $State.InstallReviewQueue.Add([PSCustomObject]@{
            Name = [string]$Item.Name
            DefinitionPath = [string]$Item.DefinitionPath
            Reconfirmations = [int]$Item.Reconfirmations + 1
        })
        $row = $State.InstallDefinitions |
            Where-Object DefinitionPath -eq $Item.DefinitionPath |
            Select-Object -First 1
        if ($null -ne $row) {
            $row.InstallStatus = 'Inputs changed'
            $row.InstallAction = 'Review again'
            $row.Error = $Message
        }
        Write-EwWorkbenchLog -State $State -Message "Reviewed inputs changed for $($Item.Name); resolving them again." -Level Warning
    }

    $approved = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $State.InstallActiveItems) {
        if ($Kind -eq 'InstallReview') {
            if (-not $completed) {
                & $markResult $item 'Failed' 'The architecture review did not complete.'
                continue
            }
            $entry = @($Job.Output | Where-Object { $_.Item.DefinitionPath -eq $item.DefinitionPath } |
                    Select-Object -First 1)
            if ($entry.Count -eq 0) {
                & $markResult $item 'Failed' 'No architecture review was returned.'
                continue
            }
            $review = $entry[0].Review
            if ($null -eq $review) {
                & $markResult $item 'Failed' 'No architecture review was returned.'
                continue
            }
            if ($review.Status -eq 'Changed') {
                & $retryReview $item $review.Error
                continue
            }
            $row = $State.InstallDefinitions |
                Where-Object DefinitionPath -eq $item.DefinitionPath |
                Select-Object -First 1
            if ($null -ne $row -and $null -ne $review.Compatibility) {
                Set-EwWorkbenchInstallArchitecture -Row $row -Compatibility $review.Compatibility `
                    -ArtifactResolved:($null -ne $review.Latest -and $review.Latest.Succeeded)
            }
            if ($review.Status -in @('Blocked', 'Failed')) {
                & $markResult $item $review.Status $review.Error
                continue
            }
            if ($review.Status -notin @('Allowed', 'NeedsApproval') -or
                $null -eq $review.Compatibility -or $null -eq $review.Latest -or
                $review.Fingerprint -notmatch '^[0-9A-Fa-f]{64}$') {
                & $markResult $item 'Failed' 'The installation review was incomplete.'
                continue
            }
            if ($review.Status -eq 'NeedsApproval' -or [int]$item.Reconfirmations -gt 0) {
                $State.InstallPromptActive = $true
                try {
                    $confirmed = Confirm-EwWorkbenchInstallArchitecture -Window $State.Window -Name $item.Name `
                        -Review $review -Changed:([int]$item.Reconfirmations -gt 0)
                }
                catch {
                    & $markResult $item 'Failed' "Could not confirm architecture: $($_.Exception.Message)"
                    continue
                }
                finally {
                    $State.InstallPromptActive = $false
                }
                if (-not $confirmed) {
                    & $markResult $item 'Skipped' 'Architecture approval was declined.'
                    continue
                }
            }
            $approved.Add([PSCustomObject]@{
                Name = [string]$item.Name
                DefinitionPath = [string]$item.DefinitionPath
                Reconfirmations = [int]$item.Reconfirmations
                Fingerprint = [string]$review.Fingerprint
                AllowMissingArchitectureRequirement = [bool]$review.Compatibility.RequiresMissingRequirementApproval
                AllowX64OnArm64 = [bool]$review.Compatibility.RequiresX64OnArm64Approval
                AllowUnknownArchitectureOnArm64 = [bool](Get-EwObjectPropertyValue -Object $review.Compatibility -Name 'RequiresUnknownArchitectureApproval' -Default $false)
            })
        }
        else {
            $entry = @($Job.Output | Where-Object DefinitionPath -eq $item.DefinitionPath |
                    Select-Object -First 1)
            if ($entry.Count -eq 0) {
                & $markResult $item 'Unknown' 'The background job did not return a result. Check the device before retrying.'
                continue
            }
            $result = $entry[0]
            if ($result.ReviewChanged) {
                if ($completed) {
                    & $retryReview $item $result.Error
                }
                else {
                    & $markResult $item 'Skipped' 'Inputs changed and the installation batch stopped.'
                }
                continue
            }
            if ($result.Status -notin @('Installed', 'Failed', 'Blocked', 'Skipped')) {
                & $markResult $item 'Unknown' 'The background job returned an unrecognized result. Check the device before retrying.'
                continue
            }
            & $markResult $item $result.Status $result.Error $result.DownloadedVersion
        }
    }
    $State.InstallActiveItems = @()
    [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.InstallDefinitions).Refresh()

    if (-not $completed) {
        foreach ($item in $State.InstallReviewQueue.ToArray()) {
            & $markResult $item 'Skipped' 'The installation batch stopped before this item could be reviewed.'
        }
        $State.InstallReviewQueue.Clear()
        $State.InstallBatchActive = $false
        $message = if ($State.InstallBatchCounts.Unknown -gt 0) {
            'Installation batch stopped with unknown outcomes. Check the device before retrying; see the activity log for details.'
        }
        else {
            'Installation batch stopped. Check the activity log.'
        }
        Write-EwWorkbenchLog -State $State -Message $message -Level Error
        return ''
    }
    if ($approved.Count -gt 0) {
        $State.InstallApprovedItems = [object[]]$approved.ToArray()
        return 'Install'
    }
    if ($State.InstallReviewQueue.Count -gt 0) {
        return 'Review'
    }
    $State.InstallBatchActive = $false
    $counts = $State.InstallBatchCounts
    Write-EwWorkbenchLog -State $State -Message "Install batch: $($counts.Installed) installed, $($counts.Blocked) blocked, $($counts.Skipped) skipped, $($counts.Failed) failed, $($counts.Unknown) unknown."
    return ''
}
