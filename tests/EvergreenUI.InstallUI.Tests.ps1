#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'appdata'
    $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force

    $newRow = {
        param([string]$Name, [string]$Assessment = 'Allowed')
        [PSCustomObject]@{
            Name = $Name
            DefinitionPath = "C:\Definitions\$Name\App.json"
            DefinitionValid = 'Yes'
            RequirementArchitecture = 'All'
            ArtifactArchitecture = 'Not checked'
            ArchitectureAssessment = $Assessment
            ArchitectureStatus = $Assessment
            ArchitectureError = ''
            IsInstalled = $false
            InstalledVersion = ''
            LatestVersion = ''
            InstallStatus = 'Not installed'
            InstallAction = 'Install'
            Error = ''
        }
    }
    $newItem = {
        param($Row, [int]$Reconfirmations = 0)
        [PSCustomObject]@{
            Name = $Row.Name
            DefinitionPath = $Row.DefinitionPath
            Reconfirmations = $Reconfirmations
        }
    }
    $newReview = {
        param([string]$Status, [bool]$Missing = $false, [bool]$X64 = $false)
        $warnings = @(
            if ($Missing) { 'The Definition has no architecture requirement.' }
            if ($X64) { 'Windows 10 on Arm does not support x64 emulation.' }
        )
        $errorMessage = if ($Status -eq 'Blocked') { 'The architecture is incompatible.' } else { '' }
        [PSCustomObject]@{
            Status = $Status
            Compatibility = [PSCustomObject]@{
                Status = $Status
                OperatingSystemArchitecture = 'arm64'
                RequirementArchitecture = if ($Missing) { '' } else { 'All' }
                ArtifactArchitecture = if ($X64) { 'x64' } else { 'x86' }
                RequiresMissingRequirementApproval = $Missing
                RequiresX64OnArm64Approval = $X64
                MissingRequirementWarning = if ($Missing) { $warnings[0] } else { '' }
                X64OnArm64Warning = if ($X64) { $warnings[-1] } else { '' }
                Warnings = [string[]]$warnings
                Error = $errorMessage
            }
            Latest = if ($Status -eq 'Blocked') { $null } else {
                [PSCustomObject]@{ Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe' }
            }
            Fingerprint = 'A' * 64
            Error = $errorMessage
        }
    }
}

