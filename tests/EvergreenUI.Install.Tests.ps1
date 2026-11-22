#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Local package detection' {
    It 'passes existence rules and requires every configured rule to pass' {
        $presentFile = Join-Path -Path $TestDrive -ChildPath 'present.exe'
        Set-Content -LiteralPath $presentFile -Value 'test'
        $definition = [PSCustomObject]@{
            DetectionRule = @(
                [PSCustomObject]@{ Type = 'File'; Path = $presentFile; DetectionMethod = 'Existence' }
                [PSCustomObject]@{ Type = 'File'; Path = (Join-Path -Path $TestDrive -ChildPath 'missing.exe'); DetectionMethod = 'Existence' }
            )
        }
        $result = Test-EwDetection -DefinitionObject $definition
        $result.Succeeded | Should -BeTrue
        $result.Installed | Should -BeFalse
        $result.RuleCount | Should -Be 2
        $result.RulePassCount | Should -Be 1
    }

    It 'returns success with a clear status when no detection rules exist' {
        $result = Test-EwDetection -DefinitionObject ([PSCustomObject]@{ DetectionRule = @() })
        $result.Succeeded | Should -BeTrue
        $result.Installed | Should -BeFalse
        $result.Status | Should -Be 'No detection rules'
    }
}

Describe 'Local package installation' {
    BeforeEach {
        $script:installRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $script:installDefinitionPath = Join-Path -Path $installRoot -ChildPath 'Example\App.json'
        $definitionFolder = Split-Path -Path $installDefinitionPath -Parent
        New-Item -Path $definitionFolder -ItemType Directory -Force | Out-Null
        [PSCustomObject]@{
            Application = [PSCustomObject]@{ Name = 'Example'; Filter = 'Get-EvergreenApp -Name "ExampleApp"' }
            Information = [PSCustomObject]@{ DisplayName = 'Example app' }
            PackageInformation = [PSCustomObject]@{ SetupFile = 'old.exe'; Version = '1.0' }
            Program = [PSCustomObject]@{ InstallCommand = 'installer.exe /quiet' }
            RequirementRule = [PSCustomObject]@{ Architecture = 'All' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $installDefinitionPath
    }

    It 'does not resolve, download, or execute when WhatIf is specified' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {}
            Mock Invoke-EwArtifactSave {}
            Mock Invoke-EwInstallerProcess {}
            Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Resolve-EwArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
            Should -Invoke Invoke-EwInstallerProcess -Exactly 0
        }
    }

    It 'stages the artifact and reports successful installer exit codes' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'installer.exe' }
            }
            Mock Invoke-EwInstallerProcess { [PSCustomObject]@{ ExitCode = 3010 } }
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.Status | Should -Be 'Installed'
            $result.ExitCode | Should -Be 3010
            $result.DownloadedVersion | Should -Be '2.0'
            Should -Invoke Invoke-EwArtifactSave -Exactly 1
            Should -Invoke Invoke-EwInstallerProcess -Exactly 1 -ParameterFilter {
                $Command -eq 'installer.exe /quiet' -and [string]::IsNullOrWhiteSpace($ScriptPath)
            }
        }
    }

    It 'blocks an invalid requirement before resolving or downloading' {
        $definition = Get-Content -LiteralPath $installDefinitionPath -Raw | ConvertFrom-Json
        $definition.RequirementRule.Architecture = 'x64,typo'
        $definition | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $installDefinitionPath
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {}
            Mock Invoke-EwArtifactSave {}
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            $result.Status | Should -Be 'Blocked'
            $result.Error | Should -Match 'x64,typo'
            Should -Invoke Resolve-EwArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
    }

    It 'returns skipped when architecture approval is declined even with Confirm disabled' {
        $definition = Get-Content -LiteralPath $installDefinitionPath -Raw | ConvertFrom-Json
        $definition.RequirementRule.Architecture = ''
        $definition | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $installDefinitionPath
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
                    Error = ''
                }
            }
            Mock Confirm-EwInstallArchitecture { $false }
            Mock Invoke-EwArtifactSave {}
            Mock Invoke-EwInstallerProcess {}
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            $result.Status | Should -Be 'Skipped'
            $result.Error | Should -Match 'declined'
            Should -Invoke Confirm-EwInstallArchitecture -Exactly 1
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
            Should -Invoke Invoke-EwInstallerProcess -Exactly 0
        }
    }

    It 'throws when architecture approval is required in a non-interactive host' {
        $definition = Get-Content -LiteralPath $installDefinitionPath -Raw | ConvertFrom-Json
        $definition.RequirementRule.Architecture = ''
        $definition | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $installDefinitionPath
        $manifest = (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1').Replace("'", "''")
        $definitionPath = $installDefinitionPath.Replace("'", "''")
        $workingPath = $installRoot.Replace("'", "''")
        $script = @"
`$ErrorActionPreference = 'Continue'
Import-Module -Name '$manifest' -Force
& (Get-Module -Name EvergreenUI) {
    function script:Resolve-EwArtifact {
        [CmdletBinding()] param([string]`$DefinitionPath, [switch]`$NoCache)
        [PSCustomObject]@{
            Succeeded = `$true; Version = '2.0'; URI = 'https://example.test/installer.exe'
            ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
            Error = ''
        }
    }
}
try {
    Install-EwPackage -DefinitionPath '$definitionPath' -WorkingPath '$workingPath' -Confirm:`$false -ErrorAction Continue
    [Console]::WriteLine('UNEXPECTED-RETURN')
}
catch {
    [Console]::WriteLine('EXPECTED-THROW: ' + `$_.Exception.Message)
}
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
        $output = & (Join-Path -Path $PSHOME -ChildPath 'pwsh.exe') -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 |
            Out-String
        $output | Should -Match 'EXPECTED-THROW:'
        $output | Should -Not -Match 'UNEXPECTED-RETURN'
    }

    It 'requires separate opt-ins for missing requirements and x64 emulation' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
                    Error = ''
                }
            }
            Mock Get-EwInstallArchitectureCompatibility {
                [PSCustomObject]@{
                    Status = 'NeedsApproval'
                    RequiresMissingRequirementApproval = $true
                    RequiresX64OnArm64Approval = $true
                    MissingRequirementWarning = 'Missing requirement'
                    X64OnArm64Warning = 'x64 emulation'
                    Error = ''
                }
            }
            Mock Confirm-EwInstallArchitecture { $false }
            Mock Invoke-EwArtifactSave {
                [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'installer.exe' }
            }
            Mock Invoke-EwInstallerProcess { [PSCustomObject]@{ ExitCode = 0 } }
            $declined = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -AllowMissingArchitectureRequirement -Confirm:$false
            $declined.Status | Should -Be 'Skipped'
            Should -Invoke Confirm-EwInstallArchitecture -Exactly 1 -ParameterFilter {
                @($Warning).Count -eq 1 -and $Warning[0] -eq 'x64 emulation'
            }
            $missingDeclined = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -AllowX64OnArm64 -Confirm:$false
            $missingDeclined.Status | Should -Be 'Skipped'
            Should -Invoke Confirm-EwInstallArchitecture -Exactly 1 -ParameterFilter {
                @($Warning).Count -eq 1 -and $Warning[0] -eq 'Missing requirement'
            }
            $approved = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -AllowMissingArchitectureRequirement -AllowX64OnArm64 -Confirm:$false
            $approved.Status | Should -Be 'Installed'
            Should -Invoke Confirm-EwInstallArchitecture -Exactly 2
        }
    }

    It 'does not execute when the Definition changes during staging' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                Add-Content -LiteralPath $DefinitionPath -Value ' '
                [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'installer.exe' }
            }
            Mock Invoke-EwInstallerProcess {}
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -Confirm:$false
            $result.Status | Should -Be 'Skipped'
            $result.ReviewChanged | Should -BeTrue
            Should -Invoke Invoke-EwInstallerProcess -Exactly 0
        }
    }

    It 'rejects changed Artifact metadata after review before downloading' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            $script:reviewArtifactArchitecture = 'x86'
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{
                        Version = '2.0'; URI = 'https://example.test/installer.exe'
                        Architecture = $script:reviewArtifactArchitecture
                    }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {}
            $review = Get-EwInstallReview -DefinitionPath $DefinitionPath -NoCache
            $script:reviewArtifactArchitecture = 'x64'
            $result = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -ExpectedReviewFingerprint $review.Fingerprint -NoCache -Confirm:$false
            $result.Status | Should -Be 'Skipped'
            $result.ReviewChanged | Should -BeTrue
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
    }
}
