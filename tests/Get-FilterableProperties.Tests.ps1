#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Get-FilterableProperties' -Tag 'Unit' {
    It 'Returns filterable properties excluding display-only columns' {
        InModuleScope EvergreenUI {
            $data = @(
                [PSCustomObject]@{ Version = '145.0.0'; Channel = 'Stable'; Architecture = 'x64'; Type = 'msi'; URI = 'https://example.com/x64.msi'; Date = '2026-03-01'; Sha = 'abc'; Sha1 = 'abc1'; Sha256 = 'abc256'; Hash = 'h1' }
                [PSCustomObject]@{ Version = '145.0.0'; Channel = 'Beta'; Architecture = 'x86'; Type = 'msi'; URI = 'https://example.com/x86.msi'; Date = '2026-03-01'; Sha = 'def'; Sha1 = 'def1'; Sha256 = 'def256'; Hash = 'h2' }
            )

            $result = Get-FilterableProperties -AppResults $data

            $result.Name | Should -Contain 'Architecture'
            $result.Name | Should -Contain 'Channel'
            $result.Name | Should -Contain 'Type'
            foreach ($excludedName in @('Version', 'URI', 'Date', 'Sha', 'Sha1', 'Sha256', 'Hash')) {
                $result.Name | Should -Not -Contain $excludedName
            }
        }
    }

    It 'Assigns CheckBoxStrip when a property has no more than six unique values' {
        InModuleScope EvergreenUI {
            $data = @(
                [PSCustomObject]@{ Version = '1.0'; Architecture = 'x64'; URI = 'https://example.com/x64.msi' }
                [PSCustomObject]@{ Version = '1.0'; Architecture = 'x86'; URI = 'https://example.com/x86.msi' }
            )

            $property = Get-FilterableProperties -AppResults $data |
                Where-Object { $_.Name -eq 'Architecture' }

            $property.ControlType | Should -Be 'CheckBoxStrip'
        }
    }

    It 'Returns an empty array for empty input' {
        InModuleScope EvergreenUI {
            Get-FilterableProperties -AppResults @() | Should -HaveCount 0
        }
    }

    It 'Creates a synthetic file type property when Type is absent' {
        InModuleScope EvergreenUI {
            $data = @(
                [PSCustomObject]@{ Version = '1.0.0'; URI = 'https://example.com/app.exe' }
                [PSCustomObject]@{ Version = '1.0.0'; URI = 'https://example.com/app.msi' }
            )

            $synthetic = Get-FilterableProperties -AppResults $data |
                Where-Object { $_.IsSynthetic -eq $true }

            $synthetic | Should -Not -BeNullOrEmpty
            $synthetic.DisplayName | Should -BeLike '*derived*'
        }
    }
}