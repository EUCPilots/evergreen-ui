Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwNerdioApp {
    <#
    .SYNOPSIS
        Publishes a Nerdio Shell App or adds a version.
    .DESCRIPTION
        Validates request content before upload and preserves partial blob,
        app and job identifiers. Pending and unknown outcomes are not success.
    .PARAMETER DefinitionPath
        Directory containing Definition.json and the scripts required for creation.
    .PARAMETER ShellAppId
        Existing Shell App ID to add a version to.
    .PARAMETER PackagePath
        Installer or archive to upload; resolved from the source when omitted.
    .PARAMETER Version
        Version label; resolved from the source when omitted.
    .PARAMETER DownloadPath
        Folder for source downloads; defaults to a temporary directory.
    .PARAMETER Snapshot
        Confirmed publishing-plan item and destination, rechecked before writes.
    .PARAMETER M365Plan
        Confirmed Microsoft 365 publishing plan, rechecked before writes.
    .PARAMETER M365PackageHash
        SHA256 hash of the package produced for the Microsoft 365 preview.
    .PARAMETER CancellationToken
        Optional cancellation checked before upload and after it completes.
    .EXAMPLE
        Publish-EwNerdioApp -DefinitionPath C:\ShellApps\Chrome -ShellAppId 42
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio. No automatic retry or cleanup is performed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Create')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,
        [Parameter(Mandatory, ParameterSetName = 'AddVersion')]
        [string]$ShellAppId,
        [string]$PackagePath,
        [string]$Version,
        [string]$DownloadPath,
        [psobject]$Snapshot,
        [psobject]$M365Plan,
        [string]$M365PackageHash,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    $result = [PSCustomObject]@{
        Succeeded = $false; AppId = [string]$ShellAppId; JobId = ''; BlobName = ''; Version = $Version
        Status = 'Failed'; Error = ''
    }
    $fail = {
        param([string]$Message)
        $result.Error = $Message
        $result
    }
    $addVersion = $PSCmdlet.ParameterSetName -eq 'AddVersion'
    $postStarted = $false
    $recoveryOperation = $null
    if (-not $PSCmdlet.ShouldProcess($DefinitionPath, 'Upload and publish Nerdio Shell App')) { return }
    try {
        $context = Get-EwNerdioSessionContext
        if ($context.PSObject.Properties['ApiOnly'] -and $context.ApiOnly) {
            throw 'A full Nerdio connection with Azure storage is required for publishing.'
        }
        Assert-EwNerdioWriteAllowed -Context $context -ShellAppId $ShellAppId
        $definition = Get-EwNerdioPublishContent -DefinitionPath $DefinitionPath -AddVersion:$addVersion
        if ($null -ne $M365Plan) {
            if ($null -ne $Snapshot -or $DefinitionPath -ne (Join-Path -Path $M365Plan.BuildPlan.ConfigurationRoot -ChildPath 'shell-app') -or
                $Version -ne $M365Plan.BuildPlan.OfficeVersion -or [string]::IsNullOrWhiteSpace($M365PackageHash) -or
                [string]$ShellAppId -ne [string]$M365Plan.ShellAppId -or
                $addVersion -ne ($M365Plan.Operation -eq 'Add version')) {
                throw 'Publish arguments do not match the confirmed Microsoft 365 preview.'
            }
            Assert-EwM365NerdioPublishPlan -Plan $M365Plan
            if (-not $addVersion) { $definition | Add-Member -NotePropertyName name -NotePropertyValue $M365Plan.Name -Force }
        }
        if ($null -ne $Snapshot) {
            if ($Snapshot.Item.DefinitionPath -ne $DefinitionPath -or
                [string]$Snapshot.Item.SourceVersion -ne $Version -or
                [string]$Snapshot.Item.NerdioAppId -ne [string]$ShellAppId) {
                throw 'Publish arguments do not match the confirmed snapshot.'
            }
            Assert-EwNerdioPublishSnapshot -Snapshot $Snapshot
        }
        if (-not $PackagePath) {
            $resolved = Resolve-EwNerdioSource -Source $definition.source
            if (-not $Version) { $Version = $resolved.Version }
            if ([string]::IsNullOrWhiteSpace($resolved.URI)) { throw 'The source did not resolve a download URI.' }
            if (-not $DownloadPath) {
                $DownloadPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "EvergreenWorkbench\Nerdio\$([guid]::NewGuid())"
            }
            $null = New-Item -Path $DownloadPath -ItemType Directory -Force -ErrorAction Stop
            $artifact = if ($null -ne $resolved.Artifact) { $resolved.Artifact } else {
                [PSCustomObject]@{ URI = $resolved.URI; Version = $resolved.Version }
            }
            $saved = @(Invoke-EwArtifactSave -Artifact $artifact -Path $DownloadPath)
            $PackagePath = [string]($saved | ForEach-Object {
                Get-EwFirstPropertyValue -InputObject $_ -Name 'FullName', 'Path'
            } | Select-Object -First 1)
        }
        if ([string]::IsNullOrWhiteSpace($Version) -or -not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
            throw 'Publishing requires a version and an existing package file.'
        }
        $result.Version = $Version
        if ($null -ne $Snapshot) { Assert-EwNerdioPublishSnapshot -Snapshot $Snapshot }
        if ($null -ne $M365Plan) {
            Assert-EwM365NerdioPublishPlan -Plan $M365Plan
            if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256 -ErrorAction Stop).Hash -cne $M365PackageHash) {
                throw 'The built Microsoft 365 package changed before upload.'
            }
        }
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled before upload.'
            return $result
        }
        $recoveryOperation = [ordered]@{
            Id = [guid]::NewGuid().ToString()
            Type = 'Publish'
            Status = 'InProgress'
            StartedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Destination = Get-EwNerdioDestinationIdentity -Context $context
            Name = [string](Get-EwFirstPropertyValue -InputObject $definition -Name 'name')
            Publisher = [string](Get-EwFirstPropertyValue -InputObject $definition -Name 'publisher')
            DefinitionPath = $DefinitionPath
            Operation = if ($addVersion) { 'Add version' } else { 'Create' }
            AppId = [string]$ShellAppId
            Version = $Version
            JobId = ''
            BlobName = [string]$result.BlobName
            Error = 'The provider write started but no final outcome was recorded.'
        }
        $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $recoveryOperation
        Write-Verbose -Message "EvergreenUI: Uploading Nerdio payload for version '$Version'"
        $package = Invoke-EwNerdioBlobUpload -Path $PackagePath -Context $context
        $blobName = Get-EwFirstPropertyValue -InputObject $package -Name 'BlobName'
        $result.BlobName = [string]$blobName
        $recoveryOperation.BlobName = $result.BlobName
        $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $recoveryOperation
        if ($CancellationToken.IsCancellationRequested) {
            $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $recoveryOperation.Id
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled after upload and before the Nerdio request.'
            return $result
        }
        if ($null -ne $Snapshot) { Assert-EwNerdioPublishSnapshot -Snapshot $Snapshot }
        if ($null -ne $M365Plan) {
            Assert-EwM365NerdioPublishPlan -Plan $M365Plan
            if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256 -ErrorAction Stop).Hash -cne $M365PackageHash) {
                throw 'The built Microsoft 365 package changed during upload.'
            }
        }
        if ($addVersion) {
            $result.AppId = $ShellAppId
            $body = [PSCustomObject]@{
                name = $Version; isPreview = $false; installScriptOverride = $null
                file = [PSCustomObject]@{ sourceUrl = $package.SourceUrl; sha256 = $package.Sha256 }
            }
            $uri = "https://$($context.NmeHost)/api/v1/shell-app/$([uri]::EscapeDataString($ShellAppId))/version"
        }
        else {
            $definition.versions[0].name = $Version
            $definition.versions[0].file.sourceUrl = $package.SourceUrl
            $definition.versions[0].file.sha256 = $package.Sha256
            if ([IO.Path]::GetExtension($PackagePath) -ieq '.zip') {
                $definition | Add-Member -NotePropertyName fileUnzip -NotePropertyValue $true -Force
            }
            if ($null -ne $definition.PSObject.Properties['source']) { $definition.PSObject.Properties.Remove('source') }
            $body = $definition
            $uri = "https://$($context.NmeHost)/api/v1/shell-app"
        }
        if ($CancellationToken.IsCancellationRequested) {
            $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $recoveryOperation.Id
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled after upload and before the Nerdio request.'
            return $result
        }
        $postStarted = $true
        $response = Invoke-EwNerdioApiRequest -Method POST -Uri $uri -AccessToken $context.AccessToken -Body $body
        $job = Get-EwFirstPropertyValue -InputObject $response -Name 'job'
        $result.JobId = [string](Get-EwFirstPropertyValue -InputObject $job -Name 'id')
        if (-not $addVersion) {
            $result.AppId = [string](Get-EwFirstPropertyValue -InputObject (Get-EwFirstPropertyValue -InputObject $response -Name 'item') -Name 'id')
        }
        $status = [string](Get-EwFirstPropertyValue -InputObject $job -Name 'status')
        $result.Status = switch ($status) {
            'Completed' { 'Completed' }
            'Pending' { 'Pending' }
            'Failed' { 'Failed' }
            default { 'Unknown' }
        }
        if ($result.Status -eq 'Completed' -and -not $result.AppId) { $result.Status = 'Unknown' }
        $result.Succeeded = $result.Status -eq 'Completed'
        if (-not $result.Succeeded) { $result.Error = "Nerdio returned '$status'; inspect the operation before retrying." }
        if ($result.Status -in @('Pending', 'Unknown')) {
            $recoveryOperation.Status = $result.Status
            $recoveryOperation.AppId = $result.AppId
            $recoveryOperation.JobId = $result.JobId
            $recoveryOperation.BlobName = $result.BlobName
            $recoveryOperation.Error = $result.Error
            $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $recoveryOperation
        }
        elseif ($result.Succeeded) {
            $offer = [ordered]@{
                Id = [guid]::NewGuid().ToString()
                Type = 'PruningOffer'
                CreatedAt = [DateTimeOffset]::UtcNow.ToString('o')
                Destination = $recoveryOperation.Destination
                AppId = $result.AppId
                Name = $recoveryOperation.Name
                Publisher = $recoveryOperation.Publisher
                DefinitionPath = $DefinitionPath
                PublishedVersion = $Version
            }
            $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $recoveryOperation.Id -UpsertOffer $offer
        }
        else {
            $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $recoveryOperation.Id
        }
        Write-Verbose -Message "EvergreenUI: Nerdio publish outcome '$($result.Status)', app '$($result.AppId)', job '$($result.JobId)'"
        return $result
    }
    catch {
        if ($postStarted -or $_.Exception.Data.Contains('OutcomeUnknown')) { $result.Status = 'Unknown' }
        if ($_.Exception.Data.Contains('BlobName')) { $result.BlobName = [string]$_.Exception.Data['BlobName'] }
        $message = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
        Write-Verbose -Message "EvergreenUI: Nerdio publish failed: $message"
        if ($null -ne $recoveryOperation) {
            if ($postStarted -or $_.Exception.Data.Contains('OutcomeUnknown')) {
                $recoveryOperation.Status = 'Unknown'
                $recoveryOperation.AppId = $result.AppId
                $recoveryOperation.JobId = $result.JobId
                $recoveryOperation.BlobName = $result.BlobName
                $recoveryOperation.Error = $message
                $null = Invoke-EwNerdioRecoveryStore -Action Update -UpsertOperation $recoveryOperation
            }
            else {
                $null = Invoke-EwNerdioRecoveryStore -Action Update -RemoveOperationId $recoveryOperation.Id
            }
        }
        return (& $fail -Message $message)
    }
}
