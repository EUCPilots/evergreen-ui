Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwNerdioApp {
    <#
    .SYNOPSIS
        Publishes a Nerdio Manager Shell App and package.
    .DESCRIPTION
        Uploads the package to the configured Azure blob container and creates
        a Nerdio Shell App using its Definition.json and PowerShell scripts.
    .PARAMETER DefinitionPath
        Directory containing Definition.json, Detect.ps1, Install.ps1, and Uninstall.ps1.
    .PARAMETER PackagePath
        Package file to upload to Azure Storage.
    .PARAMETER Version
        Version label to assign to the Shell App package.
    .EXAMPLE
        Publish-EwNerdioApp -DefinitionPath .\ShellApp -PackagePath .\Packages\Microsoft365Apps.zip -Version 16.0.1
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio, Az.Storage, and Nerdio Manager API access.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    $fail = {
        param([string]$Message)
        [PSCustomObject]@{ Succeeded = $false; AppId = ''; JobId = ''; Status = 'Failed'; Error = $Message }
    }
    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Container)) {
        return (& $fail "Shell App definition directory was not found: $DefinitionPath")
    }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        return (& $fail "Shell App package was not found: $PackagePath")
    }
    foreach ($requiredFile in @('Definition.json', 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1')) {
        $path = Join-Path -Path $DefinitionPath -ChildPath $requiredFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return (& $fail "Required Shell App file was not found: $path")
        }
    }
    if (-not $PSCmdlet.ShouldProcess($DefinitionPath, 'Publish Shell App to Nerdio Manager')) {
        return
    }

    try {
        $context = Get-EwNerdioSessionContext
        $definitionFile = Join-Path -Path $DefinitionPath -ChildPath 'Definition.json'
        $definition = Get-Content -LiteralPath $definitionFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $versionEntries = @($definition.versions)
        if ($versionEntries.Count -eq 0) {
            throw 'Definition.json must contain at least one version entry.'
        }
        $package = Invoke-EwNerdioBlobUpload -Path $PackagePath -Context $context
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
        $uri = "https://$($context.NmeHost)/api/v1/shell-app"
        $response = Invoke-EwNerdioApiRequest -Method POST -Uri $uri `
            -AccessToken $context.AccessToken -Body $definition
        $jobStatus = [string]$response.job.status
        if ($jobStatus -ine 'Completed') {
            return (& $fail "Nerdio Manager returned job status '$jobStatus'.")
        }
        [PSCustomObject]@{
            Succeeded = $true
            AppId = [string]$response.item.id
            JobId = [string]$response.job.id
            Status = $jobStatus
            Error = ''
        }
    }
    catch {
        return (& $fail "Nerdio publishing failed: $($_.Exception.Message)")
    }
}
