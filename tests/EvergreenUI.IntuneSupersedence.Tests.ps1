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
            $result.Succeeded | Should -BeTrue -Because $result.Error
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

    It 'posts a missing link through updateRelationships after checking existing relationships' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                if ($Method -eq 'GET') { [PSCustomObject]@{ value = @() } }
                elseif ($Uri -like '*/relationships') {
                    throw 'No method match route template: No OData route exists for relationships with http verb POST.'
                }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -SkipIfExists -Confirm:$false
            $result.Succeeded | Should -BeTrue
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/new-id/updateRelationships' -and
                @(($Body | ConvertFrom-Json).relationships).Count -eq 1 -and
                ($Body | ConvertFrom-Json).relationships[0].targetId -eq 'old-id' -and
                ($Body | ConvertFrom-Json).relationships[0].targetType -eq 'parent' -and
                ($Body | ConvertFrom-Json).relationships[0].supersedenceType -eq 'update'
            }
        }
    }

    It 'preserves existing dependencies and supersedence across pages without requiring SkipIfExists' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                if ($Method -eq 'GET' -and $Uri -like '*skiptoken=next') {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
                        targetId = 'earlier-id'; targetType = 'parent'; supersedenceType = 'update'
                    }) }
                }
                if ($Method -eq 'GET') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.mobileAppDependency'
                            targetId = 'dependency-id'; dependencyType = 'autoInstall'
                        })
                        '@odata.nextLink' = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/new-id/relationships?$skiptoken=next'
                    }
                }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -Confirm:$false
            $result.Succeeded | Should -BeTrue -Because $result.Error
            Should -Invoke Invoke-MgGraphRequest -Exactly 2 -ParameterFilter { $Method -eq 'GET' }
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*/updateRelationships' -and
                @(($Body | ConvertFrom-Json).relationships).Count -eq 3 -and
                ($Body | ConvertFrom-Json).relationships[0].targetId -eq 'dependency-id' -and
                ($Body | ConvertFrom-Json).relationships[0].dependencyType -eq 'autoInstall' -and
                ($Body | ConvertFrom-Json).relationships[1].targetId -eq 'earlier-id' -and
                ($Body | ConvertFrom-Json).relationships[1].supersedenceType -eq 'update' -and
                ($Body | ConvertFrom-Json).relationships[2].targetId -eq 'old-id'
            }
        }
    }

    It 'does not replace relationships when reading the existing collection fails' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest { throw 'Existing relationships could not be read.' }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Existing relationships could not be read'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'does not add a duplicate relationship without explicit retry handling' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.mobileAppSupersedence'
                    targetId = 'old-id'; targetType = 'parent'; supersedenceType = 'update'
                }) }
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'Supersedence already exists'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'preserves the Graph error details when supersedence is rejected' {
        InModuleScope EvergreenUI {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Invoke-MgGraphRequest {
                if ($Method -eq 'GET') { return [PSCustomObject]@{ value = @() } }
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('BadRequest (Bad Request).'),
                    'GraphBadRequest', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                    '{"error":{"code":"No method match route template","message":"No OData route exists for relationships with http verb POST."}}')
                throw $errorRecord
            }
            $result = Set-EwIntuneSupersedence -NewAppId 'new-id' -PreviousAppId 'old-id' -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'BadRequest'
            $result.Error | Should -Match 'No method match route template'
            $result.Error | Should -Match 'No OData route exists'
            Should -Invoke Invoke-MgGraphRequest -Exactly 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
