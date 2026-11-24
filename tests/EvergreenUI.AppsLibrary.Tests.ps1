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

    Context 'Independent library removal' {
        BeforeEach {
            $script:removalRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $appPath = Join-Path -Path $removalRoot -ChildPath 'Example'
            $otherPath = Join-Path -Path $removalRoot -ChildPath 'Other'
            $null = New-Item -Path $appPath, $otherPath -ItemType Directory -Force
            @{
                Name = 'Test library'
                Applications = @(@{ Name = 'Example'; Filter = 'preserve me' }, @{ Name = 'Other' })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'EvergreenLibrary.json')
            $entries = @(
                @{ Version = '1'; Architecture = 'x64'; Type = 'msi'; Path = @('setup-x64.msi', 'shared.msi'); URI = 'https://example.test/x64' }
                @{ Version = '1'; Architecture = 'x86'; Type = 'msi'; Path = @('setup-x86.msi', 'shared.msi'); URI = 'https://example.test/x86' }
                @{ Version = '2'; Architecture = 'x64'; Type = 'exe'; Path = 'new.exe'; URI = 'https://example.test/new' }
            )
            ConvertTo-Json -InputObject $entries -Depth 10 |
                Set-Content -LiteralPath (Join-Path -Path $appPath -ChildPath 'Example.json')
            foreach ($file in 'setup-x64.msi', 'setup-x86.msi', 'shared.msi', 'new.exe', 'notes.txt') {
                Set-Content -LiteralPath (Join-Path -Path $appPath -ChildPath $file) -Value 'test content'
            }
            ConvertTo-Json -InputObject @(@{ Version = '9'; Path = 'keep.msi' }) |
                Set-Content -LiteralPath (Join-Path -Path $otherPath -ChildPath 'Other.json')
            Set-Content -LiteralPath (Join-Path -Path $otherPath -ChildPath 'keep.msi') -Value 'retained'
        }

        It 'removes only selected rows while preserving identical versions and shared files' {
            $app = Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0 -ExpectedManifestHash $app.ManifestHash -ExpectedLibraryHash $app.LibraryHash -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.RemovedCount | Should -Be 1
            $result.RemovedFiles | Should -HaveCount 1
            $updated = Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example
            $updated.SourceItem.Versions.Version | Should -Be @('1', '2')
            $updated.SourceItem.Versions[0].Architecture | Should -Be 'x86'
            Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi' | Should -Not -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\shared.msi' | Should -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\notes.txt' | Should -Exist
        }

        It 'removes nonadjacent rows and deduplicates selected indexes' {
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0, 2, 0 -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.RemovedCount | Should -Be 2
            $versions = (Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example).SourceItem.Versions
            $versions | Should -HaveCount 1
            $versions[0].Architecture | Should -Be 'x86'
            $json = Get-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'Example\Example.json') -Raw
            $json.TrimStart() | Should -Match '^\['
        }

        It 'allows removing all rows without unregistering the application' {
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0, 1, 2 -Confirm:$false
            $result.Succeeded | Should -BeTrue
            (Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example).VersionCount | Should -Be 0
            (Get-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'Example\Example.json') -Raw).Trim() | Should -Be '[]'
        }

        It 'unregisters the entire application and preserves other apps and unrecorded files' {
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.ApplicationRemoved | Should -BeTrue
            @(Get-EwLibrary -Path $removalRoot).Name | Should -Be 'Other'
            Join-Path -Path $removalRoot -ChildPath 'Example\Example.json' | Should -Not -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi' | Should -Not -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\notes.txt' | Should -Exist
            Join-Path -Path $removalRoot -ChildPath 'Other\keep.msi' | Should -Exist
            $library = Get-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'EvergreenLibrary.json') -Raw | ConvertFrom-Json
            $library.Name | Should -Be 'Test library'
        }

        It 'preserves installers referenced by another application' {
            $shared = Join-Path -Path $removalRoot -ChildPath 'Example\shared.msi'
            ConvertTo-Json -InputObject @(@{ Version = '9'; Path = $shared }) |
                Set-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'Other\Other.json')
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $shared | Should -Exist
        }

        It 'resolves relative library paths and uses the registered application casing' {
            Push-Location -LiteralPath $removalRoot
            try {
                $result = Remove-EwLibraryApp -Path '.' -Name eXaMpLe -Confirm:$false
                $result.Succeeded | Should -BeTrue
                $result.Name | Should -BeExactly 'Example'
                @(Get-EwLibrary -Path '.').Name | Should -Be 'Other'
            }
            finally { Pop-Location }
        }

        It 'removes empty recorded version directories without deleting unrelated content' {
            $versionPath = Join-Path -Path $removalRoot -ChildPath 'Example\1'
            $null = New-Item -Path $versionPath -ItemType Directory
            Move-Item -LiteralPath (Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi') -Destination $versionPath
            $manifestPath = Join-Path -Path $removalRoot -ChildPath 'Example\Example.json'
            $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $entries[0].Path = '1\setup-x64.msi'
            ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0 -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $versionPath | Should -Not -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\notes.txt' | Should -Exist
        }

        It 'rejects a changed <Manifest> snapshot without any removal' -ForEach @(
            @{ Manifest = 'Example\Example.json' }, @{ Manifest = 'EvergreenLibrary.json' }
        ) {
            $app = Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example
            Add-Content -LiteralPath (Join-Path -Path $removalRoot -ChildPath $Manifest) -Value ' '
            { Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0 -ExpectedManifestHash $app.ManifestHash -ExpectedLibraryHash $app.LibraryHash -Confirm:$false } |
                Should -Throw '*changed*'
            Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi' | Should -Exist
        }

        It 'does not change files or manifests under WhatIf and rejects invalid indexes' {
            $app = Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example
            Remove-EwLibraryApp -Path $removalRoot -Name Example -WhatIf | Should -BeNullOrEmpty
            (Get-EwLibrary -Path $removalRoot | Where-Object Name -EQ Example).ManifestHash | Should -Be $app.ManifestHash
            Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi' | Should -Exist
            { Remove-EwLibraryApp -Path $removalRoot -Name Example -Index -1 -Confirm:$false } | Should -Throw '*index*'
            { Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 3 -Confirm:$false } | Should -Throw '*index*'
            { Remove-EwLibraryApp -Path $removalRoot -Name '..' -Confirm:$false } | Should -Throw '*folder name*'
        }

        It 'rejects outside paths before removing any selected files' {
            $outside = Join-Path -Path $removalRoot -ChildPath 'outside.msi'
            Set-Content -LiteralPath $outside -Value 'must survive'
            $manifestPath = Join-Path -Path $removalRoot -ChildPath 'Example\Example.json'
            $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $entries[1].Path = '..\outside.msi'
            ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath
            $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0, 1 -Confirm:$false -WarningAction SilentlyContinue
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'outside'
            $result.ManifestUpdated | Should -BeFalse
            $outside | Should -Exist
            Join-Path -Path $removalRoot -ChildPath 'Example\setup-x64.msi' | Should -Exist
        }

        It 'rejects junction paths and leaves their targets untouched' {
            $outside = Join-Path -Path $removalRoot -ChildPath 'Other'
            $junction = Join-Path -Path $removalRoot -ChildPath 'Example\linked'
            $null = New-Item -Path $junction -ItemType Junction -Target $outside
            try {
                $manifestPath = Join-Path -Path $removalRoot -ChildPath 'Example\Example.json'
                $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $entries[0].Path = 'linked\keep.msi'
                ConvertTo-Json -InputObject $entries -Depth 10 | Set-Content -LiteralPath $manifestPath
                $result = Remove-EwLibraryApp -Path $removalRoot -Name Example -Index 0 -Confirm:$false -WarningAction SilentlyContinue
                $result.Succeeded | Should -BeFalse
                $result.Error | Should -Match 'reparse'
                Join-Path -Path $outside -ChildPath 'keep.msi' | Should -Exist
            }
            finally { Remove-Item -LiteralPath $junction -Force }
        }

        It 'stops at the first failed file and reports removed and unattempted files without retrying' {
            InModuleScope EvergreenUI -Parameters @{ Root = $removalRoot } {
                Mock Remove-Item {
                    if ($LiteralPath.EndsWith('setup-x86.msi')) { throw 'file is locked' }
                    [IO.File]::Delete($LiteralPath)
                }
                $result = Remove-EwLibraryApp -Path $Root -Name Example -Index 0, 1, 2 -Confirm:$false -WarningAction SilentlyContinue
                $result.Succeeded | Should -BeFalse
                $result.ManifestUpdated | Should -BeFalse
                $result.RemovedCount | Should -Be 0
                $result.RemovedFiles | Should -HaveCount 2
                $result.FailedFile | Should -Be (Join-Path -Path $Root -ChildPath 'Example\setup-x86.msi')
                $result.UnattemptedFiles | Should -Contain (Join-Path -Path $Root -ChildPath 'Example\new.exe')
                $result.Items.Status | Should -Be @('Files removed; entry retained', 'Failed; entry retained', 'Unattempted; entry retained')
                (Get-EwLibrary -Path $Root | Where-Object Name -EQ Example).VersionCount | Should -Be 3
                Should -Invoke Remove-Item -Exactly 1 -ParameterFilter { $LiteralPath.EndsWith('setup-x86.msi') }
                Should -Invoke Remove-Item -Exactly 0 -ParameterFilter { $LiteralPath.EndsWith('new.exe') }
            }
        }
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
