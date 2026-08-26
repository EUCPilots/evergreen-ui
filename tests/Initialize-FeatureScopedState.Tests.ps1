BeforeAll {
    # Import the module to load all private functions
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psm1'
    Import-Module -Name $modulePath -Force
}

Describe 'Initialize-FeatureScopedState' -Tag 'Unit' {
    Context 'Operations Container' {
        It 'Should create Operations container with correct structure' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.ContainsKey('Operations') | Should -Be $true
            $syncHash.Operations.ContainsKey('Registry') | Should -Be $true
            $syncHash.Operations.ContainsKey('PollingTimer') | Should -Be $true
            $syncHash.Operations.ContainsKey('ActiveCount') | Should -Be $true
            $syncHash.Operations.ContainsKey('LastPolledAt') | Should -Be $true
        }

        It 'Operations.Registry should be an empty synchronized hashtable' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Operations.Registry | Should -BeOfType [hashtable]
            $syncHash.Operations.Registry.Count | Should -Be 0
        }

        It 'Operations.PollingTimer should be null initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Operations.PollingTimer | Should -Be $null
        }

        It 'Operations.ActiveCount should be 0 initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Operations.ActiveCount | Should -Be 0
        }

        It 'Operations.LastPolledAt should be MinValue initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Operations.LastPolledAt | Should -Be ([datetime]::MinValue)
        }
    }

    Context 'Install Container' {
        It 'Should create Install container with correct structure' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.ContainsKey('Install') | Should -Be $true
            $syncHash.Install.ContainsKey('IsLoading') | Should -Be $true
            $syncHash.Install.ContainsKey('DefinitionRows') | Should -Be $true
            $syncHash.Install.ContainsKey('Rows') | Should -Be $true
            $syncHash.Install.ContainsKey('ActionButtonStates') | Should -Be $true
            $syncHash.Install.ContainsKey('SortProperty') | Should -Be $true
            $syncHash.Install.ContainsKey('SortDirection') | Should -Be $true
            $syncHash.Install.ContainsKey('LatestVersionCache') | Should -Be $true
            $syncHash.Install.ContainsKey('LatestVersionCacheAge') | Should -Be $true
        }

        It 'Install.IsLoading should be false initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Install.IsLoading | Should -Be $false
        }

        It 'Install.DefinitionRows should be an empty array' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            # Empty array in PowerShell evaluates to empty collection
            @($syncHash.Install.DefinitionRows).Count | Should -Be 0
        }

        It 'Install.SortDirection should default to Ascending' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Install.SortDirection | Should -Be 'Ascending'
        }

        It 'Install.LatestVersionCache should be an empty hashtable' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Install.LatestVersionCache | Should -BeOfType [hashtable]
            $syncHash.Install.LatestVersionCache.Count | Should -Be 0
        }
    }

    Context 'Intune Container' {
        It 'Should create Intune container with correct structure' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.ContainsKey('Intune') | Should -Be $true
            $syncHash.Intune.ContainsKey('IsLoading') | Should -Be $true
            $syncHash.Intune.ContainsKey('DefinitionRows') | Should -Be $true
            $syncHash.Intune.ContainsKey('Win32Rows') | Should -Be $true
            $syncHash.Intune.ContainsKey('ComparisonRows') | Should -Be $true
            $syncHash.Intune.ContainsKey('CompareHasRun') | Should -Be $true
        }

        It 'Intune.CompareHasRun should be false initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Intune.CompareHasRun | Should -Be $false
        }
    }

    Context 'Nerdio Container' {
        It 'Should create Nerdio container with correct structure' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.ContainsKey('Nerdio') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('IsShellAppsLoading') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('IsAddVersionLoading') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('IsPruneLoading') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('IsImportNewLoading') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('DefinitionRows') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('ShellAppRows') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('ComparisonRows') | Should -Be $true
            $syncHash.Nerdio.ContainsKey('PostImportVerifyAppId') | Should -Be $true
        }

        It 'Nerdio.SelectedComparisonRow should be null initially' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.Nerdio.SelectedComparisonRow | Should -Be $null
        }
    }

    Context 'M365 Container' {
        It 'Should create M365 container with correct structure' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $syncHash.ContainsKey('M365') | Should -Be $true
            $syncHash.M365.ContainsKey('IsImportLoading') | Should -Be $true
            $syncHash.M365.ContainsKey('IsEvergreenLoading') | Should -Be $true
            $syncHash.M365.ContainsKey('ConfigRows') | Should -Be $true
            $syncHash.M365.ContainsKey('EvergreenRows') | Should -Be $true
        }
    }

    Context 'Idempotence' {
        It 'Should not duplicate containers when called multiple times' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $firstOperationsRegistry = $syncHash.Operations.Registry
            
            # Call again
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            $secondOperationsRegistry = $syncHash.Operations.Registry
            $firstOperationsRegistry -eq $secondOperationsRegistry | Should -Be $true
        }
    }

    Context 'Thread Safety' {
        It 'Should allow concurrent access to synchronized hashtables' {
            $syncHash = [hashtable]::Synchronized(@{})
            Initialize-FeatureScopedState -SyncHash $syncHash
            
            # Verify nested containers are also accessible from multiple threads
            $job1 = Start-Job -ScriptBlock {
                param($hash)
                $hash.Install.IsLoading = $true
                $hash.Install.IsLoading
            } -ArgumentList $syncHash
            
            $result = Receive-Job -Job $job1 -Wait
            $result | Should -Be $true
            Remove-Job -Job $job1
        }
    }
}
