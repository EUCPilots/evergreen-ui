#Requires -Version 7.6

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Local install architecture compatibility' {
    It 'assesses <Requirement> and <Artifact> on <HostArchitecture> as <Expected>' -ForEach @(
        @{ HostArchitecture = 'x86'; Requirement = 'x86'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x86'; Requirement = 'x64'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x86'; Requirement = 'x86,x64'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'x86'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'x64'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'arm64'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x86'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'arm64'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x64'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x86,x64'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x86,x64'; Artifact = 'x86'; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x64'; Artifact = 'x86'; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'All'; Artifact = 'x64'; Expected = 'NeedsApproval'; Missing = $false; Emulation = $true }
        @{ HostArchitecture = 'arm64'; Requirement = 'All'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'arm64, x86, x64'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'All, all'; Artifact = $null; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'All'; Artifact = 'arm64'; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'x86'; Artifact = 'universal'; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'x86, arm64'; Artifact = 'x86'; Expected = 'Allowed'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = 'arm64'; Artifact = ''; Expected = 'NeedsApproval'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'All,x64'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = 'x64,'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'x64'; Requirement = '-'; Artifact = 'x86'; Expected = 'NeedsApproval'; Missing = $true; Emulation = $false }
        @{ HostArchitecture = 'arm64'; Requirement = ''; Artifact = 'x64'; Expected = 'NeedsApproval'; Missing = $true; Emulation = $true }
        @{ HostArchitecture = 'x64'; Requirement = 'x64,typo'; Artifact = 'x64'; Expected = 'Blocked'; Missing = $false; Emulation = $false }
        @{ HostArchitecture = 'arm'; Requirement = 'All'; Artifact = $null; Expected = 'Blocked'; Missing = $false; Emulation = $false }
    ) {
        InModuleScope EvergreenUI -Parameters @{
            HostArchitecture = $HostArchitecture
            Requirement = $Requirement
            Artifact = $Artifact
            Expected = $Expected
            Missing = $Missing
            Emulation = $Emulation
        } {
            $definition = [PSCustomObject]@{
                RequirementRule = [PSCustomObject]@{ Architecture = $Requirement }
            }
            $resolvedArtifact = if ($null -ne $Artifact) {
                [PSCustomObject]@{ Architecture = $Artifact }
            }
            else {
                $null
            }
            $parameters = @{ DefinitionObject = $definition; OperatingSystemArchitecture = $HostArchitecture }
            if ($null -ne $resolvedArtifact) { $parameters.Artifact = $resolvedArtifact }
            $result = Get-EwInstallArchitectureCompatibility @parameters

            $result.Status | Should -Be $Expected
            $result.RequiresMissingRequirementApproval | Should -Be $Missing
            $result.RequiresX64OnArm64Approval | Should -Be $Emulation
            if ($Expected -eq 'Blocked') {
                $result.Error | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'requires approval when the requirement section is absent' {
        InModuleScope EvergreenUI {
            $result = Get-EwInstallArchitectureCompatibility -DefinitionObject ([PSCustomObject]@{}) `
                -OperatingSystemArchitecture 'x64'
            $result.Status | Should -Be 'NeedsApproval'
            $result.RequiresMissingRequirementApproval | Should -BeTrue
        }

    }

    It 'requires separate approval for unknown artifact architecture on ARM64' {
        InModuleScope EvergreenUI {
            $definition = [PSCustomObject]@{ RequirementRule = [PSCustomObject]@{ Architecture = '-' } }
            $result = Get-EwInstallArchitectureCompatibility -DefinitionObject $definition `
                -Artifact ([PSCustomObject]@{}) -OperatingSystemArchitecture 'arm64'
            $result.RequiresMissingRequirementApproval | Should -BeTrue
            $result.RequiresUnknownArchitectureApproval | Should -BeTrue
            $result.Warnings.Count | Should -Be 2
        }
    }
}
