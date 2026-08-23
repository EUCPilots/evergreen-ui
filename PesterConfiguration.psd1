@{
    Run          = @{
        Path     = '.\tests'
        PassThru = $true
    }
    Filter       = @{
        ExcludeTag = @('Integration')
    }
    Output       = @{
        Verbosity = 'Detailed'
    }
    CodeCoverage = @{
        Enabled      = $true
        Path         = @(
            '.\EvergreenUI\Private\Get-FilterableProperties.ps1'
            '.\EvergreenUI\Private\Get-InstallPackageDefinitions.ps1'
            '.\EvergreenUI\Private\Get-IntunePackageLatestVersion.ps1'
            '.\EvergreenUI\Private\Get-UIConfig.ps1'
            '.\EvergreenUI\Private\Merge-ConfigSection.ps1'
            '.\EvergreenUI\Private\Set-UIConfig.ps1'
            '.\EvergreenUI\Private\Test-LocalPackageDetection.ps1'
        )
        OutputFormat = 'JaCoCo'
        OutputPath   = '.\coverage.xml'
        CoveragePercentTarget = 75
    }
}