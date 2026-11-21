#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Evergreen package builds' {
    BeforeEach {
        $script:packageRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $definitionDirectory = Join-Path -Path $packageRoot -ChildPath 'Example'
        New-Item -Path $definitionDirectory -ItemType Directory -Force | Out-Null
        $script:packageDefinition = Join-Path -Path $definitionDirectory -ChildPath 'App.json'
        [PSCustomObject]@{
            Application = [PSCustomObject]@{ Name = 'Example'; Filter = 'Get-EvergreenApp -Name "ExampleApp"' }
            PackageInformation = [PSCustomObject]@{ SetupFile = 'old.exe'; Version = '1.0' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $packageDefinition
    }

    It 'builds an Intune package using the optional package builder' {
        $workingPath = Join-Path -Path $packageRoot -ChildPath 'BuildOutput'
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $workingPath } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                Get-Item -LiteralPath $path
            }
            Mock Invoke-EwIntunePackageBuilder {
                $package = Join-Path -Path $OutputFolder -ChildPath 'Example.intunewin'
                Set-Content -LiteralPath $package -Value 'package'
                $package
            }
            $result = New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath
            $result.Succeeded | Should -BeTrue -Because $result.Error
            $result.SetupFile | Should -Be 'setup.exe'
            $result.Version | Should -Be '2.0'
            Test-Path -LiteralPath $result.PackagePath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install.ps1') -PathType Leaf | Should -BeTrue
            Should -Invoke Invoke-EwIntunePackageBuilder -Exactly 1 -ParameterFilter {
                $SetupFile -eq 'setup.exe' -and $SourceFolder -like '*\Example\Source'
            }
        }
    }

    It 'does not add the shared installer to PSADT packages' {
        $definitionSource = Join-Path -Path (Split-Path -Path $packageDefinition -Parent) -ChildPath 'Source'
        New-Item -Path $definitionSource -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $definitionSource -ChildPath 'Invoke-AppDeployToolkit.ps1') -Value 'param()'
        $workingPath = Join-Path -Path $packageRoot -ChildPath 'BuildOutput'
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $workingPath } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                Get-Item -LiteralPath $path
            }
            Mock Invoke-EwIntunePackageBuilder {
                $package = Join-Path -Path $OutputFolder -ChildPath 'Example.intunewin'
                Set-Content -LiteralPath $package -Value 'package'
                $package
            }
            $result = New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath
            $result.Succeeded | Should -BeTrue -Because $result.Error
            Test-Path -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install.ps1') -PathType Leaf | Should -BeFalse
        }
    }

    It 'does not resolve or create a package when WhatIf is specified' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $packageRoot } {
            Mock Resolve-EwArtifact {}
            Mock Invoke-EwArtifactSave {}
            Mock Invoke-EwIntunePackageBuilder {}
            New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Resolve-EwArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
            Should -Invoke Invoke-EwIntunePackageBuilder -Exactly 0
        }
    }

    It 'builds a Nerdio zip with updated ODT settings' {
        $configurationRoot = Join-Path -Path $packageRoot -ChildPath 'M365'
        New-Item -Path $configurationRoot -ItemType Directory -Force | Out-Null
        $xmlPath = Join-Path -Path $configurationRoot -ChildPath 'Install.xml'
        $uninstallPath = Join-Path -Path $configurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Old" OfficeClientEdition="64"><Product ID="O365ProPlusRetail"><ExcludeApp ID="Bing" /></Product></Add><Property Name="TenantId" Value="old" /><Property Name="SharedComputerLicensing" Value="0" /><AppSettings><Setup Value="Old" /></AppSettings></Configuration>'
        Set-Content -LiteralPath $uninstallPath -Value '<Configuration><Remove All="TRUE" /></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; ConfigurationRoot = $configurationRoot; WorkingPath = $packageRoot } {
            Mock Get-EwM365SetupArtifact {
                [PSCustomObject]@{ Channel = $Channel; Version = '16.0.1234.1'; URI = 'https://example.test/setup.exe' }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                Get-Item -LiteralPath $path
            }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -ConfigurationRoot $ConfigurationRoot `
                -WorkingPath $WorkingPath -Provider Nerdio -Channel MonthlyEnterprise -CompanyName Contoso `
                -ImportFor 'Multi-session' -TenantId 'tenant-id'
            $result.Succeeded | Should -BeTrue
            $result.Provider | Should -Be 'Nerdio'
            Test-Path -LiteralPath $result.PackagePath -PathType Leaf | Should -BeTrue
            [xml]$updated = Get-Content -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install-Microsoft365Apps.xml') -Raw
            $updated.Configuration.Add.Channel | Should -Be 'MonthlyEnterprise'
            ($updated.Configuration.Property | Where-Object Name -eq TenantId).Value | Should -Be 'tenant-id'
            ($updated.Configuration.Property | Where-Object Name -eq SharedComputerLicensing).Value | Should -Be '1'
            $updated.Configuration.AppSettings.Setup.Value | Should -Be 'Contoso'
            $appJson = Get-Content -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'App.json') -Raw | ConvertFrom-Json
            $appJson.Information.DisplayName | Should -Be 'Microsoft 365 Apps for enterprise: x64'
            $appJson.RequirementRule.Architecture | Should -Be 'x64'
            ($appJson.DetectionRule | Where-Object ValueName -eq ProductReleaseIds).Value | Should -Be 'O365ProPlusRetail'
            ($appJson.DetectionRule | Where-Object ValueName -eq SharedComputerLicensing).Value | Should -Be '1'
        }
    }
}
