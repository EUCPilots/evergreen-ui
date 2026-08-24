#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Read-PackageDefinition' -Tag 'Unit' {
    BeforeEach {
        $definitionRoot = Join-Path -Path $TestDrive -ChildPath 'Package'
        Remove-Item -LiteralPath $definitionRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $definitionRoot -ItemType Directory -Force | Out-Null
    }

    It 'Returns a parsed definition when the baseline schema is valid' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Package\App.json'
        @{
            Application        = @{ Name = 'ContosoApp' }
            Information        = @{ DisplayName = 'Contoso App' }
            PackageInformation = @{ Version = '1.0.0' }
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $definitionPath -Encoding UTF8

        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $definitionPath } {
            $result = Read-PackageDefinition -Path $DefinitionPath

            $result.Succeeded | Should -BeTrue
            $result.Definition.Information.DisplayName | Should -Be 'Contoso App'
            $result.Error | Should -BeNullOrEmpty
        }
    }

    It 'Returns an error when the file does not exist' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Package\App.json'
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $definitionPath } {
            $result = Read-PackageDefinition -Path $DefinitionPath

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'not found'
        }
    }

    It 'Returns an error when the JSON is malformed' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Package\App.json'
        Set-Content -LiteralPath $definitionPath -Value '{invalid' -Encoding UTF8

        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $definitionPath } {
            $result = Read-PackageDefinition -Path $DefinitionPath

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Failed to parse'
        }
    }

    It 'Returns an error when the JSON root is not one object' {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Package\App.json'
        Set-Content -LiteralPath $definitionPath -Value '[{"Application":{}},{"Application":{}}]' -Encoding UTF8

        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $definitionPath } {
            $result = Read-PackageDefinition -Path $DefinitionPath

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'single JSON object'
        }
    }

    It 'Returns an error when required section <Section> is missing' -ForEach @(
        @{ Section = 'Application' }
        @{ Section = 'Information' }
        @{ Section = 'PackageInformation' }
    ) {
        $definitionPath = Join-Path -Path $TestDrive -ChildPath 'Package\App.json'
        $definition = @{
            Application        = @{ Name = 'ContosoApp' }
            Information        = @{ DisplayName = 'Contoso App' }
            PackageInformation = @{ Version = '1.0.0' }
        }
        $definition.Remove($Section)
        $definition | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $definitionPath -Encoding UTF8

        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $definitionPath; MissingSection = $Section } {
            $result = Read-PackageDefinition -Path $DefinitionPath

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match $MissingSection
        }
    }
}