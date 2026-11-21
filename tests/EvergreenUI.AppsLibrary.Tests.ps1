#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Evergreen application catalog' {
    BeforeEach {
        InModuleScope EvergreenUI {
            $script:ewAppCatalogCache = @{ RetrievedAt = $null; Items = @() }
        }
    }

    It 'caches normalized catalog results and refreshes on Force' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwAppCatalogQuery {
                @(
                    [PSCustomObject]@{ Name = 'Zulu'; Application = 'Zulu App'; Link = 'https://example.test/zulu' }
                    [PSCustomObject]@{ Name = 'Alpha' }
                )
            }
            $first = Get-EwApp
            $cached = Get-EwApp
            $refreshed = Get-EwApp -Force
            $first.Name | Should -Be @('Alpha', 'Zulu')
            $first[0].FriendlyName | Should -Be 'Alpha'
            $first[1].FriendlyName | Should -Be 'Zulu App'
            $cached.Count | Should -Be 2
            $refreshed.Count | Should -Be 2
            Should -Invoke Invoke-EwAppCatalogQuery -Exactly 2
        }
    }

    It 'resolves artifacts and applies exact multi-value filters' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion {
                @(
                    [PSCustomObject]@{ Version = '1'; Architecture = 'x64'; Type = 'msi'; URI = 'https://example.test/a.msi' }
                    [PSCustomObject]@{ Version = '1'; Architecture = 'x86'; Type = 'exe'; URI = 'https://example.test/b.exe' }
                    [PSCustomObject]@{ Version = '2'; Architecture = 'arm64'; Type = 'msi'; URI = 'https://example.test/c.msi' }
                )
            }
            $result = Get-EwApp -Name Example -Filter @{ Architecture = @('x64', 'arm64'); Type = 'msi' }
            $result.Version | Should -Be @('1', '2')
            Should -Invoke Get-EwAppVersion -Exactly 1 -ParameterFilter { $Name -eq 'Example' }
        }
    }

    It 'filters derived file types when Evergreen has no Type property' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion {
                @(
                    [PSCustomObject]@{ Version = '1'; URI = 'https://example.test/a.msi' }
                    [PSCustomObject]@{ Version = '1'; URI = 'https://example.test/b.exe' }
                )
            }
            (Get-EwApp -Name Example -Filter @{ _DerivedType = 'exe' }).URI | Should -Be 'https://example.test/b.exe'
        }
    }

    It 'rejects unknown filter properties and returns an empty result without matching versions' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion {
                [PSCustomObject]@{ Version = '1'; Architecture = 'x64' }
            }
            { Get-EwApp -Name Example -Filter @{ Channel = 'Stable' } } | Should -Throw '*not available*'
            @(Get-EwApp -Name Example -Filter @{ Architecture = 'arm64' }).Count | Should -Be 0
        }
    }
}

Describe 'Artifact filter metadata' {
    It 'excludes display fields and identifies a synthetic extension filter' {
        $artifacts = @(
            [PSCustomObject]@{ Version = '1'; URI = 'https://example.test/a.msi'; Architecture = 'x64'; Language = 'en-US' }
            [PSCustomObject]@{ Version = '2'; URI = 'https://example.test/b.exe'; Architecture = 'x86'; Language = 'fr-FR' }
        )
        $properties = Get-EwFilterableProperty -Artifact $artifacts
        $properties.Name | Should -Contain 'Architecture'
        $properties.Name | Should -Contain '_DerivedType'
        $properties.Name | Should -Not -Contain 'Version'
        $properties.Name | Should -Not -Contain 'URI'
        ($properties | Where-Object Name -eq 'Language').ControlType | Should -Be 'ComboBox'
        ($properties | Where-Object Name -eq '_DerivedType').UniqueValues | Should -Be @('exe', 'msi')
    }

    It 'selects control type from value cardinality and handles empty data' {
        $small = @(1..6 | ForEach-Object { [PSCustomObject]@{ Architecture = "arch$_" } })
        $medium = @(1..7 | ForEach-Object { [PSCustomObject]@{ Architecture = "arch$_" } })
        $large = @(1..21 | ForEach-Object { [PSCustomObject]@{ Architecture = "arch$_" } })
        (Get-EwFilterableProperty -Artifact $small).ControlType | Should -Be 'CheckBoxStrip'
        (Get-EwFilterableProperty -Artifact $medium).ControlType | Should -Be 'MultiListBox'
        (Get-EwFilterableProperty -Artifact $large).ControlType | Should -Be 'TextBox'
        @(Get-EwFilterableProperty -Artifact @()).Count | Should -Be 0
    }
}

