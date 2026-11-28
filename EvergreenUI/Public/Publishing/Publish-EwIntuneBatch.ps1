Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwIntuneBatch {
    <#
    .SYNOPSIS
        Builds and publishes selected Intune definitions.
    .DESCRIPTION
        Revalidates confirmed comparison rows, builds packages sequentially,
        updates outdated definitions, and publishes with supersedence where
        applicable. Reports partial changes without deleting created apps.
    .PARAMETER DefinitionPath
        Root folder containing the compared definitions.
    .PARAMETER Selection
        Confirmed comparison rows with DefinitionHash, InstallHash, and
        ImportAsUpdate properties. DefinitionView rows also pin the resolved
        version, URI, architectures and complete matching-app snapshot.
    .PARAMETER WorkingPath
        Package working and output folder.
    .PARAMETER TenantId
        Tenant ID confirmed for the batch.
    .PARAMETER CancellationToken
        Optional token checked between definitions.
    .EXAMPLE
        Publish-EwIntuneBatch -DefinitionPath C:\Apps -Selection $rows -WorkingPath C:\Packages -TenantId $tenantId
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Matching is rechecked before publishing but is not an atomic Graph lock.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Selection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Selection) {
        if ([string]::IsNullOrWhiteSpace([string]$item.DefinitionPath) -or
            -not $paths.Add([string]$item.DefinitionPath)) {
            throw 'Every selected Definition must have a unique path.'
        }
        if ($item.MatchStatus -notin @('No matching Win32 app', 'Matched (current)', 'Matched (update required)')) {
            throw "Definition '$($item.DefinitionPath)' is not eligible for publishing."
        }
        if ([bool]$item.ImportAsUpdate -and [string]::IsNullOrWhiteSpace([string]$item.IntuneAppId)) {
            throw 'Update-app mode requires one matching Intune app.'
        }
        if ($null -ne $item.PSObject.Properties['AvailableVersion']) {
            $blocker = if ($item.ImportAsUpdate) { $item.UpdateBlocker } else { $item.DeploymentBlocker }
            if ($blocker) { throw "Definition '$($item.DefinitionName)' is not eligible: $blocker" }
        }
    }
    if (@($Selection | Select-Object -ExpandProperty ImportAsUpdate -Unique).Count -gt 1) {
        throw 'An Intune batch must use one deployment intent.'
    }
    if (-not $PSCmdlet.ShouldProcess("$($Selection.Count) definitions in tenant $TenantId", 'Build and publish Intune apps')) {
        return
    }

    Assert-EwModule -Name Microsoft.Graph.Authentication
    $stopReason = ''
    $itemNumber = 0
    foreach ($item in $Selection) {
        $itemNumber++
        Write-Progress -Activity 'Building and publishing Intune apps' `
            -Status "$itemNumber of $($Selection.Count): $($item.DefinitionName)" `
            -PercentComplete ([int](100 * ($itemNumber - 1) / $Selection.Count))
        $result = [PSCustomObject]@{
            Name = [string]$item.DefinitionName
            DefinitionPath = [string]$item.DefinitionPath
            Succeeded = $false
            Status = 'Failed'
            PreviousAppId = [string]$item.IntuneAppId
            IntuneAppId = ''
            PackagePath = ''
            Version = ''
            DisplayName = ''
            CreationStatus = 'Not started'
            AssignmentStatus = 'Not started'
            SupersedenceStatus = if ($item.IntuneAppId) { 'Not started' } else { 'Not applicable' }
            ChangedPaths = @()
            Error = ''
        }
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'
            $result.Error = 'Not started: batch cancellation was requested.'
            $result
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($stopReason)) {
            $result.Status = 'Not started'
            $result.Error = $stopReason
            $result
            continue
        }
        try {
            $planned = $null -ne $item.PSObject.Properties['AvailableVersion']
            $context = Get-MgContext -ErrorAction Stop
            if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
                $stopReason = 'The confirmed Intune connection is no longer active. The batch stopped.'
                $result.Error = $stopReason
                $result
                continue
            }
            $installPath = Join-Path -Path (Split-Path -Path $item.DefinitionPath -Parent) -ChildPath 'Source\Install.json'
            $definitionHash = (Get-FileHash -LiteralPath $item.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
            $installHash = if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
            } else { '' }
            if ($definitionHash -ne [string]$item.DefinitionHash -or $installHash -ne [string]$item.InstallHash) {
                throw 'Definition files changed after confirmation. Refresh the comparison and review them.'
            }
            if ($planned) {
                Assert-EwIntunePublishPlan -DefinitionPath $DefinitionPath -Item $item
            }
            else {
                $comparisonRows = @(Compare-EwIntuneApp -DefinitionPath $DefinitionPath |
                    Where-Object { $_.DefinitionPath -eq $item.DefinitionPath })
                if ($comparisonRows.Count -ne 1 -or $comparisonRows[0].MatchStatus -ne $item.MatchStatus -or
                    $comparisonRows[0].IntuneAppId -ne $item.IntuneAppId -or
                    $comparisonRows[0].IntuneVersion -ne $item.IntuneVersion -or
                    $comparisonRows[0].DefinitionVersion -ne $item.DefinitionVersion -or
                    $comparisonRows[0].PSPackageFactoryGuid -ne $item.PSPackageFactoryGuid) {
                    throw 'The Intune match changed after confirmation. Refresh the comparison and review it.'
                }
            }

            Write-Verbose -Message "EvergreenUI: Building '$($item.DefinitionName)' for tenant '$TenantId'"
            $package = New-EwPackage -DefinitionPath $item.DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            if (-not $package.Succeeded) { throw "Package build failed: $($package.Error)" }
            $result.PackagePath = [string]$package.PackagePath
            $result.Version = [string]$package.Version
            if ($planned -and [string]$package.Version -cne [string]$item.AvailableVersion) {
                throw 'The built version differs from the confirmed import version. Refresh and confirm a new plan.'
            }
            $definition = Get-Content -LiteralPath $item.DefinitionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $item.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $definitionHash -or
                $(if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                    (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
                } else { '' }) -ne $installHash) {
                throw 'Definition files changed during the build. Review them before publishing.'
            }
            if ([string]$definition.PackageInformation.Version -ne [string]$package.Version -or
                [string]$definition.PackageInformation.SetupFile -ne [string]$package.SetupFile) {
                $update = @(Update-EwDefinition -DefinitionPath $item.DefinitionPath -Confirm:$false)
                if ($update.Count -ne 1) { throw 'Definition update returned an unexpected result.' }
                $result.ChangedPaths = @($update[0].ChangedPaths)
                if (-not $update[0].Succeeded) { throw "Definition update failed: $($update[0].Error)" }
                $definitionHash = (Get-FileHash -LiteralPath $item.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
                $installHash = if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                    (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
                } else { '' }
                $package = New-EwPackage -DefinitionPath $item.DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
                if (-not $package.Succeeded) { throw "Package rebuild failed: $($package.Error)" }
                $result.PackagePath = [string]$package.PackagePath
                $result.Version = [string]$package.Version
                if ($planned -and [string]$package.Version -cne [string]$item.AvailableVersion) {
                    throw 'The rebuilt version differs from the confirmed import version. Refresh and confirm a new plan.'
                }
                $definition = Get-Content -LiteralPath $item.DefinitionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            }
            if ([string]$definition.PackageInformation.Version -ne [string]$package.Version -or
                [string]$definition.PackageInformation.SetupFile -ne [string]$package.SetupFile) {
                throw 'The rebuilt package does not match the updated Definition. Review it before publishing.'
            }
            if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                $install = Get-Content -LiteralPath $installPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $installPackage = $install.PSObject.Properties['PackageInformation']
                if ($null -ne $installPackage -and $null -ne $installPackage.Value -and
                    ([string]$installPackage.Value.Version -ne [string]$package.Version -or
                        [string]$installPackage.Value.SetupFile -ne [string]$package.SetupFile)) {
                    throw 'Source\Install.json does not match the built package. Review it before publishing.'
                }
            }
            if ($planned) {
                Assert-EwIntunePublishPlan -DefinitionPath $DefinitionPath -Item $item -AfterBuild
            }
            else {
                $comparisonRows = @(Compare-EwIntuneApp -DefinitionPath $DefinitionPath |
                    Where-Object { $_.DefinitionPath -eq $item.DefinitionPath })
                if ($comparisonRows.Count -ne 1 -or $comparisonRows[0].MatchStatus -notin @('No matching Win32 app', 'Matched (current)', 'Matched (update required)') -or
                    $comparisonRows[0].IntuneAppId -ne $item.IntuneAppId -or
                    $comparisonRows[0].IntuneVersion -ne $item.IntuneVersion -or
                    $comparisonRows[0].PSPackageFactoryGuid -ne $item.PSPackageFactoryGuid) {
                    throw 'The Intune match changed during the build. Refresh the comparison and review it.'
                }
            }
            if ((Get-FileHash -LiteralPath $item.DefinitionPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $definitionHash -or
                $(if (Test-Path -LiteralPath $installPath -PathType Leaf) {
                    (Get-FileHash -LiteralPath $installPath -Algorithm SHA256 -ErrorAction Stop).Hash
                } else { '' }) -ne $installHash) {
                throw 'Definition files changed during the build. Review them before publishing.'
            }
            $context = Get-MgContext -ErrorAction Stop
            if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
                $stopReason = 'The confirmed Intune connection is no longer active. The batch stopped.'
                $result.Error = $stopReason
                $result
                continue
            }
            $published = Publish-EwIntuneApp -DefinitionPath $item.DefinitionPath -PackagePath $package.PackagePath `
                -Version $package.Version -SetupFile $package.SetupFile -ImportAsUpdate:([bool]$item.ImportAsUpdate) -Confirm:$false
            $result.IntuneAppId = [string]$published.IntuneAppId
            $result.DisplayName = [string](Get-EwObjectPropertyValue -Object $published -Name 'DisplayName' -Default "$($item.DefinitionName) $($package.Version)")
            $result.CreationStatus = if ($result.IntuneAppId) { 'Created' } else { 'Failed' }
            $result.AssignmentStatus = [string](Get-EwObjectPropertyValue -Object $published -Name 'AssignmentStatus' -Default $(if ($published.Succeeded) { 'Applied' } else { 'Incomplete' }))
            if (-not $published.Succeeded) { throw "Publish failed: $($published.Error)" }
            if (-not [string]::IsNullOrWhiteSpace([string]$item.IntuneAppId)) {
                $link = Set-EwIntuneSupersedence -NewAppId $published.IntuneAppId -PreviousAppId $item.IntuneAppId -Confirm:$false
                if (-not $link.Succeeded) {
                    $result.Status = 'Supersedence failed'
                    $result.SupersedenceStatus = 'Failed'
                    throw "App published, but supersedence failed: $($link.Error)"
                }
                $result.SupersedenceStatus = 'Linked'
            }
            $result.Succeeded = $true
            $result.Status = 'Published'
            Write-Verbose -Message "EvergreenUI: Published '$($item.DefinitionName)' as '$($result.IntuneAppId)'"
        }
        catch {
            $result.Error = $_.Exception.Message
            Write-Verbose -Message "EvergreenUI: Publishing '$($item.DefinitionName)' failed: $($result.Error)"
            try {
                $context = Get-MgContext -ErrorAction Stop
                if ($null -eq $context -or [string]$context.TenantId -ne $TenantId) {
                    throw 'The confirmed Graph context is unavailable.'
                }
                Write-Verbose -Message "EvergreenUI: Checking Intune access after the failed item"
                $healthUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$top=1&$select=id'
                Invoke-MgGraphRequest -Method GET -Uri $healthUri -OutputType PSObject -ErrorAction Stop | Out-Null
            }
            catch {
                $stopReason = "Intune access could not be verified. The batch stopped: $($_.Exception.Message)"
                $result.Error = "$($result.Error) $stopReason"
                Write-Verbose -Message "EvergreenUI: $stopReason"
            }
        }
        $result
    }
    Write-Progress -Activity 'Building and publishing Intune apps' -Completed
}
