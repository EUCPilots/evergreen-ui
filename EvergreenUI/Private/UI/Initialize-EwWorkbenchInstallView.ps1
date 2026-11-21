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
    $State.InstallSelectedPackagesButton.IsEnabled = $false
    $State.ResolveInstallVersionsButton.IsEnabled = $false
    $State.InstallDefinitionsListView.Add_SelectionChanged({
        $validSelection = @($State.InstallDefinitionsListView.SelectedItems |
            Where-Object DefinitionValid -eq 'Yes')
        $State.InstallSelectedPackagesButton.IsEnabled = $validSelection.Count -gt 0 -and $null -eq $State.ActiveJobId
    }.GetNewClosure())

    $State.ReloadInstallDefinitionsButton.Add_Click({
        $path = [string]$State.IntuneDefinitionsPathBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = 'Set the Intune definitions folder in Packages before loading install definitions.'
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
                        $architecture = ''
                        $requirementRuleProperty = if ($null -ne $definition.DefinitionObject) {
                            $definition.DefinitionObject.PSObject.Properties['RequirementRule']
                        }
                        if ($null -ne $requirementRuleProperty -and $null -ne $requirementRuleProperty.Value) {
                            $architecture = [string](Get-EwObjectPropertyValue -Object $requirementRuleProperty.Value -Name Architecture -Default '')
                        }
                        $applicationProperty = if ($null -ne $definition.DefinitionObject) {
                            $definition.DefinitionObject.PSObject.Properties['Application']
                        }
                        if ([string]::IsNullOrWhiteSpace($architecture) -and
                            $null -ne $applicationProperty -and
                            $null -ne $applicationProperty.Value) {
                            $architecture = [string](Get-EwObjectPropertyValue -Object $applicationProperty.Value -Name Architecture -Default '')
                        }
                        [PSCustomObject]@{
                            Name = $definition.Name
                            Publisher = $definition.Publisher
                            Architecture = $architecture
                            Version = $definition.Version
                            DefinitionPath = $definition.DefinitionPath
                            DefinitionValid = $definition.DefinitionValid
                            IsInstalled = [bool]$detection.Installed
                            InstalledVersion = [string]$detection.DetectedVersion
                            LatestVersion = ''
                            InstallStatus = if ($definition.Status -eq 'Valid') { [string]$detection.Status } else { "Invalid definition: $($definition.Status)" }
                            InstallAction = if ($definition.Status -eq 'Valid') { 'Find latest' } else { 'Unavailable' }
                            Error = [string]$detection.Error
                        }
                    }
                }
                ArgumentList = @($path)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not load local install definitions: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.ResolveInstallVersionsButton.Add_Click({
        $definitions = @($State.InstallDefinitions | Where-Object DefinitionValid -eq 'Yes')
        if ($definitions.Count -eq 0) {
            return
        }
        $State.InstallActionStatusLabel.Text = 'Finding latest versions...'
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'InstallVersions'
                Name = 'Find latest package versions'
                ScriptBlock = {
                    param([object[]]$Definitions)
                    foreach ($definition in $Definitions) {
                        $result = Resolve-EwArtifact -DefinitionPath $definition.DefinitionPath
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
            $State.InstallActionStatusLabel.Text = 'Could not start latest-version lookup.'
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not find latest package versions: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.InstallSelectedPackagesButton.Add_Click({
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
        $paths = [string[]]@($definitions | ForEach-Object { [string]$_.DefinitionPath })
        $workingPath = [string]$State.Settings.OutputPath
        $argumentList = [object[]]::new(2)
        $argumentList[0] = $paths
        $argumentList[1] = $workingPath
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'InstallPackages'
                Name = 'Install selected applications'
                ScriptBlock = {
                    param([string[]]$DefinitionPaths, [string]$WorkingPath)
                    foreach ($definitionPath in $DefinitionPaths) {
                        $definition = $null
                        try {
                            $definition = Get-EwDefinition -Path $definitionPath | Select-Object -First 1
                            $result = Install-EwPackage -DefinitionPath $definitionPath -WorkingPath $WorkingPath -Confirm:$false
                            [PSCustomObject]@{
                                Name = if ($null -ne $definition) { [string]$definition.Name } else { [System.IO.Path]::GetFileName((Split-Path -Path $definitionPath -Parent)) }
                                DefinitionPath = $definitionPath
                                Succeeded = [bool]$result.Succeeded
                                DownloadedVersion = [string]$result.DownloadedVersion
                                ExitCode = [int]$result.ExitCode
                                Error = [string]$result.Error
                            }
                        }
                        catch {
                            [PSCustomObject]@{
                                Name = if ($null -ne $definition) { [string]$definition.Name } else { [System.IO.Path]::GetFileName((Split-Path -Path $definitionPath -Parent)) }
                                DefinitionPath = $definitionPath
                                Succeeded = $false
                                DownloadedVersion = ''
                                ExitCode = -1
                                Error = $_.Exception.Message
                            }
                        }
                    }
                }
                ArgumentList = $argumentList
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not start selected installations: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
}
