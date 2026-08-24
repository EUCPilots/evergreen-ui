#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Get-InstallPackageDefinitions' -Tag 'Unit' {
    It 'Returns an error when the definitions root does not exist' {
        InModuleScope EvergreenUI {
            $result = Get-InstallPackageDefinitions -DefinitionsRoot (Join-Path -Path $env:TEMP -ChildPath "Missing_$(Get-Random)")

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'not found'
        }
    }

    It 'Returns an empty successful result when no definitions exist' {
        InModuleScope EvergreenUI {
            $root = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_EmptyDefinitions_$(Get-Random)"
            try {
                New-Item -Path $root -ItemType Directory -Force | Out-Null

                $result = Get-InstallPackageDefinitions -DefinitionsRoot $root

                $result.Succeeded | Should -BeTrue
                $result.Rows | Should -HaveCount 0
            }
            finally {
                Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Loads recursively and sorts definitions by publisher then name' {
        InModuleScope EvergreenUI {
            $root = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_Definitions_$(Get-Random)"
            try {
                $zetaPath = Join-Path -Path $root -ChildPath 'Zeta'
                $alphaPath = Join-Path -Path $root -ChildPath 'Nested\Alpha'
                New-Item -Path $zetaPath -ItemType Directory -Force | Out-Null
                New-Item -Path $alphaPath -ItemType Directory -Force | Out-Null
                @{
                    Application        = @{ Name = 'ZetaApp' }
                    Information        = @{ DisplayName = 'Zeta App'; Publisher = 'Zeta Co'; PSPackageFactoryGuid = '84e9f119-ff50-4c99-9d07-3504ee2dcbfa' }
                    PackageInformation = @{ Version = '2.0.0' }
                } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $zetaPath -ChildPath 'App.json') -Encoding UTF8
                @{
                    Application        = @{ Name = 'AlphaApp' }
                    Information        = @{ DisplayName = 'Alpha App'; Publisher = 'Alpha Co'; PSPackageFactoryGuid = 'd46685ae-df20-46ee-8a3b-c753029ae29f' }
                    PackageInformation = @{ Version = '1.0.0' }
                } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path -Path $alphaPath -ChildPath 'App.json') -Encoding UTF8

                $result = Get-InstallPackageDefinitions -DefinitionsRoot $root

                $result.Succeeded | Should -BeTrue
                $result.Rows.Name | Should -Be @('Alpha App', 'Zeta App')
                $result.Rows.Status | Should -Be @('Valid', 'Valid')
                $result.Rows.Version | Should -Be @('1.0.0', '2.0.0')
            }
            finally {
                Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Keeps malformed and missing GUID definitions as invalid rows' {
        InModuleScope EvergreenUI {
            $root = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_InvalidDefinitions_$(Get-Random)"
            try {
                $malformedPath = Join-Path -Path $root -ChildPath 'Malformed'
                $missingGuidPath = Join-Path -Path $root -ChildPath 'MissingGuid'
                New-Item -Path $malformedPath -ItemType Directory -Force | Out-Null
                New-Item -Path $missingGuidPath -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path -Path $malformedPath -ChildPath 'App.json') -Value '{invalid' -Encoding UTF8
                @{
                    Application        = @{ Name = 'NoGuid' }
                    Information        = @{ DisplayName = 'No Guid'; Publisher = 'Contoso'; PSPackageFactoryGuid = '' }
                    PackageInformation = @{ Version = '' }
                } |
                    ConvertTo-Json -Depth 4 |
                    Set-Content -Path (Join-Path -Path $missingGuidPath -ChildPath 'App.json') -Encoding UTF8

                $result = Get-InstallPackageDefinitions -DefinitionsRoot $root

                $result.Succeeded | Should -BeTrue
                $result.Rows | Should -HaveCount 2
                $result.Rows.Status | Should -Contain 'Invalid JSON'
                $result.Rows.Status | Should -Contain 'Missing PSPackageFactoryGuid'
            }
            finally {
                Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}