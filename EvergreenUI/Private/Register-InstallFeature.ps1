function Register-InstallFeature {
    <#
    .SYNOPSIS
    Registers event handlers for the Install package management and execution feature.

    .DESCRIPTION
    Sets up event handlers for the Install (Packages) navigation view, including package
    definition loading, latest version resolution with caching, local installation execution,
    and row status management. Handles App.json definition parsing, version comparison,
    and elevation/architecture compatibility checks.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls for the Install feature.

    .PARAMETER RegisterBackgroundOperation
    Scriptblock to register background async operations with completion handlers.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    Manages Install ListView with row filtering by architecture compatibility and status.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls,
        [scriptblock]$RegisterBackgroundOperation
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract feature-specific controls
    $installLoadDefinitionsButton = $Controls.InstallLoadDefinitionsButton
    $installResolveLatestButton = $Controls.InstallResolveLatestButton
    $installHideIncompatibleArchitectureToggle = $Controls.InstallHideIncompatibleArchitectureToggle
    $installDefinitionsCountLabel = $Controls.InstallDefinitionsCountLabel
    $installActionableCountLabel = $Controls.InstallActionableCountLabel
    $installElevationStatusDot = $Controls.InstallElevationStatusDot
    $installElevationStatusLabel = $Controls.InstallElevationStatusLabel
    $installLoadingPanel = $Controls.InstallLoadingPanel
    $installLoadingLabel = $Controls.InstallLoadingLabel
    $installProgressBar = $Controls.InstallProgressBar
    $installPackagesListView = $Controls.InstallPackagesListView
    $installApplyButton = $Controls.InstallApplyButton
    $installActionStatusLabel = $Controls.InstallActionStatusLabel
    $intuneDefinitionsPathBox = $Controls.IntuneDefinitionsPathBox
    $outputPathBox = $Controls.OutputPathBox

    # Verify required controls exist
    if ($null -eq $installPackagesListView) {
        Write-Verbose 'EvergreenUI: InstallPackagesListView not found; Install feature registration skipped.'
        return
    }

    # Helper scriptblock: Normalize directory path (trim whitespace and quotes)
    $normalizeDirectoryPath = {
        param([string]$PathValue)

        if ([string]::IsNullOrWhiteSpace($PathValue)) {
            return ''
        }

        return $PathValue.Trim().Trim('"')
    }

    # Helper scriptblock: Parse comparable version from text (handles various formats)
    $parseComparableVersion = {
        param(
            [AllowNull()]
            [string]$VersionText
        )

        $raw = if ($null -eq $VersionText) { '' } else { [string]$VersionText }
        $trimmed = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return [PSCustomObject]@{
                Success    = $false
                Raw        = $raw
                Normalized = ''
                Parsed     = $null
                Error      = 'Version is empty.'
            }
        }

        $match = [regex]::Match($trimmed, '\d+(\.\d+){0,3}')
        $normalized = ''
        if ($match.Success) {
            $normalized = $match.Value
        }
        else {
            $normalized = ($trimmed -replace '[^0-9\.]', '').Trim('.')
        }

        if ([string]::IsNullOrWhiteSpace($normalized)) {
            return [PSCustomObject]@{
                Success    = $false
                Raw        = $raw
                Normalized = ''
                Parsed     = $null
                Error      = 'Version has no numeric segments.'
            }
        }

        $segments = @($normalized.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($segments.Count -eq 0) {
            return [PSCustomObject]@{
                Success    = $false
                Raw        = $raw
                Normalized = ''
                Parsed     = $null
                Error      = 'Version has no valid numeric segments.'
            }
        }

        if ($segments.Count -gt 4) {
            $segments = @($segments | Select-Object -First 4)
        }

        $normalized = ($segments -join '.')
        try {
            return [PSCustomObject]@{
                Success    = $true
                Raw        = $raw
                Normalized = $normalized
                Parsed     = [version]$normalized
                Error      = ''
            }
        }
        catch {
            return [PSCustomObject]@{
                Success    = $false
                Raw        = $raw
                Normalized = $normalized
                Parsed     = $null
                Error      = $_.Exception.Message
            }
        }
    }

    # Helper scriptblock: Test if process is running with elevation
    $testInstallElevationState = {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            return $false
        }
    }

    # Helper scriptblock: Update elevation status indicators
    $setInstallElevationState = {
        $isElevated = & $testInstallElevationState
        if ($null -ne $installElevationStatusDot) {
            $installElevationStatusDot.Fill = if ($isElevated) {
                [System.Windows.Media.Brushes]::LightGreen
            }
            else {
                [System.Windows.Media.Brushes]::Gold
            }
        }

        if ($null -ne $installElevationStatusLabel) {
            $installElevationStatusLabel.Text = if ($isElevated) {
                'Workbench is running elevated'
            }
            else {
                'Not elevated - installers may prompt for UAC'
            }
        }
    }

    # Helper scriptblock: Apply sort to Install packages ListView
    $applyInstallListSort = {
        [void](Set-ListViewSort -ListView $installPackagesListView `
            -Property ([string]$SyncHash.InstallSortProperty) `
            -Direction ([string]$SyncHash.InstallSortDirection))
    }

    # Helper scriptblock: Update Install row action button states based on selection
    $updateInstallRowActionButtons = {
        $selectedItems = if ($null -eq $installPackagesListView) { @() } else { @($installPackagesListView.SelectedItems) }

        $hasActionable = @($selectedItems | Where-Object {
                [string]$_.InstallAction -eq 'Install' -or [string]$_.InstallAction -eq 'Update'
            }).Count -gt 0

        if ($null -ne $installApplyButton) {
            $installApplyButton.IsEnabled = (-not $SyncHash.IsInstallLoading) -and $hasActionable
        }

        if ($null -ne $installResolveLatestButton) {
            $installResolveLatestButton.IsEnabled = (-not $SyncHash.IsInstallLoading) -and (@($SyncHash.InstallDefinitionRows).Count -gt 0)
        }
    }

    # Helper scriptblock: Set loading state with UI feedback
    $setInstallLoadingState = {
        param(
            [bool]$IsLoading,
            [string]$Message = ''
        )

        $SyncHash.IsInstallLoading = $IsLoading

        Set-LoadingState -ButtonStates $SyncHash.InstallActionButtonStates -IsLoading $IsLoading `
            -Buttons @($installLoadDefinitionsButton, $installResolveLatestButton, $installApplyButton) `
            -LoadingControls @($installLoadingPanel, $installProgressBar) -LoadingLabel $installLoadingLabel `
            -LoadingMessage $Message -IdleLoadingMessage 'Working...' -StatusLabel $installActionStatusLabel `
            -ClearStatusOnIdle $false

        & $updateInstallRowActionButtons
    }

    # Helper scriptblock: Refresh Install packages ListView with status/action determination
    $refreshInstallRows = {
        $definitionRows = @($SyncHash.InstallDefinitionRows)
        $rows = [System.Collections.Generic.List[object]]::new()
        $actionableCount = 0
        $hideIncompatibleArchitecture = $false
        if ($null -ne $installHideIncompatibleArchitectureToggle) {
            $hideIncompatibleArchitecture = [bool]$installHideIncompatibleArchitectureToggle.IsChecked
        }
        elseif ($null -ne $SyncHash.Config.InstallSettings) {
            $hideIncompatibleArchitecture = [bool]$SyncHash.Config.InstallSettings.HideIncompatibleArchitecture
        }

        $localArch = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'x64' }
            'x86' { 'x86' }
            'ARM64' { 'arm64' }
            default { 'x64' }
        }

        foreach ($definitionRow in $definitionRows) {
            $definitionObject = $definitionRow.DefinitionObject
            $architecture = '-'
            $displayArchitecture = '-'
            $installedVersion = '-'
            $detectionStatus = 'Not evaluated'
            $installStatus = 'Needs latest check'
            $installAction = '-'
            $latestVersion = [string]$definitionRow.LatestVersion

            if ($null -ne $definitionObject) {
                $requirementArchValue = [string]$definitionObject.RequirementRule.Architecture
                if (-not [string]::IsNullOrWhiteSpace($requirementArchValue)) {
                    $architecture = $requirementArchValue
                }
                $appArchValue = [string]$definitionObject.Application.Architecture
                if (-not [string]::IsNullOrWhiteSpace($appArchValue)) {
                    $displayArchitecture = $appArchValue
                }
            }

            $isArchCompatible = if ($architecture -eq '-' -or [string]::IsNullOrWhiteSpace($architecture) -or
                $architecture -eq 'All' -or $architecture -eq 'x86,x64,arm64') {
                $true
            }
            else {
                $archList = @($architecture -split ',' | ForEach-Object { $_.Trim().ToLower() })
                $archList -contains $localArch
            }

            if ([string]$definitionRow.DefinitionValid -ne 'Yes' -or $null -eq $definitionObject) {
                $installStatus = [string]$definitionRow.Status
                $installAction = 'Fix definition'
            }
            elseif (-not $isArchCompatible) {
                $installStatus = "Incompatible architecture ($architecture)"
                $installAction = 'Incompatible'
                if ($hideIncompatibleArchitecture) {
                    continue
                }
            }
            else {
                $detectionResult = Test-LocalPackageDetection -DefinitionObject $definitionObject
                if (-not $detectionResult.Succeeded) {
                    $detectionStatus = 'Detection failed'
                    $installStatus = if ([string]::IsNullOrWhiteSpace([string]$detectionResult.Error)) { 'Detection failed' } else { [string]$detectionResult.Error }
                    $installAction = 'Needs review'
                }
                else {
                    if (-not [string]::IsNullOrWhiteSpace([string]$detectionResult.DetectedVersion)) {
                        $installedVersion = [string]$detectionResult.DetectedVersion
                    }
                    elseif ($detectionResult.Installed) {
                        $installedVersion = 'Installed'
                    }

                    $detectionStatus = [string]$detectionResult.Status

                    $hasDetectedInstallEvidence = -not [string]::IsNullOrWhiteSpace([string]$detectionResult.DetectedVersion)

                    if (-not $detectionResult.Installed) {
                        if ($hasDetectedInstallEvidence) {
                            if ([string]::IsNullOrWhiteSpace($latestVersion)) {
                                $installStatus = 'Installed (latest not checked)'
                                $installAction = '-'
                            }
                            else {
                                $installedComparable = & $parseComparableVersion -VersionText $installedVersion
                                $latestComparable = & $parseComparableVersion -VersionText $latestVersion
                                if ($installedComparable.Success -and $latestComparable.Success -and $installedComparable.Parsed -lt $latestComparable.Parsed) {
                                    $installStatus = 'Installed (update needed)'
                                    $installAction = 'Update'
                                }
                                elseif ($installedComparable.Success -and $latestComparable.Success) {
                                    $installStatus = 'Installed (up to date)'
                                    $installAction = '-'
                                }
                                else {
                                    $installStatus = 'Installed (compare unavailable)'
                                    $installAction = '-'
                                }
                            }
                        }
                        else {
                            $installStatus = 'Not installed'
                            $installAction = 'Install'
                        }
                    }
                    elseif ([string]::IsNullOrWhiteSpace($latestVersion)) {
                        $installStatus = 'Installed (latest not checked)'
                        $installAction = '-'
                    }
                    else {
                        $installedComparable = & $parseComparableVersion -VersionText $installedVersion
                        $latestComparable = & $parseComparableVersion -VersionText $latestVersion
                        if ($installedComparable.Success -and $latestComparable.Success -and $installedComparable.Parsed -lt $latestComparable.Parsed) {
                            $installStatus = 'Installed (update needed)'
                            $installAction = 'Update'
                        }
                        elseif ($installedComparable.Success -and $latestComparable.Success) {
                            $installStatus = 'Installed (up to date)'
                            $installAction = '-'
                        }
                        else {
                            $installStatus = 'Installed (compare unavailable)'
                            $installAction = '-'
                        }
                    }
                }
            }

            if ($installAction -eq 'Install' -or $installAction -eq 'Update') {
                $actionableCount++
            }

            $rows.Add([PSCustomObject]@{
                    Name              = [string]$definitionRow.Name
                    Publisher         = [string]$definitionRow.Publisher
                    Architecture      = $displayArchitecture
                    DefinitionVersion = [string]$definitionRow.Version
                    InstalledVersion  = $installedVersion
                    LatestVersion     = if ([string]::IsNullOrWhiteSpace($latestVersion)) { '-' } else { $latestVersion }
                    DetectionStatus   = $detectionStatus
                    InstallStatus     = $installStatus
                    InstallAction     = $installAction
                    DefinitionPath    = [string]$definitionRow.DefinitionPath
                    DefinitionObject  = $definitionObject
                })
        }

        $sortedRows = @($rows | Sort-Object -Property @{ Expression = {
                    if ([string]$_.InstallAction -eq 'Install') { 0 }
                    elseif ([string]$_.InstallAction -eq 'Update') { 1 }
                    else { 2 }
                }
            }, Publisher, Name)

        $SyncHash.InstallRows = $sortedRows
        if ($null -ne $installPackagesListView) {
            $installPackagesListView.ItemsSource = $sortedRows
            & $applyInstallListSort
        }

        if ($null -ne $installDefinitionsCountLabel) {
            $validCount = @($definitionRows | Where-Object { [string]$_.DefinitionValid -eq 'Yes' }).Count
            $installDefinitionsCountLabel.Text = "$($definitionRows.Count) loaded ($validCount valid)"
        }

        if ($null -ne $installActionableCountLabel) {
            $installActionableCountLabel.Text = "$actionableCount actionable"
        }

        if ($null -ne $installActionStatusLabel -and -not $SyncHash.IsInstallLoading) {
            $upToDate = @($sortedRows | Where-Object { [string]$_.InstallStatus -eq 'Installed (up to date)' }).Count
            $needsInstall = @($sortedRows | Where-Object { [string]$_.InstallAction -eq 'Install' }).Count
            $needsUpdate = @($sortedRows | Where-Object { [string]$_.InstallAction -eq 'Update' }).Count
            $installActionStatusLabel.Text = "Install: $needsInstall | Update: $needsUpdate | Up to date: $upToDate"
        }

        & $updateInstallRowActionButtons
    }

    # Helper scriptblock: Load Install definitions from configured path
    $loadInstallDefinitions = {
        $definitionsRoot = ''
        if ($null -ne $intuneDefinitionsPathBox) {
            $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$intuneDefinitionsPathBox.Text)
            $intuneDefinitionsPathBox.Text = $definitionsRoot
            if ($null -ne $SyncHash.ApplyIntunePathsToConfig) {
                & ($SyncHash['ApplyIntunePathsToConfig'])
            }
        }
        elseif ($null -ne $SyncHash.Config.IntuneSettings) {
            $definitionsRoot = & $normalizeDirectoryPath -PathValue ([string]$SyncHash.Config.IntuneSettings.DefinitionsPath)
        }

        if ([string]::IsNullOrWhiteSpace($definitionsRoot)) {
            $SyncHash.InstallDefinitionRows = @()
            & $refreshInstallRows
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: set a package definitions folder path on the Packages tab first.' -Level Warning
            return
        }

        $definitionResult = Get-InstallPackageDefinitions -DefinitionsRoot $definitionsRoot
        if (-not $definitionResult.Succeeded) {
            $SyncHash.InstallDefinitionRows = @()
            & $refreshInstallRows
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: failed to load definitions: $($definitionResult.Error)" -Level Error
            return
        }

        $enrichedRows = @($definitionResult.Rows | ForEach-Object {
                [PSCustomObject]@{
                    DefinitionId         = [string]$_.DefinitionId
                    DefinitionPath       = [string]$_.DefinitionPath
                    Name                 = [string]$_.Name
                    Publisher            = [string]$_.Publisher
                    Version              = [string]$_.Version
                    Status               = [string]$_.Status
                    DefinitionValid      = [string]$_.DefinitionValid
                    PSPackageFactoryGuid = [string]$_.PSPackageFactoryGuid
                    DefinitionObject     = $_.DefinitionObject
                    LatestVersion        = ''
                }
            })

        # Hydrate LatestVersion from cache so values are visible immediately on load.
        $cacheFile = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\install-latest-cache.json'
        $cacheHits = 0
        $cacheExpired = 0
        $cacheFailed = 0
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            try {
                $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) {
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: cache file is empty.' -Level Warning
                }
                else {
                    $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                    $cacheEntries = if ($parsed -is [System.Array]) { @($parsed) } elseif ($null -ne $parsed) { @($parsed) } else { @() }
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: read $($cacheEntries.Count) entr$(if ($cacheEntries.Count -eq 1) {'y'} else {'ies'}) from cache '$cacheFile'." -Level Info
                    $nowUtc = [DateTime]::UtcNow
                    foreach ($row in $enrichedRows) {
                        $rowPath = ([string]$row.DefinitionPath).Trim()
                        $matchedEntry = $null
                        foreach ($c in $cacheEntries) {
                            if ($null -ne $c -and ([string]$c.DefinitionPath).Trim() -ieq $rowPath) {
                                $matchedEntry = $c
                                break
                            }
                        }
                        if ($null -eq $matchedEntry) { continue }
                        if (-not [bool]$matchedEntry.Succeeded) { $cacheFailed++; continue }

                        # Handle both DateTime and string timestamp formats
                        [DateTime]$retrievedUtc = [DateTime]::MinValue
                        $timestampOk = $false
                        $rawTimestamp = $matchedEntry.RetrievedUtc
                        if ($rawTimestamp -is [DateTime]) {
                            $retrievedUtc = [DateTime]$rawTimestamp
                            $timestampOk = $true
                        }
                        elseif ([DateTime]::TryParseExact([string]$rawTimestamp, 'o',
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::RoundtripKind,
                                [ref]$retrievedUtc)) {
                            $timestampOk = $true
                        }
                        elseif ([DateTime]::TryParse([string]$rawTimestamp,
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::None,
                                [ref]$retrievedUtc)) {
                            $timestampOk = $true
                        }

                        if ($timestampOk) {
                            if (($nowUtc - $retrievedUtc.ToUniversalTime()) -le [TimeSpan]::FromHours(24)) {
                                $row.LatestVersion = [string]$matchedEntry.Version
                                $cacheHits++
                            }
                            else {
                                $cacheExpired++
                            }
                        }
                    }
                    $cacheSkipParts = @()
                    if ($cacheExpired -gt 0) { $cacheSkipParts += "$cacheExpired expired" }
                    if ($cacheFailed -gt 0) { $cacheSkipParts += "$cacheFailed failed" }
                    if ($cacheSkipParts.Count -gt 0) {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: cache skipped $($cacheSkipParts -join ', ')." -Level Info
                    }
                }
            }
            catch {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: cache read error - $($_.Exception.Message)" -Level Warning
            }
        }
        else {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: no cache file found at '$cacheFile'." -Level Info
        }

        $SyncHash.InstallDefinitionRows = $enrichedRows
        & $setInstallElevationState
        & $refreshInstallRows

        $cacheMsg = if ($cacheHits -gt 0) { " ($cacheHits with cached latest version)" } else { '' }
        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: loaded $($enrichedRows.Count) App.json definitions$cacheMsg." -Level Info
    }

    # Helper scriptblock: Resolve latest versions for all loaded definitions (background async)
    $resolveInstallLatestVersions = {
        if ($SyncHash.IsInstallLoading) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: another operation is already in progress.' -Level Warning
            return
        }

        $definitionRows = @($SyncHash.InstallDefinitionRows | Where-Object {
                [string]$_.DefinitionValid -eq 'Yes' -and -not [string]::IsNullOrWhiteSpace([string]$_.DefinitionPath)
            })

        if ($definitionRows.Count -eq 0) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: no valid definitions loaded.' -Level Warning
            return
        }

        $outputPath = & $normalizeDirectoryPath -PathValue ([string]$outputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: set a download output path on the Downloads tab first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
            try {
                $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
            }
            catch {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: failed to create output path '$outputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        if ($null -ne $SyncHash.PendingInstallTimer -and $SyncHash.PendingInstallTimer.IsEnabled) {
            $SyncHash.PendingInstallTimer.Stop()
            $SyncHash.PendingInstallTimer = $null
        }
        foreach ($key in @('PendingInstallPS', 'PendingInstallRunspace', 'PendingInstallAsync')) {
            $SyncHash[$key] = $null
        }

        & $setInstallLoadingState -IsLoading $true -Message "Resolving latest versions for $($definitionRows.Count) package(s)..."

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $installCacheRootPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        $helperScripts = @(
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Invoke-PackageFilter.ps1'
            'Get-IntunePackageLatestVersion.ps1'
            'Get-InstallPackageLatestVersion.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $SyncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]$HelperScripts,
                    [object[]]$DefinitionRows,
                    [string]$CacheRootPath
                )

                $result = [PSCustomObject]@{
                    Success = $false
                    Rows    = @()
                    Error   = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Save-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    $cacheFilePath = Join-Path -Path $CacheRootPath -ChildPath 'install-latest-cache.json'
                    if (Test-Path -LiteralPath $cacheFilePath -PathType Leaf) {
                        & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Install: reading latest version cache from '$cacheFilePath'." -Level Info
                    }
                    else {
                        & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Install: no cache found at '$cacheFilePath', all versions will be fetched live." -Level Info
                    }
                    $cacheState = Initialize-InstallLatestCache -CacheFile $cacheFilePath

                    $rows = [System.Collections.Generic.List[object]]::new()
                    foreach ($definitionRow in $DefinitionRows) {
                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$definitionRow.DefinitionPath) -DefinitionObject $definitionRow.DefinitionObject -CacheRootPath $CacheRootPath -CacheState $cacheState
                        $rows.Add([PSCustomObject]@{
                                DefinitionPath = [string]$definitionRow.DefinitionPath
                                Succeeded      = [bool]$latestResult.Succeeded
                                LatestVersion  = [string]$latestResult.Version
                                LatestError    = [string]$latestResult.Error
                                IsFromCache    = [bool]$latestResult.IsFromCache
                            })
                    }

                    $writeCount = @($rows | Where-Object { -not [bool]$_.IsFromCache }).Count
                    $cacheWasWritten = Save-InstallLatestCache -CacheState $cacheState
                    if ($cacheWasWritten -and $writeCount -gt 0) {
                        & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Install: wrote $writeCount $(if ($writeCount -eq 1) { 'entry' } else { 'entries' }) to cache at '$cacheFilePath'." -Level Info
                    }

                    $result.Success = $true
                    $result.Rows = @($rows)
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            }).AddArgument(@($helperScripts)).AddArgument(@($definitionRows)).AddArgument($installCacheRootPath)

        $completionAction_InstallLatestVersion = {
            param($Operation, $Result, $State)

            $completionResult = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $completionResult = $Result.Output[0]
            }
            elseif ($Result.Error) {
                $completionResult = [PSCustomObject]@{ Success = $false; Rows = @(); Error = $Result.Error.Exception.Message }
            }
            else {
                $completionResult = $null
            }

            try {
                if ($null -eq $completionResult -or -not $completionResult.Success) {
                    $err = if ($null -eq $completionResult -or [string]::IsNullOrWhiteSpace([string]$completionResult.Error)) { 'Unknown latest version error.' } else { [string]$completionResult.Error }
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: latest version resolution failed: $err" -Level Error
                }
                else {
                    $latestMap = @{}
                    foreach ($row in @($completionResult.Rows)) {
                        $latestMap[[string]$row.DefinitionPath] = $row
                    }

                    foreach ($definitionRow in @($SyncHash.InstallDefinitionRows)) {
                        $key = [string]$definitionRow.DefinitionPath
                        if (-not $latestMap.ContainsKey($key)) {
                            continue
                        }

                        $latestRow = $latestMap[$key]
                        if ([bool]$latestRow.Succeeded) {
                            $definitionRow.LatestVersion = [string]$latestRow.LatestVersion
                        }
                        else {
                            $definitionRow.LatestVersion = ''
                            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: latest lookup failed for '$([string]$definitionRow.Name)': $([string]$latestRow.LatestError)" -Level Warning
                        }
                    }

                    $cacheCount = @($completionResult.Rows | Where-Object { [bool]$_.Succeeded -and [bool]$_.IsFromCache }).Count
                    $freshCount = @($completionResult.Rows | Where-Object { [bool]$_.Succeeded -and -not [bool]$_.IsFromCache }).Count
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: latest version resolution complete ($freshCount live, $cacheCount cache)." -Level Info
                }

                # After latest lookup finishes, show highest-priority statuses first.
                $SyncHash.InstallSortProperty = 'InstallStatus'
                $SyncHash.InstallSortDirection = 'Ascending'

                & $refreshInstallRows
            }
            finally {
                & $setInstallLoadingState -IsLoading $false
            }
        }

        & $RegisterBackgroundOperation -Feature 'Install' -OperationId 'LatestVersion' -PowerShellInstance $ps -RunspaceInstance $rs -CompletionAction $completionAction_InstallLatestVersion
    }

    # Helper scriptblock: Start installation operation for selected packages (background async)
    $startInstallSelectedOperation = {
        if ($SyncHash.IsInstallLoading) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: another operation is already in progress.' -Level Warning
            return
        }

        $selectedRows = @($installPackagesListView.SelectedItems)
        $actionableRows = @($selectedRows | Where-Object {
                [string]$_.InstallAction -eq 'Install' -or [string]$_.InstallAction -eq 'Update'
            })

        if ($actionableRows.Count -eq 0) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: select one or more rows with Install or Update action.' -Level Warning
            return
        }

        $outputPath = & $normalizeDirectoryPath -PathValue ([string]$outputPathBox.Text)
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: set a download output path on the Downloads tab first.' -Level Warning
            return
        }

        if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
            try {
                $null = New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop
            }
            catch {
                & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: failed to create output path '$outputPath': $($_.Exception.Message)" -Level Error
                return
            }
        }

        if (-not (& $testInstallElevationState)) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: running without elevation. Installer may trigger a UAC prompt.' -Level Warning
        }

        if ($null -ne $SyncHash.PendingInstallTimer -and $SyncHash.PendingInstallTimer.IsEnabled) {
            $SyncHash.PendingInstallTimer.Stop()
            $SyncHash.PendingInstallTimer = $null
        }
        foreach ($key in @('PendingInstallPS', 'PendingInstallRunspace', 'PendingInstallAsync')) {
            $SyncHash[$key] = $null
        }

        $installActions = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $actionableRows) {
            if ([string]::IsNullOrWhiteSpace([string]$row.DefinitionPath)) {
                continue
            }

            $installActions.Add([PSCustomObject]@{
                    Name           = [string]$row.Name
                    DefinitionPath = [string]$row.DefinitionPath
                })
        }

        if ($installActions.Count -eq 0) {
            & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message 'Install: no valid definition paths were selected.' -Level Warning
            return
        }

        & $setInstallLoadingState -IsLoading $true -Message "Installing $($installActions.Count) package(s)..."

        $privateRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Private') -ErrorAction SilentlyContinue
        $privateRootPath = if ($null -ne $privateRoot) { $privateRoot.Path } else { Join-Path -Path $PSScriptRoot -ChildPath '..\Private' }
        $installCacheRootPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        $helperScripts = @(
            'Format-LogEntry.ps1'
            'Write-UILog.ps1'
            'Read-PackageDefinition.ps1'
            'Get-SafeFolderName.ps1'
            'Invoke-PackageFilter.ps1'
            'Get-IntunePackageLatestVersion.ps1'
            'Get-InstallPackageLatestVersion.ps1'
            'Invoke-LocalPackageInstall.ps1'
            'Test-LocalPackageDetection.ps1'
        ) | ForEach-Object { Join-Path -Path $privateRootPath -ChildPath $_ }

        $rs = New-WpfRunspace -SyncHash $SyncHash
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
                param(
                    [string[]]$HelperScripts,
                    [object[]]$InstallActions,
                    [string]$OutputPath,
                    [string]$CacheRootPath
                )

                $result = [PSCustomObject]@{
                    Success   = $false
                    Completed = @()
                    Failed    = @()
                    Error     = ''
                }

                try {
                    foreach ($scriptPath in $HelperScripts) {
                        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                            throw "Required helper script not found: $scriptPath"
                        }
                        . $scriptPath
                    }

                    if (-not (Get-Command -Name 'Save-EvergreenApp' -ErrorAction SilentlyContinue)) {
                        Import-Module -Name Evergreen -ErrorAction Stop | Out-Null
                    }

                    $completed = [System.Collections.Generic.List[object]]::new()
                    $failed = [System.Collections.Generic.List[object]]::new()

                    foreach ($action in $InstallActions) {
                        $readResult = Read-PackageDefinition -Path ([string]$action.DefinitionPath)
                        if (-not $readResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = $readResult.Error
                                })
                            continue
                        }
                        $definitionObject = $readResult.Definition

                        $latestResult = Get-InstallPackageLatestVersion -DefinitionPath ([string]$action.DefinitionPath) -DefinitionObject $definitionObject -CacheRootPath $CacheRootPath
                        if (-not [string]::IsNullOrWhiteSpace([string]$latestResult.CacheFile)) {
                            if ([bool]$latestResult.IsFromCache) {
                                & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Install: cache read for '$([string]$action.Name)' - $([string]$latestResult.Version) from '$([string]$latestResult.CacheFile)'." -Level Info
                            }
                            elseif ([bool]$latestResult.Succeeded) {
                                & ($SyncHash['WriteUILog']) -SyncHash $syncHash -Message "Install: wrote to cache for '$([string]$action.Name)' - $([string]$latestResult.Version) at '$([string]$latestResult.CacheFile)'." -Level Info
                            }
                        }
                        if (-not $latestResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = "Latest lookup failed: $($latestResult.Error)"
                                })
                            continue
                        }

                        $installResult = Invoke-LocalPackageInstall -DefinitionPath ([string]$action.DefinitionPath) -DefinitionObject $definitionObject -WorkingPath $OutputPath -LatestVersionResult $latestResult -SyncHash $syncHash
                        if (-not $installResult.Succeeded) {
                            $failed.Add([PSCustomObject]@{
                                    Name           = [string]$action.Name
                                    DefinitionPath = [string]$action.DefinitionPath
                                    Error          = [string]$installResult.Error
                                })
                            continue
                        }

                        $detectionResult = Test-LocalPackageDetection -DefinitionObject $definitionObject
                        $completed.Add([PSCustomObject]@{
                                Name             = [string]$action.Name
                                DefinitionPath   = [string]$action.DefinitionPath
                                InstalledVersion = [string]$detectionResult.DetectedVersion
                                LatestVersion    = [string]$latestResult.Version
                                ExitCode         = [int]$installResult.ExitCode
                            })
                    }

                    $result.Success = $true
                    $result.Completed = @($completed)
                    $result.Failed = @($failed)
                }
                catch {
                    $result.Error = $_.Exception.Message
                }

                return $result
            }).AddArgument(@($helperScripts)).AddArgument(@($installActions)).AddArgument($outputPath).AddArgument($installCacheRootPath)

        $completionAction_InstallExecute = {
            param($Operation, $Result, $State)

            $completionResult = $null
            if ($Result.WasCompleted -and $Result.Output.Count -gt 0) {
                $completionResult = $Result.Output[0]
            }
            elseif ($Result.Error) {
                $completionResult = [PSCustomObject]@{ Success = $false; Completed = @(); Failed = @(); Error = $Result.Error.Exception.Message }
            }
            else {
                $completionResult = $null
            }

            try {
                if ($null -eq $completionResult -or -not $completionResult.Success) {
                    $err = if ($null -eq $completionResult -or [string]::IsNullOrWhiteSpace([string]$completionResult.Error)) { 'Unknown install error.' } else { [string]$completionResult.Error }
                    & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: operation failed: $err" -Level Error
                }
                else {
                    foreach ($item in @($completionResult.Completed)) {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: completed '$([string]$item.Name)' (exit code $([int]$item.ExitCode))." -Level Info
                        foreach ($definitionRow in @($SyncHash.InstallDefinitionRows)) {
                            if ([string]$definitionRow.DefinitionPath -eq [string]$item.DefinitionPath) {
                                $definitionRow.LatestVersion = [string]$item.LatestVersion
                                break
                            }
                        }
                    }

                    foreach ($item in @($completionResult.Failed)) {
                        & ($SyncHash['WriteUILog']) -SyncHash $SyncHash -Message "Install: failed '$([string]$item.Name)': $([string]$item.Error)" -Level Error
                    }
                }

                & $setInstallElevationState
                & $refreshInstallRows
            }
            finally {
                & $setInstallLoadingState -IsLoading $false
            }
        }

        & $RegisterBackgroundOperation -Feature 'Install' -OperationId 'Execute' -PowerShellInstance $ps -RunspaceInstance $rs -CompletionAction $completionAction_InstallExecute
    }

    # Store helper scriptblocks in SyncHash for access by other features
    $SyncHash['SetInstallElevationState'] = $setInstallElevationState.GetNewClosure()
    $SyncHash['SetInstallLoadingState'] = $setInstallLoadingState.GetNewClosure()
    $SyncHash['RefreshInstallRows'] = $refreshInstallRows.GetNewClosure()
    $SyncHash['LoadInstallDefinitions'] = $loadInstallDefinitions.GetNewClosure()
    $SyncHash['ResolveInstallLatestVersions'] = $resolveInstallLatestVersions.GetNewClosure()
    $SyncHash['StartInstallSelectedOperation'] = $startInstallSelectedOperation.GetNewClosure()
    $SyncHash['UpdateInstallRowActionButtons'] = $updateInstallRowActionButtons.GetNewClosure()

    # Event handler: InstallLoadDefinitionsButton - Load package definitions
    if ($null -ne $installLoadDefinitionsButton) {
        $installLoadDefinitionsButton.add_Click({
                & $loadInstallDefinitions
            }.GetNewClosure())
    }

    # Event handler: InstallResolveLatestButton - Resolve latest versions for all definitions
    if ($null -ne $installResolveLatestButton) {
        $installResolveLatestButton.add_Click({
                & $resolveInstallLatestVersions
            }.GetNewClosure())
    }

    # Event handler: InstallPackagesListView.SelectionChanged - Update action button state
    if ($null -ne $installPackagesListView) {
        $installPackagesListView.add_SelectionChanged({
                & $updateInstallRowActionButtons
            }.GetNewClosure())
    }

    # Event handler: InstallPackagesListView column header click (sorting)
    $installPackagesListView.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]({
            param($eventSender, $routedEventArgs)

            $header = $routedEventArgs.OriginalSource -as [System.Windows.Controls.GridViewColumnHeader]
            if ($null -eq $header -or $null -eq $header.Column) {
                return
            }

            if ($header.Role -eq [System.Windows.Controls.GridViewColumnHeaderRole]::Padding) {
                return
            }

            $sortProperty = ''
            $binding = $header.Column.DisplayMemberBinding -as [System.Windows.Data.Binding]
            if ($null -ne $binding -and $null -ne $binding.Path) {
                $sortProperty = [string]$binding.Path.Path
            }

            if ([string]::IsNullOrWhiteSpace($sortProperty)) {
                return
            }

            $newDirection = 'Ascending'
            if ([string]$SyncHash.InstallSortProperty -eq $sortProperty -and [string]$SyncHash.InstallSortDirection -eq 'Ascending') {
                $newDirection = 'Descending'
            }

            $SyncHash.InstallSortProperty = $sortProperty
            $SyncHash.InstallSortDirection = $newDirection

            & $applyInstallListSort
        }.GetNewClosure())
    )

    # Event handler: InstallApplyButton - Start installation operation
    if ($null -ne $installApplyButton) {
        $installApplyButton.add_Click({
                & $startInstallSelectedOperation
            }.GetNewClosure())
    }

    # Event handler: InstallHideIncompatibleArchitectureToggle - Filter ListView by architecture
    if ($null -ne $installHideIncompatibleArchitectureToggle) {
        $installHideIncompatibleArchitectureToggle.add_Click({
                $hideIncompatibleArchitecture = [bool]$installHideIncompatibleArchitectureToggle.IsChecked
                if ($null -eq $SyncHash.Config.InstallSettings) {
                    $SyncHash.Config | Add-Member -NotePropertyName 'InstallSettings' -NotePropertyValue ([PSCustomObject]@{ HideIncompatibleArchitecture = $hideIncompatibleArchitecture }) -Force
                }
                else {
                    $SyncHash.Config.InstallSettings.HideIncompatibleArchitecture = $hideIncompatibleArchitecture
                }
                & ($SyncHash['SetUIConfig']) -Config $SyncHash.Config
                & $refreshInstallRows
            }.GetNewClosure())
    }

    Write-Verbose 'EvergreenUI: Install feature registered.'
}
