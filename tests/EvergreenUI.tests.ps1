#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the EvergreenUI module.

.DESCRIPTION
    Run with: Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module from source (not from an installed copy)
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'Has a valid module manifest' {
        $manifestPath = Join-Path $PSScriptRoot '..\EvergreenUI\EvergreenUI.psd1'
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Exports only Start-EvergreenWorkbench' {
        $manifest = Import-PowerShellDataFile -Path (
            Join-Path $PSScriptRoot '..\EvergreenUI\EvergreenUI.psd1'
        )
        $manifest.FunctionsToExport | Should -Be @('Start-EvergreenWorkbench')
    }
}

Describe 'Get-FilterableProperties' {
    BeforeAll {
        # Minimal mock data representing Get-EvergreenApp output
        $script:edgeData = @(
            [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x64'; Type='msi'; URI='https://example.com/edge-x64.msi'; Date='2026-03-01' }
            [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x86'; Type='msi'; URI='https://example.com/edge-x86.msi'; Date='2026-03-01' }
            [PSCustomObject]@{ Version='145.0.0'; Channel='Beta';   Architecture='x64'; Type='msi'; URI='https://example.com/edge-beta-x64.msi'; Date='2026-03-01' }
        )

        $script:uriOnlyData = @(
            [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app.exe' }
            [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app2.msi' }
        )
    }

    It 'Returns filterable properties excluding display-only columns' {
        InModuleScope EvergreenUI {
            $edgeData = @(
                [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x64'; Type='msi'; URI='https://example.com/edge-x64.msi'; Date='2026-03-01'; Sha='abc'; Sha1='abc1'; Sha256='abc256'; Hash='h1' }
                [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x86'; Type='msi'; URI='https://example.com/edge-x86.msi'; Date='2026-03-01'; Sha='def'; Sha1='def1'; Sha256='def256'; Hash='h2' }
                [PSCustomObject]@{ Version='145.0.0'; Channel='Beta';   Architecture='x64'; Type='msi'; URI='https://example.com/edge-beta-x64.msi'; Date='2026-03-01'; Sha='ghi'; Sha1='ghi1'; Sha256='ghi256'; Hash='h3' }
            )
            $result = Get-FilterableProperties -AppResults $edgeData
            $result.Name | Should -Contain 'Architecture'
            $result.Name | Should -Contain 'Channel'
            $result.Name | Should -Contain 'Type'
            $result.Name | Should -Not -Contain 'Version'
            $result.Name | Should -Not -Contain 'URI'
            $result.Name | Should -Not -Contain 'Date'
            $result.Name | Should -Not -Contain 'Sha'
            $result.Name | Should -Not -Contain 'Sha1'
            $result.Name | Should -Not -Contain 'Sha256'
            $result.Name | Should -Not -Contain 'Hash'
        }
    }

    It 'Assigns CheckBoxStrip control type when unique value count is <= 6' {
        InModuleScope EvergreenUI {
            $edgeData = @(
                [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x64'; Type='msi'; URI='https://example.com/edge-x64.msi'; Date='2026-03-01' }
                [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x86'; Type='msi'; URI='https://example.com/edge-x86.msi'; Date='2026-03-01' }
                [PSCustomObject]@{ Version='145.0.0'; Channel='Beta';   Architecture='x64'; Type='msi'; URI='https://example.com/edge-beta-x64.msi'; Date='2026-03-01' }
            )
            $result = Get-FilterableProperties -AppResults $edgeData
            $archProp = $result | Where-Object { $_.Name -eq 'Architecture' }
            $archProp.ControlType | Should -Be 'CheckBoxStrip'
        }
    }

    It 'Returns empty array for empty input' {
        InModuleScope EvergreenUI {
            $result = Get-FilterableProperties -AppResults @()
            $result | Should -HaveCount 0
        }
    }

    It 'Creates synthetic File type property when Type is absent but URI is present' {
        InModuleScope EvergreenUI {
            $uriOnlyData = @(
                [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app.exe' }
                [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app2.msi' }
            )
            $result = Get-FilterableProperties -AppResults $uriOnlyData
            $synthetic = $result | Where-Object { $_.IsSynthetic -eq $true }
            $synthetic | Should -Not -BeNullOrEmpty
            $synthetic.DisplayName | Should -BeLike '*derived*'
        }
    }
}

Describe 'Get-UIConfig' {
    It 'Returns a default config object when no config file exists' {
        InModuleScope EvergreenUI {
            # Temporarily redirect APPDATA to a temp path with no config file
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestNoConfig_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig
                $config.Theme        | Should -Be 'Light'
                $config.LogHeight    | Should -Be 150
                $config.ImportSettings.CurrentProvider | Should -Be 'Authentication'
                $config.NerdioSettings.NmeResourceGroup | Should -Be ''
                $config.NerdioSettings.NmeStorageAccount | Should -Be ''
                $config.NerdioSettings.NmeContainer | Should -Be ''
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Returns defaults when the config file contains malformed JSON' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestMalformedConfig_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Value '{invalid' -Encoding UTF8

                $config = Get-UIConfig

                $config.Theme | Should -Be 'Light'
                $config.ImportSettings.CurrentProvider | Should -Be 'Authentication'
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Restores missing nested settings sections' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestMissingSections_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                $persistedConfig = [PSCustomObject]@{ Theme = 'Dark' } | ConvertTo-Json -Compress
                Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Value $persistedConfig -Encoding UTF8

                $config = Get-UIConfig

                $config.ImportSettings.CurrentProvider | Should -Be 'Authentication'
                $config.NerdioSettings.NmeResourceGroup | Should -Be ''
                $config.IntuneSettings.PackageOutputPath | Should -Be ''
                $config.M365Settings.Channel | Should -Be 'MonthlyEnterprise'
                $config.InstallSettings.HideIncompatibleArchitecture | Should -BeFalse
                $config.AzureAuthSettings.TenantId | Should -Be ''
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Uses ShowImportTab for ShowInstallTab when the install setting is absent' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestLegacyInstallTab_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                $persistedConfig = [PSCustomObject]@{ ShowImportTab = $false } | ConvertTo-Json -Compress
                Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Value $persistedConfig -Encoding UTF8

                $config = Get-UIConfig

                $config.ShowInstallTab | Should -BeFalse
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Restores Authentication when the persisted provider is blank' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestBlankProvider_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                $persistedConfig = [PSCustomObject]@{
                    ImportSettings = [PSCustomObject]@{ CurrentProvider = '   ' }
                } | ConvertTo-Json -Compress
                Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Value $persistedConfig -Encoding UTF8

                $config = Get-UIConfig

                $config.ImportSettings.CurrentProvider | Should -Be 'Authentication'
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Falls back to default OutputPath when persisted OutputPath is blank' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestBlankOutputPath_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig
                $config.OutputPath = ''
                Set-UIConfig -Config $config

                $loaded = Get-UIConfig
                $expectedDefault = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'
                $loaded.OutputPath | Should -Be $expectedDefault
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Set-UIConfig and Get-UIConfig round-trip' {
    It 'Persists and retrieves config values correctly' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestRoundTrip_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig
                $config.Theme = 'Dark'
                $config.OutputPath = 'C:\TestOutput'
                $config.StartupView = 'Update'
                $config.ImportSettings.CurrentProvider = 'Intune'
                $config.NerdioSettings.NmeResourceGroup = 'rg-ops'
                $config.NerdioSettings.NmeStorageAccount = 'stgapps01'
                $config.NerdioSettings.NmeContainer = 'shellapps'
                Set-UIConfig -Config $config

                $loaded = Get-UIConfig
                $loaded.Theme      | Should -Be 'Dark'
                $loaded.OutputPath | Should -Be 'C:\TestOutput'
                $loaded.StartupView | Should -Be 'Update'
                $loaded.ImportSettings.CurrentProvider | Should -Be 'Intune'
                $loaded.NerdioSettings.NmeResourceGroup | Should -Be 'rg-ops'
                $loaded.NerdioSettings.NmeStorageAccount | Should -Be 'stgapps01'
                $loaded.NerdioSettings.NmeContainer | Should -Be 'shellapps'
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
