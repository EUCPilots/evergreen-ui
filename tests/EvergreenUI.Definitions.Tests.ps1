#Requires -Version 7.6

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Evergreen package definitions' {
    BeforeEach {
        $definitionRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $definitionDirectory = Join-Path -Path $definitionRoot -ChildPath 'Example'
        New-Item -Path $definitionDirectory -ItemType Directory -Force | Out-Null
        $script:definitionPath = Join-Path -Path $definitionDirectory -ChildPath 'App.json'
        $definition = [ordered]@{
            Application = @{
                Name = 'Example'
                Filter = 'Get-EvergreenApp -Name "ExampleApp" | Where-Object { $_.Type -eq "intunewin" } | Select-Object -First 1'
                Architecture = 'x64'
                Language = 'en-US'
            }
            PackageInformation = @{
                SetupFile = 'old.intunewin'
                Version = '1.0.0'
            }
            Information = @{
                DisplayName = 'Example package'
                Publisher = 'Example publisher'
                PSPackageFactoryGuid = '9fddd581-f505-4760-9bb3-2365db204b38'
            }
            DetectionRule = @(
                @{ Type = 'File'; DetectionMethod = 'Version'; VersionValue = '1.0.0' }
                @{ Type = 'Registry'; DetectionMethod = 'VersionComparison'; Value = '1.0.0' }
            )
        }
        $definition | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $definitionPath
    }

    It 'discovers and validates App.json definitions' {
        $rows = @(Get-EwDefinition -Path $definitionRoot)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'Example package'
        $rows[0].Publisher | Should -Be 'Example publisher'
        $rows[0].Status | Should -Be 'Valid'
        $rows[0].DefinitionObject.Application.Name | Should -Be 'Example'
    }

    It 'rejects filters containing executable commands or unsupported syntax' {
        InModuleScope EvergreenUI {
            {
                ConvertFrom-EwDefinitionFilter -Filter 'Get-EvergreenApp -Name "ExampleApp"; Remove-Item C:\temp'
            } | Should -Throw '*supported Evergreen query*'
            {
                ConvertFrom-EwDefinitionFilter -Filter 'Get-EvergreenApp -Name "ExampleApp" | Where-Object { Invoke-Expression "whoami" }'
            } | Should -Throw
            {
                ConvertFrom-EwDefinitionFilter -Filter 'Get-EvergreenApp -Name $(Get-Process)'
            } | Should -Throw '*literal -Name*'
        }
    }

    It 'resolves the highest matching artifact and caches by definition content' {
        InModuleScope EvergreenUI -Parameters @{ Definition = $definitionPath; Cache = $TestDrive } {
            Mock Get-EwAppVersion {
                @(
                    [PSCustomObject]@{ Type = 'intunewin'; Architecture = 'x64'; Language = 'en-US'; Version = '1.2.0'; URI = 'https://example.test/one.intunewin' }
                    [PSCustomObject]@{ Type = 'msi'; Architecture = 'x64'; Language = 'en-US'; Version = '9.0.0'; URI = 'https://example.test/wrong.msi' }
                    [PSCustomObject]@{ Type = 'intunewin'; Architecture = 'x64'; Language = 'en-US'; Version = '2.0.0'; URI = 'https://example.test/two.intunewin' }
                    [PSCustomObject]@{ Type = 'intunewin'; Architecture = 'x86'; Language = 'en-US'; Version = '3.0.0'; URI = 'https://example.test/wrong-arch.intunewin' }
                )
            }
            $first = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $second = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $first.Succeeded | Should -BeTrue
            $first.Version | Should -Be '2.0.0'
            $first.URI | Should -Be 'https://example.test/two.intunewin'
            $second.IsFromCache | Should -BeTrue
            Should -Invoke Get-EwAppVersion -Exactly 1 -ParameterFilter { $Name -eq 'ExampleApp' }

            $content = Get-Content -LiteralPath $Definition -Raw | ConvertFrom-Json
            $content.PackageInformation.Version = '2.1.0'
            $content | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Definition
            $third = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $third.IsFromCache | Should -BeFalse
            Should -Invoke Get-EwAppVersion -Exactly 2
        }
    }

    It 'updates package and version detection values and honors WhatIf' {
        InModuleScope EvergreenUI -Parameters @{ Definition = $definitionPath; Cache = $TestDrive } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0.0'
                    URI = 'https://example.test/updated%20setup.intunewin'
                    ResolvedArtifact = $null
                    Error = ''
                }
            }
            Update-EwDefinition -DefinitionPath $Definition -CachePath $Cache -WhatIf | Should -Not -BeNullOrEmpty
            $unchanged = Get-Content -LiteralPath $Definition -Raw | ConvertFrom-Json
            $unchanged.PackageInformation.Version | Should -Be '1.0.0'
            Should -Invoke Resolve-EwArtifact -Exactly 1

            $result = Update-EwDefinition -DefinitionPath $Definition -CachePath $Cache -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $updated = Get-Content -LiteralPath $Definition -Raw | ConvertFrom-Json
            $updated.PackageInformation.Version | Should -Be '2.0.0'
            $updated.PackageInformation.SetupFile | Should -Be 'updated setup.intunewin'
            $updated.DetectionRule[0].VersionValue | Should -Be '2.0.0'
            $updated.DetectionRule[1].Value | Should -Be '2.0.0'
        }
    }
}
