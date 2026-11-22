Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwIntuneApp {
    <#
    .SYNOPSIS
        Publishes an Intune Win32 app package through Microsoft Graph.
    .DESCRIPTION
        Creates the Win32 app, uploads the encrypted Intune package, commits
        its content version, and applies the assignments in App.json.
    .PARAMETER DefinitionPath
        Path to the App.json definition.
    .PARAMETER PackagePath
        Intune .intunewin package created by New-EwPackage.
    .PARAMETER Version
        Version packaged into the .intunewin. Defaults to App.json version.
    .PARAMETER SetupFile
        Setup file used when the package was built. Defaults to App.json.
    .PARAMETER ImportAsUpdate
        Imports the package using update-app naming and requirement behavior.
    .PARAMETER M365Plan
        Confirmed Microsoft 365 Intune publishing preview.
    .PARAMETER M365PackageHash
        SHA256 hash of the built package.
    .PARAMETER M365DefinitionHash
        SHA256 hash of the staged App.json.
    .PARAMETER CancellationToken
        Optional cancellation checked between publishing stages.
    .EXAMPLE
        Publish-EwIntuneApp -DefinitionPath .\App.json -PackagePath .\Output\App.intunewin
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Microsoft.Graph.Authentication and an active Connect-EwIntune session.
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

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$SetupFile,

        [Parameter()]
        [switch]$ImportAsUpdate,

        [Parameter()]
        [psobject]$M365Plan,

        [Parameter()]
        [string]$M365PackageHash,

        [Parameter()]
        [string]$M365DefinitionHash,

        [Parameter()]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    $fail = {
        param([string]$Message)
        [PSCustomObject]@{
            Succeeded = $false; IntuneAppId = ''; DisplayName = ''; Error = $Message
            Cancelled = $CancellationToken.IsCancellationRequested; WriteStarted = $false
        }
    }
    if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
        return (& $fail "Definition file was not found: $DefinitionPath")
    }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        return (& $fail "Intune package was not found: $PackagePath")
    }
    try {
        $definition = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Version = [string]$definition.PackageInformation.Version
        }
        if ([string]::IsNullOrWhiteSpace($SetupFile)) {
            $SetupFile = [string]$definition.PackageInformation.SetupFile
        }
        if ($null -ne $M365Plan -and ($ImportAsUpdate -or
                $Version -cne [string]$M365Plan.BuildPlan.OfficeVersion -or
                [string]::IsNullOrWhiteSpace($M365PackageHash) -or [string]::IsNullOrWhiteSpace($M365DefinitionHash))) {
            throw 'Intune publish arguments do not match the confirmed Microsoft 365 preview.'
        }
        if (-not $PSCmdlet.ShouldProcess([string]$definition.Information.DisplayName, 'Publish Win32 app to Intune')) {
            return
        }
        Assert-EwModule -Name Microsoft.Graph.Authentication
        if ($null -eq (Get-MgContext -ErrorAction Stop)) {
            return (& $fail 'No active Microsoft Graph context. Call Connect-EwIntune first.')
        }
        return Invoke-EwIntuneGraphWin32Import -DefinitionObject $definition `
            -DefinitionPath $DefinitionPath -IntuneWinPath $PackagePath -SetupFilePath $SetupFile `
            -DownloadedVersion $Version -PSPackageFactoryGuid ([string]$definition.Information.PSPackageFactoryGuid) `
            -ImportAsUpdate:$ImportAsUpdate -SyncHash @{} -M365Plan $M365Plan `
            -M365PackageHash $M365PackageHash -M365DefinitionHash $M365DefinitionHash -CancellationToken $CancellationToken
    }
    catch {
        return (& $fail "Intune publishing failed: $($_.Exception.Message)")
    }
}
