#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Intune supersedence retry' {
    It 'does not create a duplicate link if the previous attempt succeeded' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
                        targetId = 'old-id'
                        targetType = 'parent'
                    }) }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -SkipIfExists -Confirm:$false
            $result.Succeeded | Should -BeTrue
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter { $Method -eq 'GET' }
            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'does not accept an inverse supersedence relationship as a successful retry' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
                        targetId = 'old-id'
                        targetType = 'child'
                    }) }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -SkipIfExists -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'unexpected direction'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'posts a missing link after checking existing relationships' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                if ($Method -eq 'GET') { [PSCustomObject]@{ value = @() } }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -SkipIfExists -Confirm:$false
            $result.Succeeded | Should -BeTrue
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
