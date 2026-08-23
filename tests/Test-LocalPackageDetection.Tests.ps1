#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Test-LocalPackageDetection' -Tag 'Unit' {
    It 'Reports no detection rules as a successful non-installed state' {
        InModuleScope EvergreenUI {
            $definition = [PSCustomObject]@{ DetectionRule = @() }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Succeeded | Should -BeTrue
            $result.Installed | Should -BeFalse
            $result.Status | Should -Be 'No detection rules'
        }
    }

    It 'Passes a file existence rule when the target exists' {
        InModuleScope EvergreenUI {
            Mock -CommandName Test-Path { $true }
            $definition = [PSCustomObject]@{
                DetectionRule = @(
                    [PSCustomObject]@{
                        Type            = 'File'
                        Path            = 'C:\Program Files\Contoso'
                        FileOrFolder    = 'app.exe'
                        DetectionMethod = 'Existence'
                        Operator        = ''
                        VersionValue    = ''
                    }
                )
            }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Succeeded | Should -BeTrue
            $result.Installed | Should -BeTrue
            $result.RulePassCount | Should -Be 1
        }
    }

    It 'Compares detected file versions using version operators' {
        InModuleScope EvergreenUI {
            Mock -CommandName Test-Path { $true }
            Mock -CommandName Get-Item {
                [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ FileVersion = '2.1.0' } }
            }
            $definition = [PSCustomObject]@{
                DetectionRule = @(
                    [PSCustomObject]@{
                        Type            = 'File'
                        Path            = 'C:\Program Files\Contoso'
                        FileOrFolder    = 'app.exe'
                        DetectionMethod = 'Version'
                        Operator        = 'GreaterThanOrEqual'
                        VersionValue    = '2.0.0'
                    }
                )
            }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Installed | Should -BeTrue
            $result.DetectedVersion | Should -Be '2.1.0'
        }
    }

    It 'Supports the legacy registry detection schema' {
        InModuleScope EvergreenUI {
            Mock -CommandName Test-Path { $true }
            Mock -CommandName Get-ItemProperty {
                [PSCustomObject]@{ DisplayVersion = '3.2.1' }
            }
            $definition = [PSCustomObject]@{
                DetectionRule = @(
                    [PSCustomObject]@{
                        Type                       = 'Registry'
                        KeyPath                    = 'HKEY_LOCAL_MACHINE\Software\Contoso'
                        Path                       = ''
                        ValueName                  = 'DisplayVersion'
                        DetectionMethod            = 'Version'
                        DetectionValue             = '3.0.0'
                        Value                      = ''
                        VersionValue               = ''
                        Operator                   = 'GreaterThan'
                        Check32BitOn64System        = 'false'
                    }
                )
            }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Installed | Should -BeTrue
            $result.DetectedVersion | Should -Be '3.2.1'
        }
    }

    It 'Supports current registry comparison names and values' {
        InModuleScope EvergreenUI {
            Mock -CommandName Test-Path { $true }
            Mock -CommandName Get-ItemProperty {
                [PSCustomObject]@{ Channel = 'Stable Enterprise' }
            }
            $definition = [PSCustomObject]@{
                DetectionRule = @(
                    [PSCustomObject]@{
                        Type                       = 'Registry'
                        KeyPath                    = ''
                        Path                       = 'HKCU\Software\Contoso'
                        ValueName                  = 'Channel'
                        DetectionMethod            = 'StringComparison'
                        DetectionValue             = ''
                        Value                      = 'enterprise'
                        VersionValue               = ''
                        Operator                   = 'Contains'
                        Check32BitOn64System        = 'false'
                    }
                )
            }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Installed | Should -BeTrue
        }
    }

    It 'Requires every detection rule to pass' {
        InModuleScope EvergreenUI {
            Mock -CommandName Test-Path {
                return $LiteralPath -like '*present.exe'
            }
            $definition = [PSCustomObject]@{
                DetectionRule = @(
                    [PSCustomObject]@{ Type = 'File'; Path = 'C:\Apps'; FileOrFolder = 'present.exe'; DetectionMethod = 'Existence'; Operator = ''; VersionValue = '' }
                    [PSCustomObject]@{ Type = 'File'; Path = 'C:\Apps'; FileOrFolder = 'missing.exe'; DetectionMethod = 'Existence'; Operator = ''; VersionValue = '' }
                )
            }

            $result = Test-LocalPackageDetection -DefinitionObject $definition

            $result.Succeeded | Should -BeTrue
            $result.Installed | Should -BeFalse
            $result.RuleCount | Should -Be 2
            $result.RulePassCount | Should -Be 1
        }
    }
}