#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Register-SettingsFeature' -Tag 'Unit' {
    It 'Populates the Evergreen apps path without external helper dependencies' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        InModuleScope EvergreenUI {
            Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

            function Get-MockEventControl {
                param([hashtable]$Property = @{})

                $control = [PSCustomObject]$Property
                $control | Add-Member -MemberType ScriptMethod -Name add_Checked -Value {
                    param($Handler)
                    $this.CheckedHandler = $Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_Click -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_SelectionChanged -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_LostFocus -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                return $control
            }

            $evergreenAppsPathBox = Get-MockEventControl -Property @{ Text = '' }
            $navSettings = Get-MockEventControl -Property @{ CheckedHandler = $null }
            $syncHash = [hashtable]::Synchronized(@{
                    Config = [PSCustomObject]@{
                        OutputPath       = 'C:\Temp'
                        Theme            = 'Light'
                        ShowImportTab    = $true
                        ShowInstallTab   = $true
                        StartupView      = 'Apps'
                        InstallSettings  = [PSCustomObject]@{ HideIncompatibleArchitecture = $false }
                    }
                    Window = [PSCustomObject]@{}
                })
            $syncHash.Window | Add-Member -MemberType ScriptMethod -Name FindName -Value {
                param($Name)
                [void]$Name
                return [PSCustomObject]@{ Height = $null }
            } -Force
            $syncHash['GetEvergreenAppsPath'] = ${function:Get-EvergreenAppsPath}.GetNewClosure()
            $syncHash['SetDarkTheme'] = { param($Window) [void]$Window }
            $syncHash['SetLightTheme'] = { param($Window) [void]$Window }
            $syncHash['SetUIConfig'] = { param($Config) [void]$Config }
            $syncHash['WriteUILog'] = { param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info') [void]$SyncHash; [void]$Message; [void]$Level }
            $syncHash['RefreshInstallRows'] = {}
            $syncHash['UpdateDownloadAllButtonState'] = {}

            $controls = @{
                BrowseLibraryButton                     = Get-MockEventControl
                BrowseOutputButton                      = Get-MockEventControl
                ClearCacheButton                        = Get-MockEventControl
                ClearLogsButton                         = Get-MockEventControl
                CopyLogButton                           = Get-MockEventControl
                EvergreenAppsPathBox                    = $evergreenAppsPathBox
                InstallHideIncompatibleArchitectureToggle = Get-MockEventControl -Property @{ IsChecked = $false }
                LibraryPathViewBox                      = Get-MockEventControl -Property @{ Text = '' }
                LogToggleButton                         = Get-MockEventControl -Property @{ IsChecked = $false; Content = '' }
                NavApps                                 = Get-MockEventControl -Property @{ IsChecked = $false }
                NavImport                               = Get-MockEventControl -Property @{ IsChecked = $false; Visibility = $null }
                NavInstall                              = Get-MockEventControl -Property @{ IsChecked = $false; Visibility = $null }
                NavSettings                             = $navSettings
                OpenCacheFolderButton                   = Get-MockEventControl
                OpenEvergreenAppsFolderButton           = Get-MockEventControl
                OpenLogsFolderButton                    = Get-MockEventControl
                OutputPathBox                           = Get-MockEventControl -Property @{ Text = '' }
                SaveLogButton                           = Get-MockEventControl
                SettingsPanel                           = Get-MockEventControl
                ShowImportTabToggle                     = Get-MockEventControl -Property @{ IsChecked = $false }
                ShowInstallTabToggle                    = Get-MockEventControl -Property @{ IsChecked = $false }
                ThemeComboBox                           = Get-MockEventControl -Property @{ SelectedIndex = -1; SelectedItem = $null }
            }

            Register-SettingsFeature -SyncHash $syncHash -Controls $controls
            & $navSettings.CheckedHandler

            $evergreenAppsPathBox.Text | Should -Be (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Evergreen')
        }
    }
}
