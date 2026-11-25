Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Expand-EwM365DeploymentTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$ExpectedVersion
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $actualVersion = [version]'0.0'
    $expected = [version]'0.0'
    if (-not [version]::TryParse([string]$file.VersionInfo.FileVersion, [ref]$actualVersion) -or
        -not [version]::TryParse($ExpectedVersion, [ref]$expected) -or $actualVersion -ne $expected) {
        throw 'The downloaded Office Deployment Tool version does not match the resolved artifact.'
    }
    $signature = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Microsoft Corporation') {
        throw 'The downloaded Office Deployment Tool does not have a valid Microsoft signature.'
    }
    $null = New-Item -Path $Destination -ItemType Directory -ErrorAction Stop
    Write-Verbose -Message "EvergreenUI: Extracting verified Office Deployment Tool version '$ExpectedVersion'"
    $archiveTool = Join-Path -Path $env:SystemRoot -ChildPath 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $archiveTool -PathType Leaf)) {
        throw 'Windows tar.exe is required to extract the Office Deployment Tool.'
    }
    $PSNativeCommandUseErrorActionPreference = $false
    $output = @(& $archiveTool -xf $file.FullName -C $Destination 'setup.exe' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Office Deployment Tool extraction failed with exit code $($LASTEXITCODE): $($output -join ' ')"
    }
    $setup = Join-Path -Path $Destination -ChildPath 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        throw 'The Office Deployment Tool artifact did not contain setup.exe.'
    }
    $setupSignature = Get-AuthenticodeSignature -FilePath $setup -ErrorAction Stop
    if ($setupSignature.Status -ne 'Valid' -or $null -eq $setupSignature.SignerCertificate -or
        $setupSignature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Microsoft Corporation') {
        throw 'The extracted Office Deployment Tool setup.exe does not have a valid Microsoft signature.'
    }
    return $setup
}
