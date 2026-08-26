#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Test-EvergreenUIPrerequisite' -Tag 'Unit' {
    It 'Reports required and optional dependencies without importing them' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-Module -MockWith {
                param($Name)
                if ($Name -eq 'Evergreen') {
                    [PSCustomObject]@{ Name = 'Evergreen'; Version = [version]'2603.2832.0' }
                }
            }

            $result = Test-EvergreenUIPrerequisite

            $result.Succeeded | Should -BeTrue
            $result.Required[0].Name | Should -Be 'Evergreen'
            $result.Required[0].Satisfied | Should -BeTrue
            $result.Optional | Should -HaveCount 5
            $result.MissingOptional | Should -HaveCount 5
            ($result.Messages -join "`n") | Should -Match 'Microsoft\.Graph\.Authentication' -Because 'optional dependency guidance should be actionable'
        }
    }

    It 'Fails when the required module is missing or below minimum version' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-Module -MockWith { $null }

            $result = Test-EvergreenUIPrerequisite

            $result.Succeeded | Should -BeFalse
            $result.MissingRequired.Name | Should -Be 'Evergreen'
            $result.Messages[0] | Should -Match 'Install-Module -Name Evergreen'
        }
    }
}