Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwM365IntuneApp {
    <#
    .SYNOPSIS
        Builds and publishes one confirmed Microsoft 365 Intune app.
    .DESCRIPTION
        Rechecks the preview and matches, persists recovery intent before
        provider writes, and preserves known app and supersedence outcomes.
    .PARAMETER Plan
        Confirmed Get-EwM365IntunePublishPlan result.
    .PARAMETER WorkingPath
        Root directory for staging and package output.
    .PARAMETER Force
        Replace an existing output package after explicit confirmation.
    .PARAMETER CancellationToken
        Cancellation checked between stages, never during a provider request.
    .EXAMPLE
        Publish-EwM365IntuneApp -Plan $plan -WorkingPath C:\Packages
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkingPath,
        [switch]$Force,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    if (-not $PSCmdlet.ShouldProcess($Plan.BuildPlan.ConfigurationId, 'Build and publish Microsoft 365 Intune app')) { return }
    $result = [PSCustomObject]@{
        Succeeded = $false; Status = 'Failed'; PackagePath = ''; Version = [string]$Plan.BuildPlan.OfficeVersion
        IntuneAppId = ''; PreviousAppId = [string]$Plan.PreviousAppId
        SupersedenceStatus = 'Not requested'; RecoveryId = ''; Error = ''
    }
    $record = $null
    $writeStarted = $false
    try {
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled before building.'
            return $result
        }
        Assert-EwM365IntunePublishPlan -Plan $Plan
        $build = $Plan.BuildPlan
        $package = New-EwPackage -M365ConfigurationPath $build.ConfigurationPath -ConfigurationRoot $build.ConfigurationRoot `
            -WorkingPath $WorkingPath -Provider Intune -Channel $build.Channel -CompanyName $build.CompanyName `
            -ImportFor $build.ImportFor -TenantId $build.TenantId -AppJsonTemplatePath $build.AppJsonTemplatePath `
            -M365Plan $build -Force:$Force -Confirm:$false
        if (-not $package.Succeeded) { throw "Microsoft 365 package build failed: $($package.Error)" }
        $result.PackagePath = [string]$package.PackagePath
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled after building and before publishing.'
            return $result
        }
        Assert-EwM365IntunePublishPlan -Plan $Plan
        $definitionPath = Join-Path -Path $package.SourcePath -ChildPath 'App.json'
        $packageHash = (Get-FileHash -LiteralPath $package.PackagePath -Algorithm SHA256 -ErrorAction Stop).Hash
        $definitionHash = (Get-FileHash -LiteralPath $definitionPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $process = [System.Diagnostics.Process]::GetCurrentProcess()
        try { $startTicks = $process.StartTime.ToUniversalTime().Ticks }
        finally { $process.Dispose() }
        $intent = [ordered]@{
            Id = [guid]::NewGuid().ToString(); TenantId = [string]$build.TenantId
            ConfigurationId = [string]$build.ConfigurationId; Stage = 'Create'; Status = 'InProgress'
            AppId = ''; PreviousAppId = [string]$Plan.PreviousAppId
            StartedAt = [DateTimeOffset]::UtcNow.ToString('o')
            OwnerProcessId = $PID; OwnerStartTimeTicks = $startTicks
        }
        $null = Invoke-EwM365IntuneRecoveryStore -Action Begin -Record $intent
        $record = $intent
        $result.RecoveryId = $record.Id
        Assert-EwM365IntunePublishPlan -Plan $Plan
        if ($CancellationToken.IsCancellationRequested) {
            $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id $record.Id
            $record = $null
            $result.RecoveryId = ''; $result.Status = 'Cancelled'; $result.Error = 'Cancelled before the Intune request.'
            return $result
        }
        $writeStarted = $true
        $published = Publish-EwIntuneApp -DefinitionPath $definitionPath -PackagePath $package.PackagePath `
            -Version $package.Version -SetupFile $package.SetupFile -M365Plan $Plan `
            -M365PackageHash $packageHash -M365DefinitionHash $definitionHash -CancellationToken $CancellationToken -Confirm:$false
        $result.IntuneAppId = [string]$published.IntuneAppId
        $record.AppId = $result.IntuneAppId
        if (-not $published.Succeeded -or [string]::IsNullOrWhiteSpace($result.IntuneAppId)) {
            if ([bool](Get-EwFirstPropertyValue -InputObject $published -Name 'Cancelled')) {
                if (-not [bool](Get-EwFirstPropertyValue -InputObject $published -Name 'WriteStarted')) {
                    $writeStarted = $false
                }
                $result.Status = 'Cancelled'
            }
            throw "Intune app creation or content publishing requires review: $($published.Error)"
        }
        $record.Stage = 'Published'
        $null = Invoke-EwM365IntuneRecoveryStore -Action Update -Record $record
        $writeStarted = $false
        if ($Plan.PreviousAppId) {
            $result.SupersedenceStatus = 'Not attempted'
            if ($CancellationToken.IsCancellationRequested) {
                $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id $record.Id
                $record = $null
                $result.RecoveryId = ''; $result.Status = 'Cancelled'
                $result.Error = 'App published; cancelled before supersedence.'
                return $result
            }
            Assert-EwM365BuildPlan -Plan $build
            $previous = @($Plan.Matches | Where-Object { $_.Id -eq $Plan.PreviousAppId })
            $current = @(Get-EwM365IntuneMatch -ConfigurationId $build.ConfigurationId |
                    Where-Object { $_.Id -eq $Plan.PreviousAppId })
            if ($current.Count -ne 1 -or $previous.Count -ne 1 -or
                $current[0].Name -cne $previous[0].Name -or $current[0].Version -cne $previous[0].Version) {
                throw 'App published, but the selected supersedence target changed. Review it before proceeding.'
            }
            if ($CancellationToken.IsCancellationRequested) {
                $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id $record.Id
                $record = $null
                $result.RecoveryId = ''; $result.Status = 'Cancelled'
                $result.Error = 'App published; cancelled before supersedence.'
                return $result
            }
            $record.Stage = 'Supersedence'
            $null = Invoke-EwM365IntuneRecoveryStore -Action Update -Record $record
            $writeStarted = $true
            $link = Set-EwIntuneSupersedence -NewAppId $result.IntuneAppId -PreviousAppId $Plan.PreviousAppId -Confirm:$false
            if (-not $link.Succeeded) {
                $result.SupersedenceStatus = 'Unknown'
                throw "App published; supersedence outcome requires review: $($link.Error)"
            }
            $result.SupersedenceStatus = 'Completed'
        }
        $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id $record.Id
        $record = $null
        $result.RecoveryId = ''; $result.Succeeded = $true; $result.Status = 'Published'
    }
    catch {
        $result.Error = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
        if ($null -ne $record) {
            if ($writeStarted) {
                $record.Status = 'Unknown'
                $null = Invoke-EwM365IntuneRecoveryStore -Action Update -Record $record
                if ($result.Status -ne 'Cancelled') { $result.Status = 'Unknown' }
            }
            else {
                $null = Invoke-EwM365IntuneRecoveryStore -Action Finish -Id $record.Id
                $result.RecoveryId = ''
                if ($result.IntuneAppId) { $result.Status = 'Published; supersedence not attempted' }
            }
        }
        Write-Verbose -Message "EvergreenUI: Microsoft 365 Intune publishing stopped: $($result.Error)"
    }
    return $result
}
