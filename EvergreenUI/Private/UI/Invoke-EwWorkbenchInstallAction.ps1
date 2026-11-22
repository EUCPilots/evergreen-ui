Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInstallAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [ValidateSet('Review', 'Install')]
        [string]$Action
    )

    if ($null -ne $State.ActiveJobId) {
        throw 'Cannot start the next installation step while another job is active.'
    }

    if ($Action -eq 'Review') {
        $items = [object[]]$State.InstallReviewQueue.ToArray()
        $State.InstallReviewQueue.Clear()
        $State.InstallActiveItems = $items
        $arguments = [object[]]::new(1)
        $arguments[0] = $items
        $State.InstallActionStatusLabel.Text = 'Reviewing installation architecture...'
        Invoke-EwWorkbenchJob -State $State -Kind InstallReview -Name 'Review selected installations' `
            -ArgumentList $arguments -ScriptBlock {
                param([object[]]$Items)
                $module = Get-Module -Name EvergreenUI | Select-Object -First 1
                if ($null -eq $module) {
                    throw 'The EvergreenUI module is unavailable in the installation worker.'
                }
                foreach ($item in $Items) {
                    try {
                        $review = & $module {
                            param($DefinitionPath)
                            Get-EwInstallReview -DefinitionPath $DefinitionPath -NoCache -ErrorAction Stop
                        } $item.DefinitionPath
                        if ($null -eq $review) {
                            throw 'No installation review was returned.'
                        }
                    }
                    catch {
                        $review = [PSCustomObject]@{
                            Status = 'Failed'
                            Compatibility = $null
                            Latest = $null
                            Fingerprint = ''
                            Error = $_.Exception.Message
                        }
                    }
                    [PSCustomObject]@{ Item = $item; Review = $review }
                }
            }
    }
    else {
        $items = [object[]]@($State.InstallApprovedItems)
        $State.InstallApprovedItems = @()
        $State.InstallActiveItems = $items
        $arguments = [object[]]::new(2)
        $arguments[0] = $items
        $arguments[1] = [string]$State.InstallBatchWorkingPath
        $State.InstallActionStatusLabel.Text = 'Installing approved applications...'
        Invoke-EwWorkbenchJob -State $State -Kind InstallPackages -Name 'Install selected applications' `
            -ArgumentList $arguments -ScriptBlock {
                param([object[]]$Items, [string]$WorkingPath)
                foreach ($item in $Items) {
                    try {
                        $parameters = @{
                            DefinitionPath = [string]$item.DefinitionPath
                            WorkingPath = $WorkingPath
                            NoCache = $true
                            AllowMissingArchitectureRequirement = [bool]$item.AllowMissingArchitectureRequirement
                            AllowX64OnArm64 = [bool]$item.AllowX64OnArm64
                            ExpectedReviewFingerprint = [string]$item.Fingerprint
                            RequireArchitectureOptIn = $true
                            Confirm = $false
                            ErrorAction = 'Stop'
                        }
                        $result = Install-EwPackage @parameters
                        if ($null -eq $result) {
                            throw 'No installation result was returned.'
                        }
                        [PSCustomObject]@{
                            Name = [string]$item.Name
                            DefinitionPath = [string]$item.DefinitionPath
                            Reconfirmations = [int]$item.Reconfirmations
                            Status = [string]$result.Status
                            Succeeded = [bool]$result.Succeeded
                            DownloadedVersion = [string]$result.DownloadedVersion
                            ReviewChanged = [bool]$result.ReviewChanged
                            Error = [string]$result.Error
                        }
                    }
                    catch {
                        [PSCustomObject]@{
                            Name = [string]$item.Name
                            DefinitionPath = [string]$item.DefinitionPath
                            Reconfirmations = [int]$item.Reconfirmations
                            Status = 'Failed'
                            Succeeded = $false
                            DownloadedVersion = ''
                            ReviewChanged = $false
                            Error = $_.Exception.Message
                        }
                    }
                }
            }
    }
}
