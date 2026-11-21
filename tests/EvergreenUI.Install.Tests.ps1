#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Local package detection' {
    It 'passes existence rules and requires every configured rule to pass' {
        $presentFile = Join-Path -Path $TestDrive -ChildPath 'present.exe'
        Set-Content -LiteralPath $presentFile -Value 'test'
        $definition = [PSCustomObject]@{
            DetectionRule = @(
                [PSCustomObject]@{ Type = 'File'; Path = $presentFile; DetectionMethod = 'Existence' }
                [PSCustomObject]@{ Type = 'File'; Path = (Join-Path -Path $TestDrive -ChildPath 'missing.exe'); DetectionMethod = 'Existence' }
            )
        }
        $result = Test-EwDetection -DefinitionObject $definition
        $result.Succeeded | Should -BeTrue
        $result.Installed | Should -BeFalse
        $result.RuleCount | Should -Be 2
        $result.RulePassCount | Should -Be 1
    }

    It 'returns success with a clear status when no detection rules exist' {
        $result = Test-EwDetection -DefinitionObject ([PSCustomObject]@{ DetectionRule = @() })
        $result.Succeeded | Should -BeTrue
        $result.Installed | Should -BeFalse
        $result.Status | Should -Be 'No detection rules'
    }
}

Describe 'Local package installation' {
    BeforeEach {
        $script:installRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $script:installDefinitionPath = Join-Path -Path $installRoot -ChildPath 'Example\App.json'
        $definitionFolder = Split-Path -Path $installDefinitionPath -Parent
        New-Item -Path $definitionFolder -ItemType Directory -Force | Out-Null
        [PSCustomObject]@{
            Application = [PSCustomObject]@{ Name = 'Example'; Filter = 'Get-EvergreenApp -Name "ExampleApp"' }
            Information = [PSCustomObject]@{ DisplayName = 'Example app' }
            PackageInformation = [PSCustomObject]@{ SetupFile = 'old.exe'; Version = '1.0' }
            Program = [PSCustomObject]@{ InstallCommand = 'installer.exe /quiet' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $installDefinitionPath
    }

    It 'does not resolve, download, or execute when WhatIf is specified' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {}
            Mock Invoke-EwArtifactSave {}
            Mock Invoke-EwInstallerProcess {}
            Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Resolve-EwArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
            Should -Invoke Invoke-EwInstallerProcess -Exactly 0
        }
    }

    It 'stages the artifact and reports successful installer exit codes' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'installer.exe' }
            }
            Mock Invoke-EwInstallerProcess { [PSCustomObject]@{ ExitCode = 3010 } }
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.ExitCode | Should -Be 3010
            $result.DownloadedVersion | Should -Be '2.0'
            Should -Invoke Invoke-EwArtifactSave -Exactly 1
            Should -Invoke Invoke-EwInstallerProcess -Exactly 1 -ParameterFilter {
                $Command -eq 'installer.exe /quiet' -and [string]::IsNullOrWhiteSpace($ScriptPath)
            }
        }
    }
}
