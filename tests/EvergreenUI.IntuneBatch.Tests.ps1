#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
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
