#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Favourite applications' {
    BeforeEach {
        $originalAppData = $env:APPDATA
        $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
        InModuleScope EvergreenUI {
            $script:ewAppCatalogCache = @{ RetrievedAt = $null; Items = @() }
        }
    }

    AfterEach {
        $env:APPDATA = $originalAppData
    }

    It 'adds favourites without case-insensitive duplicates and lists them first' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwAppCatalogQuery {
                @(
                    [PSCustomObject]@{ Name = 'Alpha' }
                    [PSCustomObject]@{ Name = 'Zulu' }
                )
            }
            $null = Add-EwFavouriteApp -Name 'Zulu'
            $favourites = @(Add-EwFavouriteApp -Name 'zulu', 'Mike')
            $favourites | Should -Be @('Zulu', 'Mike')
            $apps = @(Get-EwApp)
            $apps.Name | Should -Be @('Zulu', 'Alpha')
            $apps[0].IsFavourite | Should -BeTrue
            $apps[1].IsFavourite | Should -BeFalse
        }
    }

    It 'removes favourites and leaves settings untouched under WhatIf' {
        $null = Add-EwFavouriteApp -Name 'Alpha', 'Zulu'
        Remove-EwFavouriteApp -Name 'ALPHA' -WhatIf | Should -Be @('Alpha', 'Zulu')
        @(Remove-EwFavouriteApp -Name 'ALPHA') | Should -Be @('Zulu')
        @((Get-EwSetting).FavouriteApps) | Should -Be @('Zulu')
    }

    It 'validates the Microsoft 365 import target' {
        { Set-EwSetting -Name M365ImportFor -Value 'Everyone' } | Should -Throw
        Set-EwSetting -Name M365ImportFor -Value 'Multi-session'
        (Get-EwSetting).M365ImportFor | Should -Be 'Multi-session'
    }
}

Describe 'Dependencies' {
    It 'reports missing, outdated, and installed modules' {
        InModuleScope EvergreenUI {
            Mock Get-Module -ParameterFilter { $ListAvailable } {
                switch ($Name) {
                    'Evergreen' { [PSCustomObject]@{ Name = 'Evergreen'; Version = [version]'2501.1.0' } }
                    'Az.Accounts' { [PSCustomObject]@{ Name = 'Az.Accounts'; Version = [version]'5.0.0' } }
                }
            }
            $dependencies = @(Get-EwDependency)
            ($dependencies | Where-Object Name -EQ 'Evergreen').Status | Should -Be 'Update required'
            ($dependencies | Where-Object Name -EQ 'Evergreen').Required | Should -BeTrue
            ($dependencies | Where-Object Name -EQ 'Az.Accounts').Status | Should -Be 'Installed'
            ($dependencies | Where-Object Name -EQ 'Az.Storage').Status | Should -Be 'Not installed'
        }
    }

    It 'surfaces dependency discovery errors instead of reporting missing modules' {
        InModuleScope EvergreenUI {
            Mock Get-Module -ParameterFilter { $ListAvailable } {
                Write-Error -Message 'module discovery failed'
            }
            { @(Get-EwDependency) } | Should -Throw '*module discovery failed*'
        }
    }

    It 'selects the highest installed dependency version' {
        InModuleScope EvergreenUI {
            Mock Get-Module -ParameterFilter { $ListAvailable } {
                if ($Name -eq 'Az.Storage') {
                    [PSCustomObject]@{ Name = 'Az.Storage'; Version = [version]'3.0' }
                    [PSCustomObject]@{ Name = 'Az.Storage'; Version = [version]'10.0' }
                }
            }
            $dependency = Get-EwDependency | Where-Object Name -EQ 'Az.Storage'
            $dependency.InstalledVersion | Should -Be '10.0'
            $dependency.Status | Should -Be 'Installed'
        }
    }

    It 'updates Evergreen and clears the catalog and application version caches' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwEvergreenUpdate {}
            Mock Invoke-EwAppVersionCache { [PSCustomObject]@{ Epoch = 'e'; RemovedCount = 0; Errors = [string[]]@() } }
            $script:ewAppCatalogCache = @{ RetrievedAt = [DateTimeOffset]::UtcNow; Items = @([PSCustomObject]@{ Name = 'Alpha' }) }
            Update-EwEvergreen -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-EwEvergreenUpdate -Exactly 0
            (Update-EwEvergreen -Confirm:$false).Succeeded | Should -BeTrue
            @($script:ewAppCatalogCache.Items).Count | Should -Be 0
            $script:ewAppCatalogCache.RetrievedAt | Should -BeNullOrEmpty
            Should -Invoke Invoke-EwAppVersionCache -Exactly 1 -ParameterFilter { $Action -eq 'Clear' }
        }
    }
}

