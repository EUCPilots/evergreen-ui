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
        [psobject]$Snapshot
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
    if (-not $PSCmdlet.ShouldProcess($DefinitionPath, 'Upload and publish Nerdio Shell App')) { return }
    try {
        $context = Get-EwNerdioSessionContext
        $definition = Get-EwNerdioPublishContent -DefinitionPath $DefinitionPath -AddVersion:$addVersion
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
        Write-Verbose -Message "EvergreenUI: Uploading Nerdio payload for version '$Version'"
        $package = Invoke-EwNerdioBlobUpload -Path $PackagePath -Context $context
        $blobName = Get-EwFirstPropertyValue -InputObject $package -Name 'BlobName'
        $result.BlobName = [string]$blobName
        if ($null -ne $Snapshot) { Assert-EwNerdioPublishSnapshot -Snapshot $Snapshot }
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
        Write-Verbose -Message "EvergreenUI: Nerdio publish outcome '$($result.Status)', app '$($result.AppId)', job '$($result.JobId)'"
        return $result
    }
    catch {
        if ($postStarted -or $_.Exception.Data.Contains('OutcomeUnknown')) { $result.Status = 'Unknown' }
        if ($_.Exception.Data.Contains('BlobName')) { $result.BlobName = [string]$_.Exception.Data['BlobName'] }
        $message = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
        Write-Verbose -Message "EvergreenUI: Nerdio publish failed: $message"
        return (& $fail -Message $message)
    }
}
