Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwNerdioApp {
    <#
    .SYNOPSIS
        Publishes a Nerdio Manager Shell App or a new Shell App version.
    .DESCRIPTION
        Uploads a package to the configured Azure blob container. Without
        ShellAppId it creates a Shell App from Definition.json and its
        PowerShell scripts. With ShellAppId it adds a version to an existing
        Shell App. When PackagePath is omitted, the package is resolved from
        the Definition.json source and downloaded before upload.
    .PARAMETER DefinitionPath
        Directory containing Definition.json. Creating a Shell App also requires
        Detect.ps1, Install.ps1, and Uninstall.ps1.
    .PARAMETER ShellAppId
        Existing Shell App ID to add a version to.
    .PARAMETER PackagePath
        Package file to upload. Resolved from the definition source when omitted.
    .PARAMETER Version
        Version label. Defaults to the version resolved from the definition source.
    .PARAMETER DownloadPath
        Folder for downloaded source packages. Defaults to a temporary folder.
    .EXAMPLE
        Publish-EwNerdioApp -DefinitionPath .\ShellApp -PackagePath .\Packages\Microsoft365Apps.zip -Version 16.0.1
    .EXAMPLE
        Publish-EwNerdioApp -DefinitionPath .\ShellApps\GoogleChrome -ShellAppId 42
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio, Az.Storage, and Nerdio Manager API access.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Create')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter(Mandatory, ParameterSetName = 'AddVersion')]
        [ValidateNotNullOrEmpty()]
        [string]$ShellAppId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadPath
    )

    $addVersion = $PSCmdlet.ParameterSetName -eq 'AddVersion'
    $fail = {
        param([string]$Message)
        [PSCustomObject]@{ Succeeded = $false; AppId = ''; JobId = ''; Version = ''; Status = 'Failed'; Error = $Message }
    }
    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Container)) {
        return (& $fail "Shell App definition directory was not found: $DefinitionPath")
    }
    if ($PSBoundParameters.ContainsKey('PackagePath') -and -not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        return (& $fail "Shell App package was not found: $PackagePath")
    }
    $requiredFiles = if ($addVersion) { @('Definition.json') } else { @('Definition.json', 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') }
    foreach ($requiredFile in $requiredFiles) {
        $path = Join-Path -Path $DefinitionPath -ChildPath $requiredFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return (& $fail "Required Shell App file was not found: $path")
        }
    }
    $target = if ($addVersion) { "Shell App $ShellAppId" } else { $DefinitionPath }
    $action = if ($addVersion) { 'Add Shell App version in Nerdio Manager' } else { 'Publish Shell App to Nerdio Manager' }
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return
    }

    try {
        $context = Get-EwNerdioSessionContext
        $definitionFile = Join-Path -Path $DefinitionPath -ChildPath 'Definition.json'
        $definition = Get-Content -LiteralPath $definitionFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if (-not $PSBoundParameters.ContainsKey('PackagePath')) {
            $source = Get-EwFirstPropertyValue -InputObject $definition -Name 'source'
            if ($null -eq $source) {
                throw 'Definition.json has no source; supply PackagePath and Version.'
            }
            $resolved = Resolve-EwNerdioSource -Source $source
            if ([string]::IsNullOrWhiteSpace($resolved.URI)) {
                throw 'The definition source did not return a download URI.'
            }
            if (-not $PSBoundParameters.ContainsKey('Version')) {
                $Version = $resolved.Version
            }
            if (-not $PSBoundParameters.ContainsKey('DownloadPath')) {
                $DownloadPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "EvergreenWorkbench\Nerdio\$([guid]::NewGuid().ToString('N'))"
            }
            $null = New-Item -Path $DownloadPath -ItemType Directory -Force -ErrorAction Stop
            $artifact = if ($null -ne $resolved.Artifact) { $resolved.Artifact } else {
                [PSCustomObject]@{ Version = $resolved.Version; URI = $resolved.URI }
            }
            Write-Verbose -Message "EvergreenUI: Downloading Nerdio source package '$($resolved.URI)' to '$DownloadPath'"
            $saved = @(Invoke-EwArtifactSave -Artifact $artifact -Path $DownloadPath | Where-Object { $null -ne $_ })
            $file = $saved | ForEach-Object { Get-EwFirstPropertyValue -InputObject $_ -Name 'FullName', 'Path' } |
                Where-Object { $null -ne $_ } | Select-Object -First 1
            if ($null -eq $file -or -not (Test-Path -LiteralPath ([string]$file) -PathType Leaf)) {
                throw 'The source package download did not produce a file.'
            }
            $PackagePath = [string]$file
        }
        if ([string]::IsNullOrWhiteSpace($Version)) {
            throw 'A version could not be determined; supply Version.'
        }

        $package = Invoke-EwNerdioBlobUpload -Path $PackagePath -Context $context
        if ($addVersion) {
            $body = [PSCustomObject]@{
                name = $Version
                isPreview = $false
                installScriptOverride = $null
                file = [PSCustomObject]@{ sourceUrl = $package.SourceUrl; sha256 = $package.Sha256 }
            }
            $uri = "https://$($context.NmeHost)/api/v1/shell-app/$([uri]::EscapeDataString($ShellAppId))/version"
        }
        else {
            $versionEntries = @($definition.versions)
            if ($versionEntries.Count -eq 0) {
                throw 'Definition.json must contain at least one version entry.'
            }
            $versionEntries[0].name = $Version
            $versionEntries[0].file.sourceUrl = $package.SourceUrl
            $versionEntries[0].file.sha256 = $package.Sha256
            $definition.versions = $versionEntries
            if ([System.IO.Path]::GetExtension($PackagePath) -ieq '.zip') {
                $definition.fileUnzip = $true
            }
            foreach ($scriptName in @('detectScript', 'installScript', 'uninstallScript')) {
                $scriptFile = switch ($scriptName) {
                    'detectScript' { 'Detect.ps1' }
                    'installScript' { 'Install.ps1' }
                    'uninstallScript' { 'Uninstall.ps1' }
                }
                $definition | Add-Member -MemberType NoteProperty -Name $scriptName `
                    -Value (Get-Content -LiteralPath (Join-Path -Path $DefinitionPath -ChildPath $scriptFile) -Raw -ErrorAction Stop) -Force
            }
            if ($null -ne $definition.PSObject.Properties['source']) {
                $definition.PSObject.Properties.Remove('source')
            }
            $body = $definition
            $uri = "https://$($context.NmeHost)/api/v1/shell-app"
        }

        Write-Verbose -Message "EvergreenUI: Posting Nerdio Shell App request to '$uri' for version '$Version'"
        $response = Invoke-EwNerdioApiRequest -Method POST -Uri $uri -AccessToken $context.AccessToken -Body $body
        $jobStatus = [string]$response.job.status
        if ($jobStatus -ine 'Completed') {
            return (& $fail "Nerdio Manager returned job status '$jobStatus'.")
        }
        $appId = if ($addVersion) { $ShellAppId } else { [string](Get-EwFirstPropertyValue -InputObject (Get-EwFirstPropertyValue -InputObject $response -Name 'item') -Name 'id') }
        Write-Verbose -Message "EvergreenUI: Nerdio Shell App '$appId' version '$Version' published"
        [PSCustomObject]@{
            Succeeded = $true
            AppId = $appId
            JobId = [string]$response.job.id
            Version = $Version
            Status = $jobStatus
            Error = ''
        }
    }
    catch {
        return (& $fail "Nerdio publishing failed: $($_.Exception.Message)")
    }
}