Describe 'Microsoft 365 configurations' {
    It 'reports configuration status and skips the uninstall configuration' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'M365'
        $null = New-Item -Path $folder -ItemType Directory -Force
        $add = '<Add OfficeClientEdition="64" Channel="MonthlyEnterprise"><Product ID="O365ProPlusRetail"><ExcludeApp ID="Groove" /></Product></Add>'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'A.xml') -Value "<Configuration ID=`"$([guid]::NewGuid())`">$add<Property Name=`"SharedComputerLicensing`" Value=`"1`" /></Configuration>"
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'B.xml') -Value "<Configuration>$add</Configuration>"
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'C.xml') -Value "<Configuration ID=`"not-a-guid`">$add</Configuration>"
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'D.xml') -Value '<Configuration>'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Uninstall-Microsoft365Apps.xml') -Value '<Configuration />'

        $configurations = @(Get-EwM365Configuration -Path $folder)
        $configurations.FileName | Should -Be @('A.xml', 'B.xml', 'C.xml', 'D.xml')
        $configurations.Status | Should -Be @('Valid', 'No ID', 'Invalid ID', 'Invalid XML')
        $configurations[0].Channel | Should -Be 'MonthlyEnterprise'
        $configurations[0].IsVdi | Should -BeTrue
        $configurations[0].ExcludedProducts | Should -Be 'Groove'
    }
}

Describe 'Version comparison' {
    It 'normalizes <Version> to <Expected>' -TestCases @(
        @{ Version = 'v1.2.3-beta'; Expected = '1.2.3' }
        @{ Version = '140'; Expected = '140.0' }
        @{ Version = '1.2.3.4.5'; Expected = '1.2.3.4' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Version = $Version; Expected = $Expected } {
            $result = ConvertTo-EwComparableVersion -Version $Version
            $result.Success | Should -BeTrue
            $result.Parsed | Should -Be ([version]$Expected)
        }
    }

    It 'fails for text without digits' {
        InModuleScope EvergreenUI {
            (ConvertTo-EwComparableVersion -Version 'latest').Success | Should -BeFalse
        }
    }
}

Describe 'Intune comparison' {
    It 'pages through Win32 apps and keeps only PSPackageFactory apps' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -notlike 'https://next.example.test*' } {
                [PSCustomObject]@{
                    value = @([PSCustomObject]@{ id = '1'; displayName = 'Other'; notes = 'manual' })
                    '@odata.nextLink' = 'https://next.example.test/page2'
                }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like 'https://next.example.test*' } {
                [PSCustomObject]@{
                    value = @([PSCustomObject]@{
                            id = '2'; displayName = 'App'; publisher = 'Pub'; displayVersion = '1.0'
                            notes = '{"CreatedBy":"PSPackageFactory","Guid":"ABC"}'
                        })
                }
            }
            $apps = @(Get-EwIntuneApp)
            $apps.Count | Should -Be 1
            $apps[0].IntuneAppId | Should -Be '2'
            $apps[0].NotesGuid | Should -Be 'ABC'
            $apps[0].NotesValid | Should -Be 'Yes'
            Should -Invoke Invoke-MgGraphRequest -Exactly 2
        }
    }

    It 'classifies matched, outdated, missing, and unmatched apps' {
        InModuleScope EvergreenUI {
            Mock Get-EwDefinition {
                @(
                    [PSCustomObject]@{ Name = 'Current'; Version = '1.0'; Publisher = 'Pub'; PSPackageFactoryGuid = 'g1'; DefinitionPath = 'c:\d\1'; Status = 'Valid'; DefinitionObject = $null }
                    [PSCustomObject]@{ Name = 'Outdated'; Version = '2.0'; Publisher = 'Pub'; PSPackageFactoryGuid = 'g2'; DefinitionPath = 'c:\d\2'; Status = 'Valid'; DefinitionObject = $null }
                    [PSCustomObject]@{ Name = 'New'; Version = '1.0'; Publisher = 'Pub'; PSPackageFactoryGuid = 'g3'; DefinitionPath = 'c:\d\3'; Status = 'Valid'; DefinitionObject = $null }
                )
            }

            $intuneApps = @(
                [PSCustomObject]@{ IntuneAppId = 'a1'; DisplayName = 'Current'; Publisher = 'Pub'; DisplayVersion = '1.0'; NotesGuid = 'G1'; NotesValid = 'Yes'; IsUpdateApp = $false }
                [PSCustomObject]@{ IntuneAppId = 'a2'; DisplayName = 'Outdated'; Publisher = 'Pub'; DisplayVersion = '1.0'; NotesGuid = 'g2'; NotesValid = 'Yes'; IsUpdateApp = $false }
                [PSCustomObject]@{ IntuneAppId = 'a4'; DisplayName = 'Orphan'; Publisher = 'Pub'; DisplayVersion = '1.0'; NotesGuid = 'g4'; NotesValid = 'Yes'; IsUpdateApp = $false }
            )
            $rows = @(Compare-EwIntuneApp -DefinitionPath 'c:\d' -IntuneApp $intuneApps)
            $rows[0].MatchStatus | Should -Be 'No matching Win32 app'
            $rows[0].ImportAction | Should -Be 'Import new app'
            $rows[1].MatchStatus | Should -Be 'Matched (update required)'
            ($rows | Where-Object IntuneAppId -EQ 'a1').MatchStatus | Should -Be 'Matched (current)'
            ($rows | Where-Object IntuneAppId -EQ 'a4').MatchStatus | Should -Be 'No local definition'
        }
    }

    It 'retrieves supersedence relationships for duplicate GUIDs' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant-id' } }
            Mock Invoke-MgGraphRequest {
                if ($Uri -like '*/new/relationships') {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.mobileAppSupersedence'; targetId = 'old'; targetType = 'parent' }) }
                }
                if ($Uri -like '*/old/relationships') {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.mobileAppSupersedence'; targetId = 'new'; targetType = 'child' }) }
                }
                else {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'old'; displayName = 'App'; publisher = 'Pub'; displayVersion = '1.0'; notes = '{"CreatedBy":"PSPackageFactory","Guid":"g1"}' }
                            [PSCustomObject]@{ id = 'new'; displayName = 'App'; publisher = 'Pub'; displayVersion = '2.0'; notes = '{"CreatedBy":"PSPackageFactory","Guid":"g1"}' }
                        )
                    }
                }
            }
            $apps = @(Get-EwIntuneApp)
            ($apps | Where-Object IntuneAppId -eq 'new').SupersededAppIds | Should -Contain 'old'
            Should -Invoke Invoke-MgGraphRequest -Exactly 3
        }
    }

    It 'marks multiple Intune apps with the same definition GUID as ambiguous' {
        InModuleScope EvergreenUI {
            Mock Get-EwDefinition {
                [PSCustomObject]@{ Name = 'App'; Version = '2.0'; Publisher = 'Pub'; PSPackageFactoryGuid = 'g1'; DefinitionPath = 'c:\d\1'; Status = 'Valid'; DefinitionObject = $null }
            }
            $apps = @(
                [PSCustomObject]@{ IntuneAppId = 'a1'; DisplayName = 'App'; Publisher = 'Pub'; DisplayVersion = '1.0'; NotesGuid = 'g1'; NotesValid = 'Yes'; IsUpdateApp = $false }
                [PSCustomObject]@{ IntuneAppId = 'a2'; DisplayName = 'App'; Publisher = 'Pub'; DisplayVersion = '2.0'; NotesGuid = 'g1'; NotesValid = 'Yes'; IsUpdateApp = $false }
            )
            $rows = @(Compare-EwIntuneApp -DefinitionPath 'c:\d' -IntuneApp $apps)
            $rows.Count | Should -Be 2
            @($rows | Where-Object MatchStatus -eq 'Duplicate Intune app GUID').Count | Should -Be 2
        }
    }

    It 'selects the current app when supersedence forms an unambiguous chain' {
        InModuleScope EvergreenUI {
            Mock Get-EwDefinition {
                [PSCustomObject]@{ Name = 'App'; Version = '3.0'; Publisher = 'Pub'; PSPackageFactoryGuid = 'g1'; DefinitionPath = 'c:\d\1'; Status = 'Valid'; DefinitionObject = $null }
            }
            $apps = @(
                [PSCustomObject]@{ IntuneAppId = 'a1'; DisplayName = 'App'; Publisher = 'Pub'; DisplayVersion = '1.0'; NotesGuid = 'g1'; NotesValid = 'Yes'; IsUpdateApp = $false; SupersededAppIds = @() }
                [PSCustomObject]@{ IntuneAppId = 'a2'; DisplayName = 'App'; Publisher = 'Pub'; DisplayVersion = '2.0'; NotesGuid = 'g1'; NotesValid = 'Yes'; IsUpdateApp = $false; SupersededAppIds = @('a1') }
                [PSCustomObject]@{ IntuneAppId = 'a3'; DisplayName = 'App'; Publisher = 'Pub'; DisplayVersion = '3.0'; NotesGuid = 'g1'; NotesValid = 'Yes'; IsUpdateApp = $false; SupersededAppIds = @('a2') }
            )
            $rows = @(Compare-EwIntuneApp -DefinitionPath 'c:\d' -IntuneApp $apps)
            ($rows | Where-Object IntuneAppId -eq 'a3').MatchStatus | Should -Be 'Matched (current)'
            @($rows | Where-Object MatchStatus -eq 'Superseded app (managed)').Count | Should -Be 2
        }
    }
}

Describe 'Azure discovery' {
    It 'reuses a matching Azure context without signing in again' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Connect-AzAccount {}
            Mock Get-AzContext {
                [PSCustomObject]@{
                    Account = [PSCustomObject]@{ Id = 'user@example.test' }
                    Tenant = [PSCustomObject]@{ Id = 'tenant-id' }
                    Subscription = [PSCustomObject]@{ Id = 'sub-id'; Name = 'Test' }
                }
            }
            $result = Connect-EwAzure -TenantId 'tenant-id' -SubscriptionId 'sub-id'
            $result.Succeeded | Should -BeTrue
            $result.SubscriptionName | Should -Be 'Test'
            Should -Invoke Connect-AzAccount -Exactly 0
        }
    }

    It 'lists resource groups, storage accounts, and containers sorted by name' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-AzResourceGroup { @([PSCustomObject]@{ ResourceGroupName = 'rg-b' }, [PSCustomObject]@{ ResourceGroupName = 'rg-a' }) }
            Mock Get-AzStorageAccount -ParameterFilter { -not $Name } { @([PSCustomObject]@{ StorageAccountName = 'st2' }, [PSCustomObject]@{ StorageAccountName = 'st1' }) }
            Mock Get-AzStorageAccount -ParameterFilter { $Name } { [PSCustomObject]@{ Context = 'storage-context' } }
            Mock Get-AzStorageContainer -RemoveParameterType Context { @([PSCustomObject]@{ Name = 'shell-apps' }) }
            @(Get-EwAzureResourceGroup) | Should -Be @('rg-a', 'rg-b')
            @(Get-EwAzureStorageAccount -ResourceGroupName 'rg-a') | Should -Be @('st1', 'st2')
            @(Get-EwAzureStorageContainer -ResourceGroupName 'rg-a' -StorageAccountName 'st1') | Should -Be @('shell-apps')
            Should -Invoke Get-AzStorageContainer -Exactly 1 -ParameterFilter { $Context -eq 'storage-context' }
        }
    }

    It 'signs out, clears the Azure process context, and clears the Nerdio token' {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{ Token = 'token' }
            Mock Assert-EwModule {}
            Mock Get-AzContext { [PSCustomObject]@{ Account = [PSCustomObject]@{ Id = 'user@example.test' } } }
            Mock Disconnect-AzAccount {}
            Mock Clear-AzContext {}
            $result = Disconnect-EwAzure
            $result.Succeeded | Should -BeTrue
            $result.WasConnected | Should -BeTrue
            $script:ewNerdioSession.Context | Should -BeNullOrEmpty
            Should -Invoke Disconnect-AzAccount -Exactly 1 -ParameterFilter { $Scope -eq 'Process' }
            Should -Invoke Clear-AzContext -Exactly 1 -ParameterFilter { $Scope -eq 'Process' -and $Force }
        }
    }

    It 'clears the Azure process context without signing out when no context exists' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-AzContext {}
            Mock Disconnect-AzAccount {}
            Mock Clear-AzContext {}
            $result = Disconnect-EwAzure
            $result.Succeeded | Should -BeTrue
            $result.WasConnected | Should -BeFalse
            Should -Invoke Disconnect-AzAccount -Exactly 0
            Should -Invoke Clear-AzContext -Exactly 1
        }
    }
}

Describe 'Nerdio Shell App parity' {
    BeforeAll {
        $definitionRoot = Join-Path -Path $TestDrive -ChildPath 'ShellApps'
        $definitions = @{
            Chrome = '{"publisher":"Google","name":"Chrome","source":{"type":"Evergreen","app":"GoogleChrome","filter":"$_.Architecture -eq ''x64''"},"versions":[]}'
            Edge = '{"publisher":"Microsoft","name":"Edge","source":{"type":"Evergreen","app":"MicrosoftEdge","filter":""}}'
            NewApp = '{"publisher":"Contoso","name":"New App","source":{"type":"Evergreen","app":"Contoso"}}'
            Static = '{"publisher":"Fabrikam","name":"Tool","source":{"type":"Static","url":"https://example.test/tool.msi","version":"1.0"}}'
            Missing = '{"name":"No publisher"}'
            Broken = '{ not json'
        }
        foreach ($name in $definitions.Keys) {
            $folder = Join-Path -Path $definitionRoot -ChildPath $name
            $null = New-Item -Path $folder -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Definition.json') -Value $definitions[$name]
        }
    }

    BeforeEach {
        InModuleScope EvergreenUI {
            $script:ewNerdioSession.Context = [PSCustomObject]@{
                AccessToken = 'test-token'
                TokenExpiresAt = [DateTimeOffset]::UtcNow.AddHours(1)
                NmeHost = 'nme.example.test'
            }
        }
    }

    It 'reads definitions and reports validation status' {
        $rows = @(Get-EwNerdioDefinition -Path $definitionRoot)
        $rows.Count | Should -Be 6
        ($rows | Where-Object AppName -EQ 'Chrome').DefinitionValid | Should -Be 'Yes'
        ($rows | Where-Object AppName -EQ 'Chrome').SourceApp | Should -Be 'GoogleChrome'
        ($rows | Where-Object AppName -EQ 'No publisher').DefinitionValid | Should -Be 'No (missing JSON properties)'
        ($rows | Where-Object AppName -EQ 'Broken').DefinitionValid | Should -Be 'No (invalid JSON)'
    }

    It 'derives latest version and count from version records when the list omits them' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwNerdioApiRequest -ParameterFilter { $Uri -like '*/shell-app' } {
                [PSCustomObject]@{ items = @([PSCustomObject]@{ id = 7; name = 'Chrome'; publisher = 'Google' }) }
            }
            Mock Invoke-EwNerdioApiRequest -ParameterFilter { $Uri -like '*/shell-app/7/version' } {
                [PSCustomObject]@{ items = @([PSCustomObject]@{ name = '9.0' }, [PSCustomObject]@{ name = '10.0' }, [PSCustomObject]@{ name = 'preview' }) }
            }
            $app = Get-EwNerdioShellApp
            $app.Id | Should -Be '7'
            $app.LatestVersion | Should -Be '10.0'
            $app.VersionCount | Should -Be 3
        }
    }

    It 'compares definitions with Shell Apps using safe source resolution' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionRoot = $definitionRoot } {
            Mock Get-EwAppVersion -ParameterFilter { $Name -eq 'GoogleChrome' } {
                @(
                    [PSCustomObject]@{ Version = '9.0'; Architecture = 'x86'; URI = 'https://example.test/x86.msi' }
                    [PSCustomObject]@{ Version = '11.0'; Architecture = 'x64'; URI = 'https://example.test/x64.msi' }
                )
            }
            Mock Get-EwAppVersion -ParameterFilter { $Name -eq 'MicrosoftEdge' } {
                @([PSCustomObject]@{ Version = '5.0'; URI = 'https://example.test/edge.msi' })
            }
            $shellApps = @(
                [PSCustomObject]@{ Id = '1'; Name = 'Chrome'; Publisher = 'google '; LatestVersion = '10.0'; VersionCount = 2 }
                [PSCustomObject]@{ Id = '2'; Name = 'Edge'; Publisher = 'Microsoft'; LatestVersion = '5.0'; VersionCount = 1 }
                [PSCustomObject]@{ Id = '3'; Name = 'Orphan'; Publisher = 'Other'; LatestVersion = '1.0'; VersionCount = 1 }
            )
            $rows = @(Compare-EwNerdioShellApp -DefinitionPath $DefinitionRoot -ShellApp $shellApps)
            $rows[0].AppName | Should -Be 'New App'
            $rows[0].Action | Should -Be 'Import'
            $chrome = $rows | Where-Object AppName -EQ 'Chrome'
            $chrome.MatchStatus | Should -Be 'Matched (update available)'
            $chrome.SourceVersion | Should -Be '11.0'
            $chrome.Action | Should -Be 'Update'
            ($rows | Where-Object AppName -EQ 'Edge').MatchStatus | Should -Be 'Matched (No update required)'
            ($rows | Where-Object AppName -EQ 'Tool').MatchStatus | Should -Be 'Unsupported source type'
            ($rows | Where-Object NerdioAppId -EQ '3').MatchStatus | Should -Be 'No local definition'
            $rows[-1].MatchStatus | Should -Not -Be 'Matched (update available)'
        }
    }

    It 'rejects unsafe source filters instead of executing them' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion { @([PSCustomObject]@{ Version = '1.0' }) }
            $source = [PSCustomObject]@{ type = 'Evergreen'; app = 'App'; filter = '$(Remove-Item C:\)' }
            { Resolve-EwNerdioSource -Source $source } | Should -Throw
            Should -Invoke Get-EwAppVersion -Exactly 0
        }
    }

    It 'rejects unorderable version names before deleting anything' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwNerdioApiRequest -ParameterFilter { $Method -eq 'GET' } {
                [PSCustomObject]@{ items = @(
                        [PSCustomObject]@{ name = '10.0' }
                        [PSCustomObject]@{ name = '9.1' }
                        [PSCustomObject]@{ name = '8.0' }
                        [PSCustomObject]@{ name = 'latest' }
                    ) }
            }
            { Remove-EwNerdioShellAppVersion -Id 7 -KeepVersions 2 -Confirm:$false } |
                Should -Throw '*cannot be pruned safely*'
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 0 -ParameterFilter { $Method -eq 'DELETE' }
        }
    }

    It 'adds a version from the definition source' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = (Join-Path -Path $definitionRoot -ChildPath 'Chrome') } {
            Mock Get-EwAppVersion {
                @([PSCustomObject]@{ Version = '11.0'; Architecture = 'x64'; URI = 'https://example.test/x64.msi' })
            }
            Mock Invoke-EwArtifactSave {
                $file = Join-Path -Path $Path -ChildPath 'chrome.msi'
                Set-Content -LiteralPath $file -Value 'package'
                Get-Item -LiteralPath $file
            }
            Mock Invoke-EwNerdioBlobUpload { [PSCustomObject]@{ Sha256 = 'sha256'; SourceUrl = 'https://storage.example.test/chrome.msi' } }
            Mock Invoke-EwNerdioApiRequest { [PSCustomObject]@{ job = [PSCustomObject]@{ id = 'job-id'; status = 'Completed' } } }

            $result = Publish-EwNerdioApp -DefinitionPath $DefinitionPath -ShellAppId 7 -DownloadPath (Join-Path -Path $TestDrive -ChildPath 'dl') -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.AppId | Should -Be '7'
            $result.Version | Should -Be '11.0'
            Should -Invoke Invoke-EwArtifactSave -Exactly 1 -ParameterFilter { $Artifact.URI -eq 'https://example.test/x64.msi' }
            Should -Invoke Invoke-EwNerdioApiRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'https://nme.example.test/api/v1/shell-app/7/version' -and
                $Body.name -eq '11.0' -and $Body.file.sha256 -eq 'sha256' -and $Body.isPreview -eq $false
            }
        }
    }
}
