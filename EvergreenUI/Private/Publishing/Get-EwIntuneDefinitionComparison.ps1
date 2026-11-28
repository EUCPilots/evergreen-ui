Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntuneDefinitionComparison {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'PowerShell enumerates the result list as individual PSCustomObject rows.')]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$IntuneApp,

        [Parameter()]
        [switch]$NoCache,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$SelectedDefinitionPath
    )

    $definitions = @(Get-EwDefinition -Path $DefinitionPath)
    $selectedDefinitions = $definitions
    if ($PSBoundParameters.ContainsKey('SelectedDefinitionPath')) {
        $selectedPaths = @($SelectedDefinitionPath | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
        $selectedDefinitions = @($definitions | Where-Object { $_.DefinitionPath -in $selectedPaths })
        foreach ($path in $selectedPaths) {
            if (@($selectedDefinitions | Where-Object DefinitionPath -EQ $path).Count -ne 1) {
                throw "Selected definition '$path' is no longer a unique definition in '$DefinitionPath'."
            }
        }
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    $matchedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $appsById = @{}
    $supersedingAppsById = @{}
    foreach ($app in $IntuneApp) {
        $id = [string]$app.IntuneAppId
        if (-not $appsById.ContainsKey($id)) { $appsById[$id] = [System.Collections.Generic.List[object]]::new() }
        $appsById[$id].Add($app)
        foreach ($target in @(Get-EwObjectPropertyValue -Object $app -Name 'SupersededAppIds' -Default @() | Select-Object -Unique)) {
            $targetId = [string]$target
            if (-not $supersedingAppsById.ContainsKey($targetId)) { $supersedingAppsById[$targetId] = [System.Collections.Generic.List[object]]::new() }
            $supersedingAppsById[$targetId].Add($app)
        }
    }
    $display = {
        param([object]$Value, [string]$Fallback = 'Not specified')
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { $Fallback } else { [string]$Value }
    }
    $definitionIndex = 0
    foreach ($definition in $selectedDefinitions) {
        $definitionIndex++
        Write-Progress -Activity 'Resolving definition import versions' -Status "$definitionIndex of $($selectedDefinitions.Count): $($definition.Name)" -PercentComplete ([int](100 * $definitionIndex / $selectedDefinitions.Count))
        $definitionHash = (Get-FileHash -LiteralPath $definition.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $installPath = Join-Path -Path (Split-Path -Path $definition.DefinitionPath -Parent) -ChildPath 'Source\Install.json'
        $installHash = if (Test-Path -LiteralPath $installPath -PathType Leaf) {
            (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
        } else { '' }
        $guid = ([string]$definition.PSPackageFactoryGuid).Trim()
        $duplicates = @($definitions | Where-Object { $_.Status -eq 'Valid' -and $_.PSPackageFactoryGuid -ieq $guid })
        $matchingApps = @(if ($definition.Status -eq 'Valid') {
                $IntuneApp | Where-Object { $_.NotesValid -eq 'Yes' -and $_.NotesGuid -ieq $guid }
            })
        $chain = Get-EwIntuneSupersedenceState -App $matchingApps
        $apps = @(foreach ($app in $matchingApps) {
                $null = $matchedIds.Add([string]$app.IntuneAppId)
                $targetIds = @(Get-EwObjectPropertyValue -Object $app -Name 'SupersededAppIds' -Default @())
                $predecessors = @(foreach ($targetId in @($targetIds | Select-Object -Unique)) {
                    if ($appsById.ContainsKey([string]$targetId)) { $appsById[[string]$targetId] }
                })
                $supersedes = @($predecessors | Sort-Object DisplayName, DisplayVersion | ForEach-Object { "$(& $display $_.DisplayName 'Name unavailable') (version $(& $display $_.DisplayVersion 'Version unavailable'))" })
                $successors = @(if ($supersedingAppsById.ContainsKey([string]$app.IntuneAppId)) { $supersedingAppsById[[string]$app.IntuneAppId] })
                $supersededBy = @($successors | Sort-Object DisplayName, DisplayVersion | ForEach-Object { "$(& $display $_.DisplayName 'Name unavailable') (version $(& $display $_.DisplayVersion 'Version unavailable'))" })
                [PSCustomObject]@{
                    IntuneAppId = [string]$app.IntuneAppId
                    DisplayName = & $display $app.DisplayName 'Name unavailable'
                    DisplayVersion = & $display $app.DisplayVersion 'Version unavailable'
                    AllowedArchitectures = & $display (Get-EwObjectPropertyValue -Object $app -Name 'AllowedArchitectures') 'Unavailable'
                    Role = if ($chain.CurrentAppId -eq $app.IntuneAppId) { 'Current app' }
                        elseif ($app.IntuneAppId -in $chain.SupersededAppIds) { 'Superseded app' } else { 'Needs review' }
                    AppKind = if ($app.IsUpdateApp) { 'Update app' } else { 'Deployment app' }
                    Supersedes = if ($supersedes.Count) { $supersedes -join '; ' } else { 'No verified predecessor' }
                    SupersededBy = if ($supersededBy.Count) { $supersededBy -join '; ' } else { 'No verified successor' }
                    SupersededAppIds = $targetIds
                    SelectionLabel = "$(& $display $app.DisplayName 'Name unavailable') / $(& $display $app.DisplayVersion 'Version unavailable') / $($app.IntuneAppId)"
                }
            })
        $apps = @($apps | Sort-Object -Property @{ Expression = { if ($_.Role -eq 'Current app') { 0 } else { 1 } } }, DisplayName, DisplayVersion)
        $comparisonError = ''
        $resolved = $null
        $object = $definition.DefinitionObject
        if ($definition.Status -ne 'Valid') {
            $comparisonError = "$($definition.Status). $($definition.Error)".Trim()
        }
        elseif ($duplicates.Count -gt 1) {
            $comparisonError = 'Multiple local definitions share this GUID. Correct the definitions before importing.'
        }
        else {
            try {
                $currentObject = Get-Content -LiteralPath $definition.DefinitionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ((ConvertTo-Json -InputObject $currentObject -Depth 100 -Compress) -cne (ConvertTo-Json -InputObject $object -Depth 100 -Compress)) {
                    $comparisonError = 'The definition changed while comparing. Refresh the comparison before importing.'
                }
                else {
                    $resolved = Resolve-EwArtifact -DefinitionPath $definition.DefinitionPath -NoCache:$NoCache
                    if (-not $resolved.Succeeded) { $comparisonError = "Artifact resolution failed: $($resolved.Error)" }
                }
            }
            catch {
                $comparisonError = "Artifact resolution failed: $($_.Exception.Message)"
            }
        }
        $application = Get-EwObjectPropertyValue -Object $object -Name 'Application'
        $requirement = Get-EwObjectPropertyValue -Object $object -Name 'RequirementRule'
        $requiredArchitecture = [string](Get-EwObjectPropertyValue -Object $requirement -Name 'Architecture')
        $architecture = ConvertFrom-EwArchitectureRequirement -Architecture $requiredArchitecture
        if (-not $comparisonError -and $architecture.Kind -in @('Missing', 'Invalid')) {
            $comparisonError = if ($architecture.Kind -eq 'Missing') { 'Specify RequirementRule.Architecture before importing.' } else { $architecture.Error }
        }
        $assignments = @(Get-EwObjectPropertyValue -Object $object -Name 'Assignments' -Default @())
        $assignmentText = @(foreach ($assignment in $assignments) {
                $type = [string](Get-EwObjectPropertyValue -Object $assignment -Name 'Type')
                $intent = [string](Get-EwObjectPropertyValue -Object $assignment -Name 'Intent')
                $target = switch ($type) {
                    'AllDevices' { 'All Devices' }
                    'AllUsers' { 'All Users' }
                    'Group' { "Group $([string](Get-EwObjectPropertyValue -Object $assignment -Name 'GroupID'))" }
                    default { "Unsupported target '$type'" }
                }
                $groupName = [string](Get-EwObjectPropertyValue -Object $assignment -Name 'GroupName')
                if ($type -eq 'Group' -and $groupName) { $target = "$groupName ($target)" }
                "$intent for $target"
            })
        $updateRequirement = if ($null -ne $object) { Get-EwIntuneUpdateRequirement -Definition $object }
            else { [PSCustomObject]@{ Succeeded = $false; Rules = @(); Error = 'The definition is invalid.' } }
        $currentDefinitionHash = (Get-FileHash -LiteralPath $definition.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $currentInstallHash = if (Test-Path -LiteralPath $installPath -PathType Leaf) {
            (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
        } else { '' }
        if ($currentDefinitionHash -cne $definitionHash -or $currentInstallHash -cne $installHash) {
            $comparisonError = 'The definition or install configuration changed while comparing. Refresh the comparison before importing.'
        }
        $artifact = Get-EwObjectPropertyValue -Object $resolved -Name 'ResolvedArtifact'
        $row = [PSCustomObject]@{
            RowType = 'Definition'
            DefinitionName = & $display $definition.Name 'Name unavailable'
            DefinitionVersion = & $display $definition.Version 'Not specified'
            DefinitionPath = [string]$definition.DefinitionPath
            PSPackageFactoryGuid = $guid
            Publisher = & $display $definition.Publisher
            Architecture = & $display (Get-EwObjectPropertyValue -Object $artifact -Name 'Architecture' -Default (Get-EwObjectPropertyValue -Object $application -Name 'Architecture'))
            RequirementArchitecture = & $display $requiredArchitecture
            AvailableVersion = & $display (Get-EwObjectPropertyValue -Object $resolved -Name 'Version') 'Unavailable'
            AvailableURI = [string](Get-EwObjectPropertyValue -Object $resolved -Name 'URI')
            AssignmentSummary = if ($assignmentText.Count) { $assignmentText -join '; ' } else { 'No assignments. The app will be imported without deployment assignments.' }
            UpdateRequirement = $updateRequirement
            MatchingApps = $apps
            MatchingAppCount = $apps.Count
            RelationshipsVerified = [bool]$chain.Verified
            MatchSnapshot = ConvertTo-Json -InputObject @($apps | Sort-Object IntuneAppId) -Depth 8 -Compress
            ComparisonError = $comparisonError
            DefinitionHash = $definitionHash
            InstallHash = $installHash
            IntuneAppId = ''
            IntuneDisplayName = ''
            IntuneVersion = ''
            Readiness = ''
            MatchStatus = ''
            DeploymentBlocker = ''
            UpdateBlocker = ''
            UpdateEligibilityText = ''
            ImportAsUpdate = $false
            IsSelected = $false
        }
        Set-EwIntuneComparisonTarget -Row $row -AppId $chain.CurrentAppId
        if ($comparisonError) { Write-Verbose -Message "EvergreenUI: '$($row.DefinitionName)' requires review: $comparisonError" }
        $rows.Add($row)
    }
    if (-not $PSBoundParameters.ContainsKey('SelectedDefinitionPath')) {
        foreach ($app in $IntuneApp) {
            if ($matchedIds.Contains([string]$app.IntuneAppId)) { continue }
            $rows.Add([PSCustomObject]@{
                    RowType = 'Intune'
                    IntuneAppId = [string]$app.IntuneAppId
                    IntuneDisplayName = & $display $app.DisplayName 'Name unavailable'
                    IntuneVersion = & $display $app.DisplayVersion 'Version unavailable'
                    RequirementArchitecture = & $display (Get-EwObjectPropertyValue -Object $app -Name 'AllowedArchitectures') 'Unavailable'
                    PSPackageFactoryGuid = & $display $app.NotesGuid 'Not specified'
                    MatchStatus = 'No matching local definition'
                })
        }
    }
    Write-Verbose -Message "EvergreenUI: Compared $($selectedDefinitions.Count) definitions and retained $($rows.Count - $selectedDefinitions.Count) Intune-only apps."
    Write-Progress -Activity 'Resolving definition import versions' -Completed
    $rows
}
