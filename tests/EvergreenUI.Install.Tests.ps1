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

    It 'expands file paths in the requested program files context' {
        InModuleScope EvergreenUI {
            $native = [Environment]::GetEnvironmentVariable('ProgramW6432')
            if ([string]::IsNullOrWhiteSpace($native)) { $native = [Environment]::GetEnvironmentVariable('ProgramFiles') }
            $x86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            if ([Environment]::Is64BitOperatingSystem -and -not [string]::IsNullOrWhiteSpace($x86)) {
                Resolve-EwDetectionFilePath -Path '%ProgramFiles%\Example' -Check32BitOn64System | Should -Be "$x86\Example"
                Resolve-EwDetectionFilePath -Path '%ProgramFiles%\Example' | Should -Be "$native\Example"
            }
        }
    }

    It 'selects the requested registry view for a detection rule' {
        InModuleScope EvergreenUI {
            Mock Get-EwDetectionRegistryValue {
                [PSCustomObject]@{ KeyExists = $true; ValueExists = $true; Value = '2.0' }
            }
            $definition = [PSCustomObject]@{ DetectionRule = @(
                [PSCustomObject]@{ Type = 'Registry'; KeyPath = 'HKCU\Software\Example'; ValueName = 'Version'; DetectionMethod = 'VersionComparison'; Value = '2.0'; Check32BitOn64System = $true }
            ) }
            $result = Test-EwDetection -DefinitionObject $definition
            $result.Installed | Should -BeTrue
            Should -Invoke Get-EwDetectionRegistryValue -Exactly 1 -ParameterFilter {
                $Path -eq 'HKCU\Software\Example' -and $Check32BitOn64System
            }
        }
    }

    It 'reads registry values from the requested logical views' -Skip:(-not $IsWindows -or -not [Environment]::Is64BitOperatingSystem) {
        $subKey = "Software\Classes\CLSID\{$([guid]::NewGuid())}"
        $base32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry32)
        $base64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key32 = $base32.CreateSubKey($subKey)
            try { $key32.SetValue('Version', '32') } finally { $key32.Dispose() }
            $key64 = $base64.CreateSubKey($subKey)
            try { $key64.SetValue('Version', '64') } finally { $key64.Dispose() }
            InModuleScope EvergreenUI -Parameters @{ Path = "HKCU\$subKey" } {
                (Get-EwDetectionRegistryValue -Path $Path -ValueName 'Version' -Check32BitOn64System).Value | Should -Be '32'
                (Get-EwDetectionRegistryValue -Path $Path -ValueName 'Version').Value | Should -Be '64'
            }
        }
        finally {
            $base32.DeleteSubKeyTree($subKey, $false)
            $base64.DeleteSubKeyTree($subKey, $false)
            $base32.Dispose()
            $base64.Dispose()
        }
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
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe'; Architecture = 'x86' }
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

    It 'requires a separate opt-in for unknown artifact architecture on ARM64' {
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
                    Status = 'NeedsApproval'; RequiresMissingRequirementApproval = $true
                    RequiresX64OnArm64Approval = $false; RequiresUnknownArchitectureApproval = $true
                    MissingRequirementWarning = 'Missing requirement'; X64OnArm64Warning = ''
                    UnknownArchitectureWarning = 'Unknown artifact architecture'; Error = ''
                }
            }
            Mock Confirm-EwInstallArchitecture { $false }
            Mock Invoke-EwArtifactSave { [PSCustomObject]@{ FullName = Join-Path -Path $Path -ChildPath 'installer.exe' } }
            Mock Invoke-EwInstallerProcess { [PSCustomObject]@{ ExitCode = 0 } }
            $declined = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -AllowMissingArchitectureRequirement -Confirm:$false
            $declined.Status | Should -Be 'Skipped'
            Should -Invoke Confirm-EwInstallArchitecture -Exactly 1 -ParameterFilter {
                @($Warning).Count -eq 1 -and $Warning[0] -eq 'Unknown artifact architecture'
            }
            $approved = Install-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath `
                -AllowMissingArchitectureRequirement -AllowUnknownArchitectureOnArm64 -Confirm:$false
            $approved.Status | Should -Be 'Installed'
        }
    }

    It 'does not execute when the Definition changes during staging' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $installDefinitionPath; WorkingPath = $installRoot } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true; Version = '2.0'; URI = 'https://example.test/installer.exe'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/installer.exe'; Architecture = 'x86' }
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