Describe 'Install architecture review in the Workbench' {
    It 'hides only blocked rows and does not persist the toggle' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.InstallDefinitions.Add((& $NewRow -Name 'Allowed'))
                $state.InstallDefinitions.Add((& $NewRow -Name 'Blocked' -Assessment 'Blocked'))
                $state.InstallDefinitions.Add((& $NewRow -Name 'Review' -Assessment 'NeedsApproval'))
                Mock Set-EwSetting {}

                $state.HideIncompatibleInstallToggle.IsChecked | Should -BeFalse
                @($state.InstallDefinitionsListView.Items).Count | Should -Be 3
                $state.HideIncompatibleInstallToggle.IsChecked = $true
                @($state.InstallDefinitionsListView.Items | ForEach-Object Name) | Should -Be @('Allowed', 'Review')
                $state.HideIncompatibleInstallToggle.IsChecked = $false
                @($state.InstallDefinitionsListView.Items).Count | Should -Be 3
                Should -Invoke Set-EwSetting -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'assesses definitions without resolving Artifacts while loading the list' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneDefinitionsPathBox.Text = 'C:\Definitions'
                Mock Invoke-EwWorkbenchJob { $script:installLoadWorker = $ScriptBlock }
                Mock Get-EwDefinition {
                    [PSCustomObject]@{
                        Name = 'Example'; Publisher = 'Example'; Version = '1.0'
                        Status = 'Valid'; DefinitionValid = 'Yes'; DefinitionPath = 'C:\Definitions\Example\App.json'
                        DefinitionObject = [PSCustomObject]@{ RequirementRule = [PSCustomObject]@{ Architecture = 'x86' } }
                    }
                    [PSCustomObject]@{
                        Name = 'Missing'; Publisher = 'Example'; Version = '1.0'
                        Status = 'Valid'; DefinitionValid = 'Yes'; DefinitionPath = 'C:\Definitions\Missing\App.json'
                        DefinitionObject = [PSCustomObject]@{
                            Application = [PSCustomObject]@{ Architecture = 'x64' }
                        }
                    }
                }
                Mock Test-EwDetection {
                    [PSCustomObject]@{ Installed = $false; DetectedVersion = ''; Status = 'Not installed'; Error = '' }
                }
                Mock Resolve-EwArtifact {}
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.ReloadInstallDefinitionsButton.RaiseEvent($eventArgs)
                $worker = [scriptblock]::Create($script:installLoadWorker.ToString())
                $rows = @(& $worker 'C:\Definitions')
                $rows[0].RequirementArchitecture | Should -Be 'x86'
                $rows[0].ArtifactArchitecture | Should -Be 'Not checked'
                $rows[1].RequirementArchitecture | Should -Be 'Missing'
                Should -Invoke Resolve-EwArtifact -Exactly 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'updates and filters an incompatible Artifact after latest-version lookup' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; NewReview = $newReview } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = & $NewRow -Name 'Example'
                $state.InstallDefinitions.Add($row)
                $state.HideIncompatibleInstallToggle.IsChecked = $true
                $compatibility = (& $NewReview -Status 'Blocked').Compatibility
                $compatibility.RequirementArchitecture = 'All'
                $compatibility.ArtifactArchitecture = 'arm64'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'InstallVersions'
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; TerminatingError = $null
                        Progress = @(); Information = @(); Errors = @()
                        Output = @([PSCustomObject]@{
                            DefinitionPath = $row.DefinitionPath; Succeeded = $true; LatestVersion = '2.0'
                            IsCurrent = $false; VersionsComparable = $true; Compatibility = $compatibility; Error = ''
                        })
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $row.RequirementArchitecture | Should -Be 'All'
                $row.ArtifactArchitecture | Should -Be 'arm64'
                $row.InstallStatus | Should -Be 'Architecture blocked'
                @($state.InstallDefinitionsListView.Items).Count | Should -Be 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'rejects a latest-version assessment if the Definition changes during resolution' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Changing\App.json'
        $null = New-Item -Path (Split-Path -Path $definitionPath -Parent) -ItemType Directory -Force
        [PSCustomObject]@{
            RequirementRule = [PSCustomObject]@{ Architecture = 'All' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $definitionPath
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; DefinitionPath = $definitionPath } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = & $NewRow -Name 'Changing'
                $row.DefinitionPath = $DefinitionPath
                $state.InstallDefinitions.Add($row)
                $state.ResolveInstallVersionsButton.IsEnabled = $true
                Mock Invoke-EwWorkbenchJob { $script:installVersionsWorker = $ScriptBlock }
                Mock Resolve-EwArtifact {
                    Add-Content -LiteralPath $DefinitionPath -Value ' '
                    [PSCustomObject]@{
                        Succeeded = $true; Version = '2.0'; Error = ''
                        ResolvedArtifact = [PSCustomObject]@{ Architecture = 'x86' }
                    }
                }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.ResolveInstallVersionsButton.RaiseEvent($eventArgs)
                $worker = [scriptblock]::Create($script:installVersionsWorker.ToString())
                $arguments = [object[]]::new(1)
                $arguments[0] = [object[]]@($row)
                $result = & $worker @arguments
                $result.Succeeded | Should -BeFalse
                $result.Error | Should -Match 'Definition changed'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'handles blocked and declined items while combining warnings for each approved item' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; NewItem = $newItem; NewReview = $newReview } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $rows = @(
                    & $NewRow -Name 'Allowed'
                    & $NewRow -Name 'Blocked'
                    & $NewRow -Name 'Declined'
                    & $NewRow -Name 'Both'
                    & $NewRow -Name 'Unavailable'
                )
                foreach ($row in $rows) { $state.InstallDefinitions.Add($row) }
                $items = @($rows | ForEach-Object { & $NewItem -Row $_ })
                $state.InstallBatchActive = $true
                $state.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
                $state.InstallActiveItems = $items
                $unavailableReview = & $NewReview -Status 'Allowed'
                $unavailableReview.Status = 'Failed'
                $unavailableReview.Latest.Succeeded = $false
                $unavailableReview.Error = 'Artifact resolution failed.'
                $job = [PSCustomObject]@{
                    State = 'Completed'; TerminatingError = $null
                    Output = @(
                        [PSCustomObject]@{ Item = $items[0]; Review = (& $NewReview -Status 'Allowed') }
                        [PSCustomObject]@{ Item = $items[1]; Review = (& $NewReview -Status 'Blocked') }
                        [PSCustomObject]@{ Item = $items[2]; Review = (& $NewReview -Status 'NeedsApproval' -Missing $true) }
                        [PSCustomObject]@{ Item = $items[3]; Review = (& $NewReview -Status 'NeedsApproval' -Missing $true -X64 $true) }
                        [PSCustomObject]@{ Item = $items[4]; Review = $unavailableReview }
                    )
                }
                Mock Confirm-EwWorkbenchInstallArchitecture { $Name -ne 'Declined' }

                Invoke-EwWorkbenchInstallJobResult -State $state -Kind InstallReview -Job $job | Should -Be 'Install'
                @($state.InstallApprovedItems.Name) | Should -Be @('Allowed', 'Both')
                $state.InstallApprovedItems[1].AllowMissingArchitectureRequirement | Should -BeTrue
                $state.InstallApprovedItems[1].AllowX64OnArm64 | Should -BeTrue
                $rows[1].InstallStatus | Should -Be 'Architecture blocked'
                $rows[2].InstallStatus | Should -Be 'Skipped'
                $rows[4].ArtifactArchitecture | Should -Be 'Not checked'
                $rows[4].ArchitectureStatus | Should -Be 'Artifact not checked'
                Should -Invoke Confirm-EwWorkbenchInstallArchitecture -Exactly 1 -ParameterFilter {
                    $Name -eq 'Both' -and @($Review.Compatibility.Warnings).Count -eq 2
                }
                Should -Invoke Confirm-EwWorkbenchInstallArchitecture -Exactly 2

                $state.InstallActiveItems = $state.InstallApprovedItems
                $state.InstallApprovedItems = @()
                $job.Output = @(
                    [PSCustomObject]@{ DefinitionPath = $items[0].DefinitionPath; Status = 'Installed'; ReviewChanged = $false; DownloadedVersion = '2.0'; Error = '' }
                    [PSCustomObject]@{ DefinitionPath = $items[3].DefinitionPath; Status = 'Failed'; ReviewChanged = $false; DownloadedVersion = ''; Error = 'Installer failed.' }
                )
                Invoke-EwWorkbenchInstallJobResult -State $state -Kind InstallPackages -Job $job | Should -BeNullOrEmpty
                $rows[0].InstalledVersion | Should -Be '2.0'
                $rows[3].InstallStatus | Should -Be 'Installation failed'
                $state.InstallBatchCounts.Installed | Should -Be 1
                $state.InstallBatchCounts.Blocked | Should -Be 1
                $state.InstallBatchCounts.Skipped | Should -Be 1
                $state.InstallBatchCounts.Failed | Should -Be 2
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'reconfirms changed inputs at most twice even when the new architecture is allowed' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; NewItem = $newItem; NewReview = $newReview } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = & $NewRow -Name 'Changing'
                $state.InstallDefinitions.Add($row)
                $state.InstallBatchActive = $true
                $state.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
                $state.InstallActiveItems = @((& $NewItem -Row $row))
                Mock Confirm-EwWorkbenchInstallArchitecture { $true }

                foreach ($attempt in 0..2) {
                    $item = $state.InstallActiveItems[0]
                    $job = [PSCustomObject]@{
                        State = 'Completed'; TerminatingError = $null
                        Output = @([PSCustomObject]@{
                            DefinitionPath = $item.DefinitionPath; Status = 'Skipped'; ReviewChanged = $true
                            DownloadedVersion = ''; Error = 'Artifact metadata changed.'
                        })
                    }
                    $action = Invoke-EwWorkbenchInstallJobResult -State $state -Kind InstallPackages -Job $job
                    if ($attempt -eq 2) {
                        $action | Should -BeNullOrEmpty
                        $state.InstallReviewQueue.Count | Should -Be 0
                        break
                    }
                    $action | Should -Be 'Review'
                    $state.InstallActiveItems = $state.InstallReviewQueue.ToArray()
                    $state.InstallReviewQueue.Clear()
                    $reviewJob = [PSCustomObject]@{
                        State = 'Completed'; TerminatingError = $null
                        Output = @([PSCustomObject]@{ Item = $state.InstallActiveItems[0]; Review = (& $NewReview -Status 'Allowed') })
                    }
                    Invoke-EwWorkbenchInstallJobResult -State $state -Kind InstallReview -Job $reviewJob | Should -Be 'Install'
                    $state.InstallActiveItems = $state.InstallApprovedItems
                    $state.InstallApprovedItems = @()
                }
                $row.InstallStatus | Should -Be 'Skipped'
                $row.Error | Should -Match 'two re-confirmation limit'
                Should -Invoke Confirm-EwWorkbenchInstallArchitecture -Exactly 2 -ParameterFilter { $Changed }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'passes the reviewed fingerprint and explicit approvals to the installation worker' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.InstallBatchWorkingPath = 'C:\Output'
                $state.InstallApprovedItems = @([PSCustomObject]@{
                    Name = 'Example'; DefinitionPath = 'C:\Definitions\Example\App.json'; Reconfirmations = 0
                    Fingerprint = 'A' * 64; AllowMissingArchitectureRequirement = $true; AllowX64OnArm64 = $true
                })
                Mock Invoke-EwWorkbenchJob {
                    $script:installWorker = $ScriptBlock
                    $script:installWorkerArguments = $ArgumentList
                }
                Mock Install-EwPackage {
                    [PSCustomObject]@{
                        Status = 'Skipped'; Succeeded = $false; DownloadedVersion = ''
                        ReviewChanged = $true; Error = 'Artifact metadata changed.'
                    }
                }
                Invoke-EwWorkbenchInstallAction -State $state -Action Install
                $result = & $script:installWorker @script:installWorkerArguments
                $result.ReviewChanged | Should -BeTrue
                Should -Invoke Install-EwPackage -Exactly 1 -ParameterFilter {
                    $NoCache -and $RequireArchitectureOptIn -and $AllowMissingArchitectureRequirement -and
                    $AllowX64OnArm64 -and $ExpectedReviewFingerprint -eq ('A' * 64)
                }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'confirms on the UI thread and starts the next step only after clearing the completed job' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; NewItem = $newItem; NewReview = $newReview } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = & $NewRow -Name 'Review'
                $item = & $NewItem -Row $row
                $state.InstallDefinitions.Add($row)
                $state.InstallBatchActive = $true
                $state.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
                $state.InstallActiveItems = @($item)
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'InstallReview'
                $script:installMonitorState = $state
                $script:installMonitorJob = [PSCustomObject]@{
                    Id = $state.ActiveJobId; State = 'Completed'; TerminatingError = $null
                    Progress = @(); Information = @(); Errors = @()
                    Output = @([PSCustomObject]@{ Item = $item; Review = (& $NewReview -Status 'NeedsApproval' -Missing $true) })
                }
                $uiThread = [Threading.Thread]::CurrentThread.ManagedThreadId
                Mock Get-EwJob { $script:installMonitorJob }
                Mock Remove-EwJob {}
                Mock Confirm-EwWorkbenchInstallArchitecture {
                    $script:installConfirmationThread = [Threading.Thread]::CurrentThread.ManagedThreadId
                    Invoke-EwWorkbenchJobMonitor -State $script:installMonitorState
                    $true
                }
                Mock Invoke-EwWorkbenchInstallAction {
                    $script:activeIdAtNextInstallStep = $State.ActiveJobId
                }

                Invoke-EwWorkbenchJobMonitor -State $state
                $script:installConfirmationThread | Should -Be $uiThread
                $script:activeIdAtNextInstallStep | Should -BeNullOrEmpty
                Should -Invoke Get-EwJob -Exactly 1
                Should -Invoke Confirm-EwWorkbenchInstallArchitecture -Exactly 1
                Should -Invoke Invoke-EwWorkbenchInstallAction -Exactly 1 -ParameterFilter { $Action -eq 'Install' }
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'preserves completed outcomes and marks interrupted installations as unknown' {
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; NewItem = $newItem } {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $done = & $NewRow -Name 'Completed'
                $unknown = & $NewRow -Name 'Interrupted'
                $state.InstallDefinitions.Add($done)
                $state.InstallDefinitions.Add($unknown)
                $state.InstallBatchActive = $true
                $state.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
                $state.InstallActiveItems = @((& $NewItem -Row $done), (& $NewItem -Row $unknown))
                $job = [PSCustomObject]@{
                    State = 'Failed'; TerminatingError = $null
                    Output = @([PSCustomObject]@{
                        DefinitionPath = $done.DefinitionPath; Status = 'Installed'; ReviewChanged = $false
                        DownloadedVersion = '2.0'; Error = ''
                    })
                }
                Invoke-EwWorkbenchInstallJobResult -State $state -Kind InstallPackages -Job $job | Should -BeNullOrEmpty
                $done.InstallStatus | Should -Be 'Installed'
                $unknown.InstallStatus | Should -Be 'Installation outcome unknown'
                $unknown.Error | Should -Match 'Check the device'
                $state.InstallBatchActive | Should -BeFalse
                $state.InstallReviewQueue.Count | Should -Be 0
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'blocks a changed incompatible Definition through a real review job' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Blocked\App.json'
        $null = New-Item -Path (Split-Path -Path $definitionPath -Parent) -ItemType Directory -Force
        [PSCustomObject]@{
            Information = [PSCustomObject]@{ DisplayName = 'Blocked' }
            RequirementRule = [PSCustomObject]@{ Architecture = 'invalid' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $definitionPath
        InModuleScope EvergreenUI -Parameters @{ NewRow = $newRow; DefinitionPath = $definitionPath } {
            $window = Get-EwWorkbenchWindow
            $state = $null
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $row = & $NewRow -Name 'Blocked'
                $row.DefinitionPath = $DefinitionPath
                $state.InstallDefinitions.Add($row)
                $state.InstallDefinitionsListView.SelectedItem = $row
                Mock Confirm-EwWorkbenchInstallBatch { $true }
                $eventArgs = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.InstallSelectedPackagesButton.RaiseEvent($eventArgs)
                $state.ActiveJobKind | Should -Be 'InstallReview'
                $deadline = [DateTime]::UtcNow.AddSeconds(30)
                do {
                    Start-Sleep -Milliseconds 50
                    Invoke-EwWorkbenchJobMonitor -State $state
                } while ($null -ne $state.ActiveJobId -and [DateTime]::UtcNow -lt $deadline)
                $state.ActiveJobId | Should -BeNullOrEmpty
                $row.InstallStatus | Should -Be 'Architecture blocked'
                $row.Error | Should -Match 'invalid'
                $state.InstallBatchCounts.Blocked | Should -Be 1
            }
            finally {
                if ($null -ne $state -and $null -ne $state.ActiveJobId) {
                    Stop-EwJob -Id $state.ActiveJobId -ErrorAction SilentlyContinue
                    Remove-EwJob -Id $state.ActiveJobId -Confirm:$false -ErrorAction SilentlyContinue
                }
                $window.Close()
            }
        }
    }
}

AfterAll {
    $env:APPDATA = $script:originalAppData
}