Describe 'Artifact download' {
    BeforeEach {
        $script:downloadRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        New-Item -Path $downloadRoot -ItemType Directory -Force | Out-Null
    }

    It 'saves a resolved artifact and returns path metadata' {
        InModuleScope EvergreenUI -Parameters @{ DownloadRoot = $downloadRoot } {
            Mock Invoke-EwArtifactSave {
                [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'setup.msi' }
            }
            $artifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.msi' }
            $result = Save-EwArtifact -AppName Example -Artifact $artifact -Path $DownloadRoot -Force -VerifyChecksum
            $result.AppName | Should -Be 'Example'
            $result.Version | Should -Be '2.0'
            $result.Path | Should -Be (Join-Path -Path $DownloadRoot -ChildPath 'Example\setup.msi')
            Should -Invoke Invoke-EwArtifactSave -Exactly 1 -ParameterFilter {
                $Force -and $VerifyChecksum -and $Path -eq (Join-Path -Path $DownloadRoot -ChildPath 'Example')
            }
        }
    }

    It 'does not invoke Evergreen under WhatIf' {
        InModuleScope EvergreenUI -Parameters @{ DownloadRoot = $downloadRoot } {
            Mock Invoke-EwArtifactSave {}
            $artifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.msi' }
            Save-EwArtifact -AppName Example -Artifact $artifact -Path $DownloadRoot -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
    }

    It 'rejects unsafe app folder names and artifacts without URIs' {
        InModuleScope EvergreenUI -Parameters @{ DownloadRoot = $downloadRoot } {
            $artifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.msi' }
            { Save-EwArtifact -AppName '..' -Artifact $artifact -Path $DownloadRoot } | Should -Throw '*folder name*'
            { Save-EwArtifact -AppName Example -Artifact ([PSCustomObject]@{ Version = '2.0' }) -Path $DownloadRoot } | Should -Throw '*URI*'
        }
    }
}

Describe 'Evergreen library' {
    BeforeEach {
        $script:libraryPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        New-Item -Path $libraryPath -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $libraryPath -ChildPath 'EvergreenLibrary.json') -Value '{}'
    }

    It 'returns one record per inventoried application' {
        InModuleScope EvergreenUI -Parameters @{ LibraryPath = $libraryPath } {
            Mock Get-EwLibraryInventory {
                [PSCustomObject]@{
                    Inventory = @(
                        [PSCustomObject]@{ ApplicationName = 'Example'; Versions = @('1', '2') }
                        [PSCustomObject]@{ Name = 'Other'; Versions = @('1') }
                    )
                }
            }
            $result = @(Get-EwLibrary -Path $LibraryPath)
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'Example'
            $result[0].VersionCount | Should -Be 2
            $result[1].Path | Should -Be (Join-Path -Path $LibraryPath -ChildPath 'Other')
        }
    }

    It 'requires an initialized library and surfaces missing inventory names' {
        { Get-EwLibrary -Path $TestDrive } | Should -Throw '*manifest*'
        InModuleScope EvergreenUI -Parameters @{ LibraryPath = $libraryPath } {
            Mock Get-EwLibraryInventory { [PSCustomObject]@{ Inventory = @([PSCustomObject]@{ Versions = @() }) } }
            { Get-EwLibrary -Path $LibraryPath } | Should -Throw '*no ApplicationName or Name*'
        }
    }

    It 'updates the library and returns a structured outcome' {
        InModuleScope EvergreenUI -Parameters @{ LibraryPath = $libraryPath } {
            Mock Invoke-EwLibraryUpdate { 'updated' }
            $result = Update-EwLibrary -Path $LibraryPath
            $result.Succeeded | Should -BeTrue
            $result.Path | Should -Be $LibraryPath
            $result.Output | Should -Be 'updated'
            Should -Invoke Invoke-EwLibraryUpdate -Exactly 1 -ParameterFilter { $Path -eq $LibraryPath }
        }
    }

    It 'does not update under WhatIf and surfaces update failures' {
        InModuleScope EvergreenUI -Parameters @{ LibraryPath = $libraryPath } {
            Mock Invoke-EwLibraryUpdate { throw 'library update failed' }
            Update-EwLibrary -Path $LibraryPath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-EwLibraryUpdate -Exactly 0
            { Update-EwLibrary -Path $LibraryPath -Confirm:$false } | Should -Throw '*library update failed*'
        }
    }
}
