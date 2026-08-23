#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Get-IntunePackageLatestVersion' -Tag 'Unit' {
    It 'Rejects an unsupported filter expression without executing it' {
        InModuleScope EvergreenUI {
            Mock -CommandName Invoke-Expression
            $definition = [PSCustomObject]@{
                Application = [PSCustomObject]@{ Filter = 'Get-Process' }
            }

            $result = Get-IntunePackageLatestVersion -DefinitionObject $definition

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Unsupported filter expression'
            Should -Invoke -CommandName Invoke-Expression -Times 0 -Exactly
        }
    }

    It 'Returns a structured failure when the filter is missing' {
        InModuleScope EvergreenUI {
            $definition = [PSCustomObject]@{
                Application = [PSCustomObject]@{ Filter = '' }
            }

            $result = Get-IntunePackageLatestVersion -DefinitionObject $definition

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'empty or missing'
        }
    }

    It 'Returns a structured failure when filter execution fails' {
        InModuleScope EvergreenUI {
            Mock -CommandName Invoke-Expression { throw 'catalog unavailable' }
            $definition = [PSCustomObject]@{
                Application = [PSCustomObject]@{ Filter = 'Get-EvergreenApp -Name Test' }
            }

            $result = Get-IntunePackageLatestVersion -DefinitionObject $definition

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'catalog unavailable'
        }
    }

    It 'Selects the highest version matching architecture and language preferences' {
        InModuleScope EvergreenUI {
            Mock -CommandName Invoke-Expression {
                @(
                    [PSCustomObject]@{ Version = '1.0.0'; Architecture = 'x64'; Language = 'en-US'; URI = 'https://example.com/1.exe' }
                    [PSCustomObject]@{ Version = '3.0.0'; Architecture = 'x86'; Language = 'en-US'; URI = 'https://example.com/3.exe' }
                    [PSCustomObject]@{ Version = '2.0.0'; Architecture = 'x64'; Language = 'en-US'; URI = 'https://example.com/2.exe' }
                    [PSCustomObject]@{ Version = '4.0.0'; Architecture = 'x64'; Language = 'fr-FR'; URI = 'https://example.com/4.exe' }
                )
            }
            $definition = [PSCustomObject]@{
                Application = [PSCustomObject]@{
                    Filter       = 'Get-EvergreenApp -Name Test'
                    Architecture = 'x64'
                    Language     = 'en-US'
                }
            }

            $result = Get-IntunePackageLatestVersion -DefinitionObject $definition

            $result.Succeeded | Should -BeTrue
            $result.Version | Should -Be '2.0.0'
            $result.URI | Should -Be 'https://example.com/2.exe'
        }
    }

    It 'Resolves supported alternate URI property names' {
        InModuleScope EvergreenUI {
            Mock -CommandName Invoke-Expression {
                [PSCustomObject]@{ Version = '1.0.0'; DownloadUrl = 'https://example.com/app.exe' }
            }
            $definition = [PSCustomObject]@{
                Application = [PSCustomObject]@{
                    Filter       = 'Get-VcList'
                    Architecture = ''
                    Language     = ''
                }
            }

            $result = Get-IntunePackageLatestVersion -DefinitionObject $definition

            $result.Succeeded | Should -BeTrue
            $result.URI | Should -Be 'https://example.com/app.exe'
        }
    }
}