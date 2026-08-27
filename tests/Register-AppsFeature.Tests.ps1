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
                    AppList                 = @()
                    Config                  = [PSCustomObject]@{ FavouriteApps = @(); LibraryPath = '' }
                    CurrentAppResults       = @()
                    FilterState             = @{}
                    VersionsColSavedWidths  = @{}
                    VersionsListView        = Get-MockWpfControl -Property @{ Items = @(); ItemsSource = @() }
                    VersionsSortDirection   = 'Ascending'
                    VersionsSortProperty    = ''
                    TestAppsListBox         = $appsListBox
                    TestAppCountLabel       = $appCountLabel
                    TestLogMessages         = [System.Collections.Generic.List[string]]::new()
                })
            $syncHash['SetUIConfig'] = {
                param($Config)
                [void]$Config
            }
            $syncHash['WriteUILog'] = {
                param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info')
                [void]$Level
                $SyncHash.TestLogMessages.Add($Message)
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

        { & ($syncHash['LoadAppCatalog']) -Force } | Should -Not -Throw
        @($syncHash.TestAppsListBox.ItemsSource).Count | Should -BeGreaterThan 0
        $syncHash.TestAppCountLabel.Text | Should -Match '^ \d+ of \d+$'
        $syncHash.TestLogMessages | Should -Contain 'Retrieving application list with Evergreen...'
        $syncHash.TestLogMessages | Should -Contain 'Find-EvergreenApp'
    }

    It 'Stores a DisplayAppResults callback that can render cached results outside module scope' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $syncHash = InModuleScope EvergreenUI {
            Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

            $window = [System.Windows.Window]::new()
            $appsListBox = [System.Windows.Controls.ListBox]::new()
            $appsListBox.SelectedItem = [PSCustomObject]@{ Name = 'TestApp' }
            $versionsListView = [System.Windows.Controls.ListView]::new()
            $filterWrapPanel = [System.Windows.Controls.WrapPanel]::new()

            $syncHash = [hashtable]::Synchronized(@{
                    AppList                = @()
                    Config                 = [PSCustomObject]@{ FavouriteApps = @(); LibraryPath = '' }
                    CurrentAppResults      = @()
                    FilterState            = @{}
                    ResultsCountLabel      = [System.Windows.Controls.TextBlock]::new()
                    VersionsColSavedWidths = @{}
                    VersionsListView       = $versionsListView
                    VersionsSortDirection  = 'Ascending'
                    VersionsSortProperty   = ''
                    Window                 = $window
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
                AddToLibraryButton    = [System.Windows.Controls.Button]::new()
                AddToQueueButton      = $null
                AppCountLabel         = [System.Windows.Controls.TextBlock]::new()
                AppDetailContent      = [System.Windows.Controls.Grid]::new()
                AppDetailEmpty        = [System.Windows.Controls.Grid]::new()
                AppDetailLoading      = [System.Windows.Controls.Grid]::new()
                AppDetailLoadingLabel = [System.Windows.Controls.TextBlock]::new()
                AppDetailTitle        = [System.Windows.Controls.TextBlock]::new()
                AppSearchBox          = [System.Windows.Controls.TextBox]::new()
                AppsActionStatusLabel = $null
                AppsListBox           = $appsListBox
                ClearFiltersButton    = $null
                ExportCsvButton       = $null
                FilterWrapPanel       = $filterWrapPanel
                LoadAppVersionsButton = $null
                RefreshAppsButton     = $null
            }

            Register-AppsFeature -SyncHash $syncHash -Controls $controls -RegisterBackgroundOperation {}
            return $syncHash
        }

        $cachedResults = @(
            [PSCustomObject]@{
                Version = '1.0.0'
                URI     = 'https://example.test/test.msi'
            }
        )

        { & ($syncHash['DisplayAppResults']) -AppResults $cachedResults } | Should -Not -Throw
        $syncHash.CurrentAppResults | Should -HaveCount 1
        $syncHash.ResultsCountLabel.Text | Should -Be 'Showing 1 of 1'
    }

    It 'Stores a LoadAppVersions callback that can register background work outside module scope' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
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

            $appsListBox = Get-MockWpfControl -Property @{ ItemsSource = @(); SelectedItem = [PSCustomObject]@{ Name = 'TestApp' } }
            $syncHash = [hashtable]::Synchronized(@{
                    AppList                = @()
                    Config                 = [PSCustomObject]@{ FavouriteApps = @(); LibraryPath = '' }
                    CurrentAppResults      = @()
                    FilterState            = @{}
                    VersionsColSavedWidths = @{}
                    VersionsListView       = Get-MockWpfControl -Property @{ Items = @(); ItemsSource = @() }
                    VersionsSortDirection  = 'Ascending'
                    VersionsSortProperty   = ''
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
                AppCountLabel         = $null
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

            $registerBackgroundOperation = {
                param(
                    [string]$Feature,
                    [string]$OperationId,
                    [System.Management.Automation.PowerShell]$PowerShellInstance,
                    [System.Management.Automation.Runspaces.Runspace]$RunspaceInstance,
                    [scriptblock]$CompletionAction,
                    [object]$CallbackState
                )
                [void]$CompletionAction
                [void]$CallbackState
                $PowerShellInstance.Dispose()
                $RunspaceInstance.Dispose()
                throw ('REGISTERED:{0}:{1}' -f $Feature, $OperationId)
            }

            Register-AppsFeature -SyncHash $syncHash -Controls $controls -RegisterBackgroundOperation $registerBackgroundOperation
            return $syncHash
        }

        { & ($syncHash['LoadAppVersions']) } | Should -Throw '*REGISTERED:Load:Evergreen*'
    }
}
