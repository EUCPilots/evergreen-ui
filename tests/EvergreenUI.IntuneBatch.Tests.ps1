#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

Describe 'Definition-centric Intune comparison' {
    BeforeEach {
        $script:comparisonRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $script:comparisonRoot -ItemType Directory
        $script:comparisonPath = Join-Path -Path $script:comparisonRoot -ChildPath 'App.json'
        $script:guid = 'ad6e0b7c-37c9-4e96-9c3d-a4d9c6b046dc'
        $script:definition = [PSCustomObject]@{
            Information = @{ DisplayName = 'Example definition'; Publisher = 'Example publisher'; PSPackageFactoryGuid = $script:guid }
            Application = @{ Architecture = 'x64'; Filter = 'Get-EvergreenApp -Name Example' }
            RequirementRule = @{ Architecture = 'x64,arm64' }
            PackageInformation = @{ Version = '1.0'; SetupFile = 'setup.exe' }
            DetectionRule = @(@{ Type = 'File'; DetectionMethod = 'Version'; Path = 'C:\Example'; FileOrFolder = 'app.exe'; Operator = 'greaterThanOrEqual'; VersionValue = '1.0'; Check32BitOn64System = 'false' })
            CustomRequirementRule = @()
            Assignments = @(@{ Type = 'AllUsers'; Intent = 'available' })
        }
        $script:definition = $script:definition | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $script:definition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:comparisonPath
        Mock Resolve-EwArtifact {
            [PSCustomObject]@{ Succeeded = $true; Version = '2.0'; URI = 'https://example.test/app.exe'; ResolvedArtifact = [PSCustomObject]@{ Architecture = 'x64' }; Error = '' }
        } -ModuleName EvergreenUI
        $script:older = [PSCustomObject]@{
            IntuneAppId = 'old'; DisplayName = 'Example imported name'; DisplayVersion = '1.0'
            Publisher = 'Example publisher'; NotesValid = 'Yes'; NotesGuid = $script:guid; IsUpdateApp = $false
            AllowedArchitectures = 'x64'; SupersededAppIds = @()
        }
    }

    It 'retains the names and versions of the current and superseded apps in one definition row' {
        $current = $older.PSObject.Copy()
        $current.IntuneAppId = 'current'
        $current.DisplayName = 'Example latest'
        $current.DisplayVersion = '2.0'
        $current.SupersededAppIds = @('old')
        $rows = @(Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older, $current))
        $rows.Count | Should -Be 1
        $rows[0].Readiness | Should -Be 'Latest imported'
        $rows[0].IntuneAppId | Should -Be 'current'
        $rows[0].DefinitionVersion | Should -Be '1.0'
        $rows[0].AvailableVersion | Should -Be '2.0'
        $rows[0].MatchingApps.Count | Should -Be 2
        $rows[0].MatchingApps[0].Supersedes | Should -Match 'Example imported name.*1.0'
        $rows[0].MatchingApps[1].SupersededBy | Should -Match 'Example latest.*2.0'
        $rows[0].DeploymentBlocker | Should -Match 'already imported'
    }

    It 'indexes supersedence relationships instead of rescanning inventory for every matching app' {
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Guid = $guid } {
            $script:relationshipReads = 0
            $propertyReader = (Get-Command Get-EwObjectPropertyValue).ScriptBlock
            Mock Get-EwObjectPropertyValue {
                if ($Name -eq 'SupersededAppIds') { $script:relationshipReads++ }
                & $propertyReader -Object $Object -Name $Name -Default $Default
            }
            $inventory = @(1..100 | ForEach-Object {
                [PSCustomObject]@{
                    IntuneAppId = "app-$_"; DisplayName = "App $_"; DisplayVersion = '1.0'; Publisher = 'Publisher'
                    NotesValid = 'Yes'; NotesGuid = if ($_ -le 20) { $Guid } else { 'unrelated' }
                    IsUpdateApp = $false; AllowedArchitectures = 'x64'; SupersededAppIds = @()
                }
            })
            $rows = @(Compare-EwIntuneApp -DefinitionPath $Root -DefinitionView -IntuneApp $inventory)
            $rows[0].MatchingAppCount | Should -Be 20
            $script:relationshipReads | Should -BeLessOrEqual 140
        }
    }

    It 'matches update apps to the definition and distinguishes artifact from OS architecture' {
        $older.IsUpdateApp = $true
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $row.Readiness | Should -Be 'Update available'
        $row.MatchingApps[0].AppKind | Should -Be 'Update app'
        $row.Architecture | Should -Be 'x64'
        $row.RequirementArchitecture | Should -Be 'x64,arm64'
        $row.MatchingApps[0].AllowedArchitectures | Should -Be 'x64'
        $row.UpdateBlocker | Should -BeNullOrEmpty
    }

    It 'requires an explicit predecessor when matching apps are not linked' {
        $other = $older.PSObject.Copy()
        $other.IntuneAppId = 'other'
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older, $other)
        $row.Readiness | Should -Be 'Needs review'
        $row.IntuneAppId | Should -BeNullOrEmpty
        InModuleScope EvergreenUI -Parameters @{ Row = $row } {
            Set-EwIntuneComparisonTarget -Row $Row -AppId 'other'
            $Row.IntuneAppId | Should -Be 'other'
            $Row.DeploymentBlocker | Should -BeNullOrEmpty
            { Set-EwIntuneComparisonTarget -Row $Row -AppId 'unrelated' } | Should -Throw '*not a unique match*'
        }
    }

    It 'blocks missing versions and preserves unrelated inventory without name matching' {
        $older.NotesGuid = 'another-guid'
        $older.DisplayVersion = ''
        $rows = @(Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older))
        $rows[0].Readiness | Should -Be 'Not imported'
        $rows[0].UpdateBlocker | Should -Match 'No existing app'
        $rows[1].RowType | Should -Be 'Intune'
        $rows[1].IntuneVersion | Should -Be 'Version unavailable'
        $older.NotesGuid = $guid
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $row.Readiness | Should -Be 'Needs review'
        $row.DeploymentBlocker | Should -Match 'cannot be compared'
    }

    It 'blocks imports older than an existing Intune version' {
        $older.DisplayVersion = '3.0'
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $row.Readiness | Should -Be 'Newer version in Intune'
        $row.DeploymentBlocker | Should -Match 'Older imports are blocked'
    }

    It 'blocks unresolvable definitions without hiding the resolution error' {
        Mock Resolve-EwArtifact { [PSCustomObject]@{ Succeeded = $false; Error = 'No artifact matches'; Version = ''; URI = ''; ResolvedArtifact = $null } } -ModuleName EvergreenUI
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @()
        $row.Readiness | Should -Be 'Needs review'
        $row.DeploymentBlocker | Should -Match 'No artifact matches'
        $row.AvailableVersion | Should -Be 'Unavailable'
    }

    It 'adds independent existence checks even when custom requirements are configured' {
        InModuleScope EvergreenUI -Parameters @{ Definition = $definition } {
            $Definition.CustomRequirementRule = @([PSCustomObject]@{ Type = 'Script'; ScriptFile = 'custom.ps1' })
            $result = Get-EwIntuneUpdateRequirement -Definition $Definition
            $result.Succeeded | Should -BeTrue
            $result.Rules.Count | Should -Be 2
            $result.Rules[1].DetectionMethod | Should -Be 'Existence'
            $result.Rules[1].FileOrFolder | Should -Be 'app.exe'
            $Definition.DetectionRule = @([PSCustomObject]@{ Type = 'MSI'; ProductCode = '{example}' })
            (Get-EwIntuneUpdateRequirement -Definition $Definition).Succeeded | Should -BeFalse
        }
    }

    It 'rejects an unsafe update before any Graph write' {
        InModuleScope EvergreenUI -Parameters @{ Definition = $definition } {
            $Definition.DetectionRule = @([PSCustomObject]@{ Type = 'MSI' })
            Mock Invoke-MgGraphRequest {}
            $result = Invoke-EwIntuneGraphWin32Import -DefinitionObject $Definition -IntuneWinPath 'not-used.intunewin' -SetupFilePath 'setup.exe' -DownloadedVersion '2.0' -PSPackageFactoryGuid 'guid' -ImportAsUpdate -SyncHash @{}
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'MSI-only'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }
    }

    It 'pins the version during publishing and does not upload a different built version' {
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Assert-EwIntunePublishPlan {}
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'package.intunewin'; Version = '3.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp {}
            Mock Invoke-MgGraphRequest {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'confirmed import version'
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }

    It 'requires fresh confirmation when a reviewed version changes' {
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row } {
            $changed = $Item.PSObject.Copy()
            $changed.AvailableVersion = '3.0'
            Mock Compare-EwIntuneApp { $changed }
            { Assert-EwIntunePublishPlan -DefinitionPath $Root -Item $Item } | Should -Throw '*AvailableVersion*'
            $review = Get-EwIntunePublishReview -DefinitionPath $Root -Selection @($Item) -ImportAsUpdate $false
            $review.Changed | Should -BeTrue
            $review.Items[0].AvailableVersion | Should -Be '3.0'
            Should -Invoke Compare-EwIntuneApp -Exactly 2 -ParameterFilter { $DefinitionView -and $NoCache }
        }
    }

    It 'refreshes only selected artifacts during <Stage> without querying unrelated definitions' -ForEach @(
        @{ Stage = 'Review' }
        @{ Stage = 'BeforeBuild' }
        @{ Stage = 'AfterBuild' }
    ) {
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $otherFolder = Join-Path -Path $comparisonRoot -ChildPath 'Unselected'
        $null = New-Item -Path $otherFolder -ItemType Directory
        $otherPath = Join-Path -Path $otherFolder -ChildPath 'App.json'
        $otherDefinition = $definition | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $otherDefinition.Information.PSPackageFactoryGuid = [guid]::NewGuid().ToString()
        $otherDefinition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $otherPath
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row; App = $older; Stage = $Stage; OtherPath = $otherPath } {
            Mock Get-EwIntuneApp { @($App) }
            if ($Stage -eq 'Review') {
                $review = Get-EwIntunePublishReview -DefinitionPath $Root -Selection @($Item) -ImportAsUpdate $false
                $review.Items.Count | Should -Be 1
            }
            else {
                Assert-EwIntunePublishPlan -DefinitionPath $Root -Item $Item -AfterBuild:($Stage -eq 'AfterBuild')
            }
            Should -Invoke Resolve-EwArtifact -Exactly 0 -ParameterFilter { $DefinitionPath -eq $OtherPath }
            Should -Invoke Resolve-EwArtifact -Exactly 1 -ParameterFilter { $DefinitionPath -eq $Item.DefinitionPath -and $NoCache }
        }
    }

    It 'retains root-wide duplicate GUID protection when refreshing selected definitions' {
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $duplicateFolder = Join-Path -Path $comparisonRoot -ChildPath 'Duplicate'
        $null = New-Item -Path $duplicateFolder -ItemType Directory
        $definition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path -Path $duplicateFolder -ChildPath 'App.json')
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row; App = $older } {
            Mock Get-EwIntuneApp { @($App) }
            { Get-EwIntunePublishReview -DefinitionPath $Root -Selection @($Item) -ImportAsUpdate $false } | Should -Throw '*Multiple local definitions share this GUID*'
            { Assert-EwIntunePublishPlan -DefinitionPath $Root -Item $Item } | Should -Throw '*changed*'
            Should -Invoke Resolve-EwArtifact -Exactly 0 -ParameterFilter { $NoCache }
        }
    }

    It 'refreshes every selected definition in a batch and rejects files removed from the root' {
        $secondFolder = Join-Path -Path $comparisonRoot -ChildPath 'Second'
        $null = New-Item -Path $secondFolder -ItemType Directory
        $secondPath = Join-Path -Path $secondFolder -ChildPath 'App.json'
        $secondDefinition = $definition | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $secondDefinition.Information.PSPackageFactoryGuid = [guid]::NewGuid().ToString()
        $secondDefinition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $secondPath
        $selection = @(Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older))
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Items = $selection; App = $older } {
            Mock Get-EwIntuneApp { @($App) }
            $review = Get-EwIntunePublishReview -DefinitionPath $Root -Selection $Items -ImportAsUpdate $false
            $review.Items.Count | Should -Be 2
            @($review.Items | Where-Object IsSelected -EQ $true).Count | Should -Be 2
            Should -Invoke Resolve-EwArtifact -Exactly 2 -ParameterFilter { $NoCache }
            $missing = $Items[0].PSObject.Copy()
            $missing.DefinitionPath = Join-Path -Path $Root -ChildPath 'Missing\App.json'
            { Get-EwIntunePublishReview -DefinitionPath $Root -Selection @($missing) -ImportAsUpdate $false } | Should -Throw '*no longer a unique definition*'
        }
    }

    It 'reviews the newly verified current app instead of retaining a superseded predecessor' {
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $current = $older.PSObject.Copy()
        $current.IntuneAppId = 'current'
        $current.DisplayVersion = '1.5'
        $current.SupersededAppIds = @('old')
        $fresh = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older, $current)
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row; Fresh = $fresh } {
            Mock Compare-EwIntuneApp { $Fresh }
            $review = Get-EwIntunePublishReview -DefinitionPath $Root -Selection @($Item) -ImportAsUpdate $false
            $review.Changed | Should -BeTrue
            $review.Items[0].IntuneAppId | Should -Be 'current'
            { Assert-EwIntunePublishPlan -DefinitionPath $Root -Item $Item } | Should -Throw '*changed*'
        }
    }

    It 'blocks a definition edited while its available artifact is resolving' {
        Mock Resolve-EwArtifact {
            $changedDefinition = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json
            $changedDefinition.Information.DisplayName = 'Changed definition'
            $changedDefinition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DefinitionPath
            [PSCustomObject]@{ Succeeded = $true; Version = '2.0'; URI = 'https://example.test/app.exe'; ResolvedArtifact = [PSCustomObject]@{ Architecture = 'x64' }; Error = '' }
        } -ModuleName EvergreenUI
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        $row.Readiness | Should -Be 'Needs review'
        $row.DeploymentBlocker | Should -Match 'changed while comparing'
        $row.UpdateBlocker | Should -Match 'changed while comparing'
    }

    It 'does not upload a definition edited during the final publishing review' {
        $older.DisplayVersion = '0.9'
        Mock Resolve-EwArtifact {
            [PSCustomObject]@{ Succeeded = $true; Version = '1.0'; URI = 'https://example.test/app.exe'; ResolvedArtifact = [PSCustomObject]@{ Architecture = 'x64' }; Error = '' }
        } -ModuleName EvergreenUI
        $row = Compare-EwIntuneApp -DefinitionPath $comparisonRoot -DefinitionView -IntuneApp @($older)
        InModuleScope EvergreenUI -Parameters @{ Root = $comparisonRoot; Item = $row } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Assert-EwIntunePublishPlan {
                if ($AfterBuild) {
                    $changedDefinition = Get-Content -LiteralPath $Item.DefinitionPath -Raw | ConvertFrom-Json
                    $changedDefinition.Information.DisplayName = 'Changed after build'
                    $changedDefinition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Item.DefinitionPath
                }
            }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp {}
            Mock Invoke-MgGraphRequest {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Definition files changed'
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Intune batch publishing' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $directory = Join-Path -Path $script:root -ChildPath 'Example'
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
        $script:definitionPath = Join-Path -Path $directory -ChildPath 'App.json'
        [PSCustomObject]@{ PackageInformation = @{ Version = '1.0'; SetupFile = 'setup.exe' } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:definitionPath
        $script:selection = [PSCustomObject]@{
            DefinitionName = 'Example'
            DefinitionPath = $script:definitionPath
            MatchStatus = 'Matched (update required)'
            IntuneAppId = 'old-id'
            IntuneVersion = '0.9'
            DefinitionVersion = '1.0'
            PSPackageFactoryGuid = 'guid'
            DefinitionHash = (Get-FileHash -LiteralPath $script:definitionPath).Hash
            InstallHash = ''
            ImportAsUpdate = $false
        }
        Mock Invoke-MgGraphRequest {} -ModuleName EvergreenUI
    }

    It 'publishes a matching package and supersedes the confirmed app' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-id'; Error = '' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $true; Error = '' } }
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.IntuneAppId | Should -Be 'new-id'
            Should -Invoke Publish-EwIntuneApp -Exactly 1 -ParameterFilter { $Version -eq '1.0' -and $SetupFile -eq 'setup.exe' }
            Should -Invoke Set-EwIntuneSupersedence -Exactly 1 -ParameterFilter { $NewAppId -eq 'new-id' -and $PreviousAppId -eq 'old-id' }
        }
    }

    It 'does not build or write when WhatIf is used' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock New-EwPackage {}
            Mock Publish-EwIntuneApp {}
            Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -WhatIf
            Should -Invoke New-EwPackage -Exactly 0
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }

    It 'skips a changed Intune match before building' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { @() }
            Mock New-EwPackage {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'match changed'
            Should -Invoke New-EwPackage -Exactly 0
        }
    }

    It 'retains both app IDs when supersedence fails' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-id'; Error = '' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $false; Error = 'link failed' } }
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Status | Should -Be 'Supersedence failed'
            $result.IntuneAppId | Should -Be 'new-id'
            $result.PreviousAppId | Should -Be 'old-id'
        }
    }

    It 'updates and rebuilds before publishing a newer artifact' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '2.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Update-EwDefinition {
                [PSCustomObject]@{ PackageInformation = @{ Version = '2.0'; SetupFile = 'setup.exe' } } |
                    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $DefinitionPath
                [PSCustomObject]@{ Succeeded = $true; ChangedPaths = @($DefinitionPath); Error = '' }
            }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-id'; Error = '' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $true; Error = '' } }
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.ChangedPaths | Should -Contain $Item.DefinitionPath
            Should -Invoke New-EwPackage -Exactly 2
            Should -Invoke Publish-EwIntuneApp -Exactly 1 -ParameterFilter { $Version -eq '2.0' }
        }
    }

    It 'does not publish if the rebuilt package still differs from the updated definition' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '2.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Update-EwDefinition {
                [PSCustomObject]@{ PackageInformation = @{ Version = '3.0'; SetupFile = 'setup.exe' } } |
                    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $DefinitionPath
                [PSCustomObject]@{ Succeeded = $true; ChangedPaths = @($DefinitionPath); Error = '' }
            }
            Mock Publish-EwIntuneApp {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'does not match'
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }

    It 'reports changed files and does not publish when definition update fails' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '2.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Update-EwDefinition { [PSCustomObject]@{ Succeeded = $false; ChangedPaths = @($DefinitionPath); Error = 'Install.json failed' } }
            Mock Publish-EwIntuneApp {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Install.json failed'
            $result.ChangedPaths | Should -Contain $Item.DefinitionPath
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }

    It 'preserves a partial app ID when publishing fails' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Item }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $false; IntuneAppId = 'partial-id'; Error = 'upload failed' } }
            Mock Set-EwIntuneSupersedence {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.IntuneAppId | Should -Be 'partial-id'
            Should -Invoke Set-EwIntuneSupersedence -Exactly 0
        }
    }

    It 'continues to the next Definition after an item fails' {
        $secondDirectory = Join-Path -Path $root -ChildPath 'Second'
        New-Item -Path $secondDirectory -ItemType Directory -Force | Out-Null
        $secondPath = Join-Path -Path $secondDirectory -ChildPath 'App.json'
        Copy-Item -LiteralPath $definitionPath -Destination $secondPath
        $second = $selection.PSObject.Copy()
        $second.DefinitionName = 'Second'
        $second.DefinitionPath = $secondPath
        $second.IntuneAppId = 'second-old'
        $second.PSPackageFactoryGuid = 'second-guid'
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Items = @($selection, $second) } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Items }
            Mock New-EwPackage {
                if ($DefinitionPath -eq $Items[0].DefinitionPath) {
                    return [PSCustomObject]@{ Succeeded = $false; Error = 'build failed' }
                }
                [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' }
            }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-id'; Error = '' } }
            Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $true; Error = '' } }
            $results = @(Publish-EwIntuneBatch -DefinitionPath $Root -Selection $Items -WorkingPath $Root -TenantId 'tenant' -Confirm:$false)
            $results.Count | Should -Be 2
            $results[0].Succeeded | Should -BeFalse
            $results[1].Succeeded | Should -BeTrue
            Should -Invoke Publish-EwIntuneApp -Exactly 1
        }
    }

    It 'stops further items when Intune access is lost after a publish failure' {
        $secondDirectory = Join-Path -Path $root -ChildPath 'Second'
        New-Item -Path $secondDirectory -ItemType Directory -Force | Out-Null
        $secondPath = Join-Path -Path $secondDirectory -ChildPath 'App.json'
        Copy-Item -LiteralPath $definitionPath -Destination $secondPath
        $second = $selection.PSObject.Copy()
        $second.DefinitionPath = $secondPath
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Items = @($selection, $second) } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { $Items }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp { [PSCustomObject]@{ Succeeded = $false; IntuneAppId = 'partial-id'; Error = 'Unauthorized' } }
            Mock Invoke-MgGraphRequest { throw 'Unauthorized' }
            $results = @(Publish-EwIntuneBatch -DefinitionPath $Root -Selection $Items -WorkingPath $Root -TenantId 'tenant' -Confirm:$false)
            $results[0].IntuneAppId | Should -Be 'partial-id'
            $results[0].Error | Should -Match 'Intune access could not be verified'
            $results[1].Status | Should -Be 'Not started'
            Should -Invoke New-EwPackage -Exactly 1
            Should -Invoke Publish-EwIntuneApp -Exactly 1
        }
    }

    It 'stops between items when cancellation is requested during publishing' {
        $secondDirectory = Join-Path -Path $root -ChildPath 'Second'
        New-Item -Path $secondDirectory -ItemType Directory -Force | Out-Null
        $secondPath = Join-Path -Path $secondDirectory -ChildPath 'App.json'
        Copy-Item -LiteralPath $definitionPath -Destination $secondPath
        $second = $selection.PSObject.Copy()
        $second.DefinitionPath = $secondPath
        $second.IntuneAppId = 'second-old'
        $second.PSPackageFactoryGuid = 'second-guid'
        $source = [System.Threading.CancellationTokenSource]::new()
        try {
            InModuleScope EvergreenUI -Parameters @{ Root = $root; Items = @($selection, $second); Source = $source } {
                Mock Assert-EwModule {}
                Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
                Mock Compare-EwIntuneApp { $Items }
                Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
                Mock Publish-EwIntuneApp {
                    $Source.Cancel()
                    [PSCustomObject]@{ Succeeded = $true; IntuneAppId = 'new-id'; Error = '' }
                }
                Mock Set-EwIntuneSupersedence { [PSCustomObject]@{ Succeeded = $true; Error = '' } }
                $results = @(Publish-EwIntuneBatch -DefinitionPath $Root -Selection $Items -WorkingPath $Root -TenantId 'tenant' -CancellationToken $Source.Token -Confirm:$false)
                $results.Count | Should -Be 2
                $results[0].Succeeded | Should -BeTrue
                $results[1].Status | Should -Be 'Cancelled'
                Should -Invoke Set-EwIntuneSupersedence -Exactly 1
                Should -Invoke New-EwPackage -Exactly 1
            }
        }
        finally {
            $source.Dispose()
        }
    }

    It 'does not publish if the match changes during the build' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            $script:comparisonCalls = 0
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp {
                $script:comparisonCalls++
                if ($script:comparisonCalls -eq 1) { return $Item }
                $changed = $Item.PSObject.Copy()
                $changed.IntuneAppId = 'different-id'
                $changed
            }
            Mock New-EwPackage { [PSCustomObject]@{ Succeeded = $true; PackagePath = 'C:\package.intunewin'; Version = '1.0'; SetupFile = 'setup.exe'; Error = '' } }
            Mock Publish-EwIntuneApp {}
            $result = Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'match changed during the build'
            Should -Invoke Publish-EwIntuneApp -Exactly 0
        }
    }

    It 'does not start items after cooperative cancellation' {
        InModuleScope EvergreenUI -Parameters @{ Root = $root; Item = $selection } {
            $source = [System.Threading.CancellationTokenSource]::new()
            try {
                $source.Cancel()
                Mock Assert-EwModule {}
                Mock New-EwPackage {}
                $results = @(Publish-EwIntuneBatch -DefinitionPath $Root -Selection @($Item) -WorkingPath $Root -TenantId 'tenant' -CancellationToken $source.Token -Confirm:$false)
                $results.Count | Should -Be 1
                $results[0].Status | Should -Be 'Cancelled'
                Should -Invoke New-EwPackage -Exactly 0
            }
            finally {
                $source.Dispose()
            }
        }
    }
}
