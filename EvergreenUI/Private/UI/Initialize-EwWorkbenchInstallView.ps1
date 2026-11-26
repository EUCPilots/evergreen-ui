Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchInstallView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $State.InstallDefinitions = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $State.InstallDefinitionsListView.ItemsSource = $State.InstallDefinitions
    $State.InstallDefinitionsStale = $true
    $State.InstallDefinitionsRevision = 0
    $State.InstallRefreshRevision = -1
    $State.InstallRefreshPending = $false
    $State.InstallSelectedDefinitionPaths = @()
    $State.InstallBatchActive = $false
    $State.InstallPromptActive = $false
    $State.InstallReviewQueue = [System.Collections.ArrayList]::new()
    $State.InstallApprovedItems = @()
    $State.InstallActiveItems = @()
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.InstallDefinitions)
    $view.Filter = [System.Predicate[object]]({
        param($item)
        return -not $State.HideIncompatibleInstallToggle.IsChecked -or
            $null -eq $item.PSObject.Properties['ArchitectureAssessment'] -or
            $item.ArchitectureAssessment -ne 'Blocked'
    }.GetNewClosure())
    $refreshInstallView = { $view.Refresh() }.GetNewClosure()
    $State.HideIncompatibleInstallToggle.Add_Checked($refreshInstallView)
    $State.HideIncompatibleInstallToggle.Add_Unchecked($refreshInstallView)
    $State.InstallSelectedPackagesButton.IsEnabled = $false
    $State.ResolveInstallVersionsButton.IsEnabled = $false
    $State.InstallDefinitionsListView.Add_SelectionChanged({
        $validSelection = @($State.InstallDefinitionsListView.SelectedItems |
            Where-Object DefinitionValid -eq 'Yes')
        $State.InstallSelectedPackagesButton.IsEnabled = $validSelection.Count -gt 0 -and
            $null -eq $State.ActiveJobId -and -not $State.InstallDefinitionsStale
    }.GetNewClosure())

    $State.LoadInstallDefinitions = {
        $path = [string]$State.IntuneDefinitionsPathBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = 'Set the Intune definitions folder on the Definitions tab before loading install definitions.'
                Level = 'Warning'
            }
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'InstallDefinitions'
                Name = 'Check local package definitions'
                ScriptBlock = {
                    param($DefinitionPath)
                    $module = Get-Module -Name EvergreenUI | Select-Object -First 1
                    foreach ($definition in Get-EwDefinition -Path $DefinitionPath) {
                        $detection = if ($definition.Status -eq 'Valid') {
                            Test-EwDetection -DefinitionPath $definition.DefinitionPath
                        }
                        else {
                            [PSCustomObject]@{
                                Succeeded = $false
                                Installed = $false
                                DetectedVersion = ''
                                Status = $definition.Status
                                Error = $definition.Error
                            }
                        }
                        $architecture = if ($definition.Status -eq 'Valid') {
                            & $module {
                                param($DefinitionObject)
                                Get-EwInstallArchitectureCompatibility -DefinitionObject $DefinitionObject
                            } $definition.DefinitionObject
                        }
                        else { $null }
                        [PSCustomObject]@{
                            Name = $definition.Name
                            Publisher = $definition.Publisher
                            RequirementArchitecture = if ($null -eq $architecture) { 'Unavailable' }
                                elseif ([string]::IsNullOrWhiteSpace($architecture.RequirementArchitecture)) { 'Missing' }
                                else { $architecture.RequirementArchitecture }
                            ArtifactArchitecture = 'Not checked'
                            ArchitectureAssessment = if ($null -ne $architecture) { $architecture.Status } else { 'Unavailable' }
                            ArchitectureStatus = if ($null -eq $architecture) { 'Unavailable' }
                                elseif ($architecture.Status -eq 'Blocked') { 'Blocked' }
                                elseif ($architecture.Status -eq 'NeedsApproval') { 'Approval may be required' }
                                else { 'Artifact not checked' }
                            ArchitectureError = if ($null -eq $architecture) { '' }
                                elseif ($architecture.Status -eq 'Blocked') { $architecture.Error }
                                else { $architecture.Warnings -join ' ' }
                            Version = $definition.Version
                            DefinitionPath = $definition.DefinitionPath
                            DefinitionValid = $definition.DefinitionValid
                            IsInstalled = [bool]$detection.Installed
                            InstalledVersion = [string]$detection.DetectedVersion
                            LatestVersion = ''
                            InstallStatus = if ($definition.Status -ne 'Valid') { "Invalid definition: $($definition.Status)" }
                                elseif ($architecture.Status -eq 'Blocked') { 'Architecture blocked' }
                                else { [string]$detection.Status }
                            InstallAction = if ($definition.Status -ne 'Valid' -or
                                $architecture.Status -eq 'Blocked') { 'Unavailable' } else { 'Find latest' }
                            Error = if ($null -ne $architecture -and $architecture.Status -eq 'Blocked') { $architecture.Error }
                                else { [string]$detection.Error }
                        }
                    }
                }
                ArgumentList = @($path)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not load local install definitions: $($_.Exception.Message) Reload definitions to retry."
                Level = 'Error'
            }
        }
    }.GetNewClosure()

    $State.ReloadInstallDefinitionsButton.Add_Click({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallStale' -Parameters @{ State = $State }
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallRefresh' -Parameters @{ State = $State; Force = $true }
    }.GetNewClosure())
    $State.PackagesTabControl.Add_SelectionChanged({
        if ($args[1].Source -ne $State.PackagesTabControl) {
            return
        }
        if ($State.InstallTab.IsSelected) {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallStale' -Parameters @{ State = $State }
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallRefresh' -Parameters @{ State = $State }
        }
    }.GetNewClosure())

    $State.ResolveInstallVersionsButton.Add_Click({
        if ($State.InstallDefinitionsStale -or $null -ne $State.ActiveJobId) {
            return
        }
        $definitions = @($State.InstallDefinitions | Where-Object DefinitionValid -eq 'Yes')
        if ($definitions.Count -eq 0) {
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'InstallVersions'
                Name = 'Find latest package versions'
                ScriptBlock = {
                    param([object[]]$Definitions)
                    $module = Get-Module -Name EvergreenUI | Select-Object -First 1
                    foreach ($definition in $Definitions) {
                        $architecture = $null
                        try {
                            $definitionHash = & $module {
                                param($Path)
                                Get-EwDefinitionFileHash -DefinitionPath $Path -ErrorAction Stop
                            } $definition.DefinitionPath
                            $result = Resolve-EwArtifact -DefinitionPath $definition.DefinitionPath -ErrorAction Stop
                            if ($result.Succeeded) {
                                $definitionObject = Get-Content -LiteralPath $definition.DefinitionPath -Raw -ErrorAction Stop |
                                    ConvertFrom-Json -ErrorAction Stop
                                $currentHash = & $module {
                                    param($Path)
                                    Get-EwDefinitionFileHash -DefinitionPath $Path -ErrorAction Stop
                                } $definition.DefinitionPath
                                if ($currentHash -ne $definitionHash) {
                                    throw 'Definition changed during latest-version lookup. Reload and retry.'
                                }
                                $architecture = & $module {
                                    param($DefinitionObject, $Artifact)
                                    Get-EwInstallArchitectureCompatibility -DefinitionObject $DefinitionObject -Artifact $Artifact
                                } $definitionObject $result.ResolvedArtifact
                            }
                        }
                        catch {
                            $result = [PSCustomObject]@{
                                Succeeded = $false
                                Version = ''
                                Error = "Could not find and assess the latest Artifact: $($_.Exception.Message)"
                            }
                        }
                        $installedVersion = [version]::new(0, 0)
                        $isCurrent = $false
                        $latestVersion = [version]::new(0, 0)
                        $versionsComparable = [version]::TryParse(
                            ([string]$definition.InstalledVersion -replace '^[^0-9]*', ''),
                            [ref]$installedVersion
                        ) -and [version]::TryParse(
                            ([string]$result.Version -replace '^[^0-9]*', ''),
                            [ref]$latestVersion
                        )
                        if ($result.Succeeded -and $definition.IsInstalled -and $versionsComparable) {
                            $isCurrent = $installedVersion -ge $latestVersion
                        }
                        [PSCustomObject]@{
                            DefinitionPath = $definition.DefinitionPath
                            Succeeded = [bool]$result.Succeeded
                            LatestVersion = [string]$result.Version
                            IsCurrent = $isCurrent
                            IsInstalled = [bool]$definition.IsInstalled
                            VersionsComparable = $versionsComparable
                            Compatibility = $architecture
                            Error = [string]$result.Error
                        }
                    }
                }
                ArgumentList = ,([object[]]@($definitions | ForEach-Object {
                    [PSCustomObject]@{
                        DefinitionPath = [string]$_.DefinitionPath
                        InstalledVersion = [string]$_.InstalledVersion
                        IsInstalled = [bool]$_.IsInstalled
                    }
                }))
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not find latest package versions: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.InstallSelectedPackagesButton.Add_Click({
        if ($State.InstallDefinitionsStale -or $null -ne $State.ActiveJobId) {
            return
        }
        $definitions = @($State.InstallDefinitionsListView.SelectedItems |
            Where-Object DefinitionValid -eq 'Yes')
        if ($definitions.Count -eq 0) {
            return
        }
        $confirmed = & $State.ModuleInvoker -Name 'Confirm-EwWorkbenchInstallBatch' -Parameters @{
            Window = $State.Window
            Definition = [psobject[]]$definitions
        }
        if (-not $confirmed) {
            return
        }
        $State.InstallReviewQueue.Clear()
        foreach ($definition in $definitions) {
            $null = $State.InstallReviewQueue.Add([PSCustomObject]@{
                Name = [string]$definition.Name
                DefinitionPath = [string]$definition.DefinitionPath
                Reconfirmations = 0
            })
        }
        $State.InstallApprovedItems = @()
        $State.InstallBatchCounts = @{ Installed = 0; Failed = 0; Blocked = 0; Skipped = 0; Unknown = 0 }
        $State.InstallBatchWorkingPath = [string]$State.Settings.OutputPath
        $State.InstallBatchActive = $true
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallAction' -Parameters @{
                State = $State
                Action = 'Review'
            }
        }
        catch {
            $State.InstallBatchActive = $false
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not start the installation review: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
}
