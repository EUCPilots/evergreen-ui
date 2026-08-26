#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Register-AppsFeature' -Tag 'Unit' {
    It 'Stores a LoadAppCatalog callback that can run outside module scope' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $syncHash = InModuleScope EvergreenUI {
            Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

            function Get-MockWpfControl {
                param([hashtable]$Property = @{})

                $control = [PSCustomObject]$Property
                $control | Add-Member -MemberType ScriptMethod -Name AddHandler -Value {
                    param($RoutedEvent, $Handler, $HandledEventsToo)
                    [void]$RoutedEvent
                    [void]$Handler
                    [void]$HandledEventsToo
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_Click -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_TextChanged -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name add_SelectionChanged -Value {
                    param($Handler)
                    [void]$Handler
                } -Force
                return $control
            }

            $appsListBox = Get-MockWpfControl -Property @{ ItemsSource = @(); SelectedItem = $null }
            $appCountLabel = Get-MockWpfControl -Property @{ Text = '' }
            $syncHash = [hashtable]::Synchronized(@{
                    AppList                 = @([PSCustomObject]@{ Name = 'TestApp'; FriendlyName = 'Test App'; IsFavourite = $false })
                    Config                  = [PSCustomObject]@{ FavouriteApps = @(); LibraryPath = '' }
                    CurrentAppResults       = @()
                    FilterState             = @{}
                    VersionsColSavedWidths  = @{}
                    VersionsListView        = Get-MockWpfControl -Property @{ Items = @(); ItemsSource = @() }
                    VersionsSortDirection   = 'Ascending'
                    VersionsSortProperty    = ''
                    TestAppsListBox         = $appsListBox
                    TestAppCountLabel       = $appCountLabel
                })
            $syncHash['SetUIConfig'] = {
                param($Config)
                [void]$Config
            }
            $syncHash['WriteUILog'] = {
                param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info')
                [void]$SyncHash
                [void]$Message
                [void]$Level
            }

            $controls = @{
                AddToLibraryButton    = $null
                AddToQueueButton      = $null
                AppCountLabel         = $appCountLabel
                AppDetailContent      = $null
                AppDetailEmpty        = $null
                AppDetailLoading      = $null
                AppDetailLoadingLabel = $null
                AppDetailTitle        = $null
                AppSearchBox          = Get-MockWpfControl -Property @{ Text = '' }
                AppsActionStatusLabel = $null
                AppsListBox           = $appsListBox
                ClearFiltersButton    = $null
                ExportCsvButton       = $null
                FilterWrapPanel       = $null
                LoadAppVersionsButton = $null
                RefreshAppsButton     = $null
            }

            Register-AppsFeature -SyncHash $syncHash -Controls $controls -RegisterBackgroundOperation {}
            return $syncHash
        }

        { & ($syncHash['LoadAppCatalog']) } | Should -Not -Throw
        @($syncHash.TestAppsListBox.ItemsSource) | Should -HaveCount 1
        $syncHash.TestAppCountLabel.Text | Should -Be ' 1 of 1'
    }
}