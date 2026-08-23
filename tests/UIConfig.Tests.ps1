#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Merge-ConfigSection' -Tag 'Unit' {
    It 'Returns defaults when the loaded section is null' {
        InModuleScope EvergreenUI {
            $default = [PSCustomObject]@{ First = 'one'; Second = 'two' }

            $result = Merge-ConfigSection -Loaded $null -Default $default

            $result | Should -Be $default
        }
    }

    It 'Preserves loaded values and adds missing defaults' {
        InModuleScope EvergreenUI {
            $loaded = [PSCustomObject]@{ First = 'custom' }
            $default = [PSCustomObject]@{ First = 'one'; Second = 'two' }

            $result = Merge-ConfigSection -Loaded $loaded -Default $default

            $result.First | Should -Be 'custom'
            $result.Second | Should -Be 'two'
        }
    }
}

Describe 'Get-UIConfig and Set-UIConfig' -Tag 'Unit' {
    It 'Returns canonical defaults when no config file exists' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestNoConfig_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig

                $config.Theme | Should -Be 'Light'
                $config.LogHeight | Should -Be 150
                $config.ImportSettings.CurrentProvider | Should -Be 'Authentication'
                $config.NerdioSettings.NmeResourceGroup | Should -Be ''
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Returns defaults when settings JSON is malformed' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestMalformed_$(Get-Random)"
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
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestMissingSections_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                [PSCustomObject]@{ Theme = 'Dark' } | ConvertTo-Json -Compress |
                    Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Encoding UTF8

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

    It 'Uses ShowImportTab when legacy settings omit ShowInstallTab' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestLegacyTab_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                [PSCustomObject]@{ ShowImportTab = $false } | ConvertTo-Json -Compress |
                    Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Encoding UTF8

                (Get-UIConfig).ShowInstallTab | Should -BeFalse
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Restores Authentication when the persisted provider is blank' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestBlankProvider_$(Get-Random)"
            $configDirectory = Join-Path -Path $tempAppData -ChildPath 'EvergreenUI'
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                New-Item -Path $configDirectory -ItemType Directory -Force | Out-Null
                $persistedConfig = [PSCustomObject]@{
                    ImportSettings = [PSCustomObject]@{ CurrentProvider = '   ' }
                }
                $persistedConfig | ConvertTo-Json -Compress |
                    Set-Content -Path (Join-Path -Path $configDirectory -ChildPath 'settings.json') -Encoding UTF8

                (Get-UIConfig).ImportSettings.CurrentProvider | Should -Be 'Authentication'
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Falls back to the default output path when the persisted path is blank' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestBlankOutput_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig
                $config.OutputPath = ''
                Set-UIConfig -Config $config

                $expected = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath 'Downloads'
                (Get-UIConfig).OutputPath | Should -Be $expected
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Persists and retrieves configuration values' {
        InModuleScope EvergreenUI {
            $tempAppData = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_TestRoundTrip_$(Get-Random)"
            $originalAppData = $env:APPDATA
            $env:APPDATA = $tempAppData
            try {
                $config = Get-UIConfig
                $config.Theme = 'Dark'
                $config.OutputPath = 'C:\TestOutput'
                $config.StartupView = 'Update'
                $config.ImportSettings.CurrentProvider = 'Intune'
                Set-UIConfig -Config $config

                $loaded = Get-UIConfig

                $loaded.Theme | Should -Be 'Dark'
                $loaded.OutputPath | Should -Be 'C:\TestOutput'
                $loaded.StartupView | Should -Be 'Update'
                $loaded.ImportSettings.CurrentProvider | Should -Be 'Intune'
            }
            finally {
                $env:APPDATA = $originalAppData
                Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}