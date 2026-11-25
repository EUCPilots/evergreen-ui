Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwIntunePackageBuilder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFolder,

        [Parameter(Mandatory)]
        [string]$SetupFile,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    Assert-EwModule -Name IntuneWin32App
    $packageResult = New-IntuneWin32AppPackage -SourceFolder $SourceFolder `
        -SetupFile $SetupFile -OutputFolder $OutputFolder -Force -ErrorAction Stop
    if ($packageResult -is [string] -and -not [string]::IsNullOrWhiteSpace($packageResult)) {
        return $packageResult
    }
    if ($null -ne $packageResult -and $null -ne $packageResult.PSObject.Properties['Path'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageResult.Path)) {
        return [string]$packageResult.Path
    }

    $package = Get-ChildItem -LiteralPath $OutputFolder -Filter '*.intunewin' -File -ErrorAction Stop |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $package) {
        throw "The IntuneWin32App module did not create an .intunewin file in '$OutputFolder'."
    }
    return $package.FullName
}
