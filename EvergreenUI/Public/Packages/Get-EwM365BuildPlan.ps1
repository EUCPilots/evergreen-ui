Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365BuildPlan {
    <#
    .SYNOPSIS
        Previews Microsoft 365 build inputs and provider identity.
    .DESCRIPTION
        Resolves the Office channel and deployment tool versions and records
        local file hashes for a subsequent confirmed build. This command does
        not download, build, or publish a package.
    .PARAMETER ConfigurationPath
        Office Deployment Tool XML file.
    .PARAMETER ConfigurationRoot
        Folder containing the uninstall configuration and Nerdio definition.
    .PARAMETER Provider
        Provider whose active session is used for the build.
    .PARAMETER Channel
        Office update channel.
    .PARAMETER CompanyName
        Company name to write into the staged configuration.
    .PARAMETER ImportFor
        Single-session or multi-session licensing.
    .PARAMETER TenantId
        Tenant ID, which must match the provider session.
    .PARAMETER AppJsonTemplatePath
        Optional App.json template.
    .EXAMPLE
        Get-EwM365BuildPlan -ConfigurationPath C:\M365\Install.xml -Provider Intune `
            -Channel Current -CompanyName Contoso -ImportFor 'Single session' -TenantId $tenantId
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [string]$ConfigurationRoot,
        [Parameter(Mandatory)][ValidateSet('Intune', 'Nerdio')][string]$Provider,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Channel,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CompanyName,
        [Parameter(Mandatory)][ValidateSet('Single session', 'Multi-session')][string]$ImportFor,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TenantId,
        [string]$AppJsonTemplatePath
    )

    $path = (Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Stop).Path
    if (-not $ConfigurationRoot) { $ConfigurationRoot = Split-Path -Path $path -Parent }
    $root = (Resolve-Path -LiteralPath $ConfigurationRoot -ErrorAction Stop).Path
    $initialHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    $configuration = Read-EwM365Configuration -Path $path
    $configurationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$configuration.ConfigId, [ref]$configurationId) -or
        $configurationId -eq [guid]::Empty) {
        throw 'The Microsoft 365 configuration must have a valid, non-empty configuration ID.'
    }
    [xml]$xml = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    if ($xml.SelectSingleNode('/Configuration/Add').HasAttribute('DownloadPath')) {
        throw 'A rolling channel cannot use DownloadPath because Office Deployment Tool requires a pinned version for that setting.'
    }
    if (-not $AppJsonTemplatePath) {
        $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $AppJsonTemplatePath = Join-Path -Path $moduleRoot -ChildPath 'Resources\m365-app.json'
    }
    $template = (Resolve-Path -LiteralPath $AppJsonTemplatePath -ErrorAction Stop).Path
    $templateHash = (Get-FileHash -LiteralPath $template -Algorithm SHA256 -ErrorAction Stop).Hash
    $templateContent = Get-Content -LiteralPath $template -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($Provider -eq 'Intune') {
        $rules = @((Get-EwFirstPropertyValue -InputObject $templateContent -Name 'DetectionRule') | Where-Object {
                (Get-EwFirstPropertyValue -InputObject $_ -Name 'ValueName') -eq 'VersionToReport'
            })
        if ($rules.Count -ne 1 -or (Get-EwFirstPropertyValue -InputObject $rules[0] -Name 'Type') -ne 'Registry') {
            throw 'The Intune template must contain exactly one registry VersionToReport detection rule.'
        }
    }
    $uninstall = Join-Path -Path $root -ChildPath 'Uninstall-Microsoft365Apps.xml'
    $uninstallHash = if (Test-Path -LiteralPath $uninstall -PathType Leaf) {
        (Get-FileHash -LiteralPath $uninstall -Algorithm SHA256 -ErrorAction Stop).Hash
    } else { '' }
    $shellHash = ''
    if ($Provider -eq 'Nerdio') {
        Assert-EwM365UninstallConfiguration -Path $uninstall
        $shellPath = Join-Path -Path $root -ChildPath 'shell-app'
        foreach ($name in 'Definition.json', 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
            if (-not (Test-Path -LiteralPath (Join-Path -Path $shellPath -ChildPath $name) -PathType Leaf)) {
                throw "Required Nerdio Shell App file '$name' is missing."
            }
        }
        $shellHash = Get-EwNerdioDefinitionHash -DefinitionPath $shellPath
        $null = Get-EwNerdioPublishContent -DefinitionPath $shellPath
        $context = Get-EwNerdioSessionContext
        if ([string]$context.TenantId -ine $TenantId) { throw 'The Nerdio session tenant does not match the requested tenant.' }
        $identity = "$($context.SessionId)|$($context.NmeHost)"
    }
    else {
        Assert-EwModule -Name Microsoft.Graph.Authentication
        $context = Get-MgContext -ErrorAction Stop
        if ($null -eq $context -or [string]$context.TenantId -ine $TenantId) {
            throw 'The Intune session tenant does not match the requested tenant.'
        }
        $identity = [string]$context.Account
        if ([string]::IsNullOrWhiteSpace($identity)) { throw 'The Intune session account could not be verified.' }
    }
    $office = Get-EwM365SetupArtifact -Channel $Channel
    $tool = Get-EwM365DeploymentArtifact
    $finalHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($initialHash -cne $finalHash) { throw 'The Microsoft 365 configuration changed during preview.' }
    if ($templateHash -cne (Get-FileHash -LiteralPath $template -Algorithm SHA256 -ErrorAction Stop).Hash) {
        throw 'The App.json template changed during preview.'
    }
    $finalUninstallHash = if (Test-Path -LiteralPath $uninstall -PathType Leaf) {
        (Get-FileHash -LiteralPath $uninstall -Algorithm SHA256 -ErrorAction Stop).Hash
    } else { '' }
    if ($uninstallHash -cne $finalUninstallHash) { throw 'The uninstall configuration changed during preview.' }
    if ($Provider -eq 'Nerdio' -and $shellHash -cne (Get-EwNerdioDefinitionHash -DefinitionPath $shellPath)) {
        throw 'The Nerdio Shell App definition changed during preview.'
    }
    [PSCustomObject]@{
        ConfigurationPath = $path; ConfigurationRoot = $root; ConfigurationId = $configurationId.ToString()
        ConfigurationHash = $finalHash
        UninstallHash = $uninstallHash
        ShellHash = $shellHash
        AppJsonTemplatePath = $template
        TemplateHash = $templateHash
        Provider = $Provider; Channel = $Channel; CompanyName = $CompanyName; ImportFor = $ImportFor
        TenantId = $TenantId; SessionIdentity = $identity
        OfficeVersion = [string]$office.Version
        OfficeURI = [string](Get-EwFirstPropertyValue -InputObject $office -Name 'URI')
        ToolVersion = [string]$tool.Version; ToolURI = [string]$tool.URI
    }
}
