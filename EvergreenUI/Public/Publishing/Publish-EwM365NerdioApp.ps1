Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwM365NerdioApp {
    <#
    .SYNOPSIS
        Builds and publishes one confirmed Microsoft 365 Nerdio package.
    .DESCRIPTION
        Rechecks a confirmed preview before and after building and at provider
        write boundaries. Preserves partial provider results and does not retry.
    .PARAMETER Plan
        Confirmed Get-EwM365NerdioPublishPlan result.
    .PARAMETER WorkingPath
        Root directory for staging and package output.
    .PARAMETER Force
        Replace an existing output package after explicit confirmation.
    .PARAMETER CancellationToken
        Cancellation checked between stages, not during provider requests.
    .EXAMPLE
        Publish-EwM365NerdioApp -Plan $plan -WorkingPath C:\Packages
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

    if (-not $PSCmdlet.ShouldProcess($Plan.Name, 'Build and publish Microsoft 365 Nerdio Shell App')) { return }
    $result = [PSCustomObject]@{
        Succeeded = $false; Status = 'Failed'; PackagePath = ''; Version = [string]$Plan.BuildPlan.OfficeVersion
        AppId = [string]$Plan.ShellAppId; JobId = ''; BlobName = ''; Error = ''
    }
    try {
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled before building.'
            return $result
        }
        Assert-EwM365NerdioPublishPlan -Plan $Plan
        $build = $Plan.BuildPlan
        $package = New-EwPackage -M365ConfigurationPath $build.ConfigurationPath -ConfigurationRoot $build.ConfigurationRoot `
            -WorkingPath $WorkingPath -Provider Nerdio -Channel $build.Channel -CompanyName $build.CompanyName `
            -ImportFor $build.ImportFor -TenantId $build.TenantId -AppJsonTemplatePath $build.AppJsonTemplatePath `
            -M365Plan $build -Force:$Force -Confirm:$false
        if (-not $package.Succeeded) { throw "Microsoft 365 package build failed: $($package.Error)" }
        $result.PackagePath = [string]$package.PackagePath
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Cancelled after building and before upload.'
            return $result
        }
        Assert-EwM365NerdioPublishPlan -Plan $Plan
        $packageHash = (Get-FileHash -LiteralPath $result.PackagePath -Algorithm SHA256 -ErrorAction Stop).Hash
        $parameters = @{
            DefinitionPath = Join-Path -Path $build.ConfigurationRoot -ChildPath 'shell-app'
            PackagePath = $result.PackagePath; Version = $result.Version; M365Plan = $Plan
            M365PackageHash = $packageHash; CancellationToken = $CancellationToken; Confirm = $false
        }
        if ($Plan.Operation -eq 'Add version') { $parameters.ShellAppId = $Plan.ShellAppId }
        $published = Publish-EwNerdioApp @parameters
        foreach ($name in 'Succeeded', 'Status', 'AppId', 'JobId', 'BlobName', 'Error') {
            $result.$name = $published.$name
        }
    }
    catch {
        $result.Error = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
        Write-Verbose -Message "EvergreenUI: Microsoft 365 Nerdio publishing stopped: $($result.Error)"
    }
    return $result
}
