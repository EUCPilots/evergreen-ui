#Requires -Version 7.6

BeforeAll {
    $script:originalAppData = $env:APPDATA
    $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'appdata'
    $null = New-Item -Path $env:APPDATA -ItemType Directory -Force
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
}

AfterAll {
    $env:APPDATA = $script:originalAppData
    Remove-Module -Name EvergreenUI -Force -ErrorAction SilentlyContinue
}

Describe 'Intune Publish view' {
    It 'shows connection and comparison instructions until a successful comparison, including an empty result' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneComparisonInstructionText.Visibility.ToString() | Should -Be 'Visible'
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Connect to Intune'
                $state.IntuneComparisonListView.Visibility.ToString() | Should -Be 'Collapsed'
                $state.IntuneTenantId = 'tenant'
                Update-EwWorkbenchIntuneView -State $state
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Compare definitions'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntuneCompare'
                Update-EwWorkbenchIntuneView -State $state
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Comparing'
                Mock Remove-EwJob {}
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{ DefinitionRoot = 'C:\Definitions'; Items = @() })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneComparisonLoaded | Should -BeTrue
                $state.IntuneComparisonInstructionText.Visibility.ToString() | Should -Be 'Collapsed'
                $state.IntuneComparisonListView.Visibility.ToString() | Should -Be 'Visible'
                $state.IntuneInventoryViewCombo.SelectedIndex = 1
                $state.IntuneOnlyAppsListView.Visibility.ToString() | Should -Be 'Visible'
                $state.IntuneTenantId = ''
                $state.IntuneComparisonLoaded = $false
                Update-EwWorkbenchIntuneView -State $state
                $state.IntuneOnlyAppsListView.Visibility.ToString() | Should -Be 'Collapsed'
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Connect to Intune'
            }
            finally { $window.Close() }
        }
    }

    It 'restores comparison guidance after a failed initial comparison' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntuneCompare'
                Update-EwWorkbenchIntuneView -State $state
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Comparing'
                Mock Remove-EwJob {}
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Failed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Comparison failed'), 'ComparisonFailed',
                            [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                        Output = @()
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneComparisonLoaded | Should -BeFalse
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Compare definitions'
                $state.IntuneComparisonListView.Visibility.ToString() | Should -Be 'Collapsed'
            }
            finally { $window.Close() }
        }
    }

    It 'places the selection summary beside the import actions at window width <Width>' -ForEach @(
        @{ Width = 960 }
        @{ Width = 1400 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Width = $Width } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Width = $Width
                $window.Show()
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $summary = $state.IntuneSelectionSummaryText
                $summaryPosition = $summary.TranslatePoint([System.Windows.Point]::new(0, 0), $window)
                $summary.ActualWidth | Should -BeGreaterThan 0
                foreach ($button in @($state.CancelIntuneBatchButton, $state.PublishSelectedIntuneButton, $state.PublishIntuneUpdateButton)) {
                    $buttonPosition = $button.TranslatePoint([System.Windows.Point]::new(0, 0), $window)
                    ($summaryPosition.X + $summary.ActualWidth) | Should -BeLessOrEqual $buttonPosition.X
                    [Math]::Abs(($summaryPosition.Y + $summary.ActualHeight / 2) - ($buttonPosition.Y + $button.ActualHeight / 2)) | Should -BeLessOrEqual 1
                    ($buttonPosition.X + $button.ActualWidth) | Should -BeLessOrEqual $window.ActualWidth
                }
            }
            finally { $window.Close() }
        }
    }

    It 'aligns Intune inventory column headers with their cells and spaces filter labels' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonLoaded = $true
                $state.IntuneInventoryViewCombo.SelectedIndex = 1
                $item = [PSCustomObject]@{
                    IntuneDisplayName = 'App'; IntuneVersion = '1.0'; RequirementArchitecture = 'x64'; PSPackageFactoryGuid = 'guid'
                }
                $grid = $state.IntuneOnlyAppsListView
                $grid.ItemsSource = @($item)
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                foreach ($pair in @(
                        @{ Label = 'IntuneDefinitionSearchLabel'; Input = 'IntuneDefinitionSearchBox' }
                        @{ Label = 'IntuneInventoryViewLabel'; Input = 'IntuneInventoryViewCombo' }
                    )) {
                    $label = $window.FindName($pair.Label)
                    $inputControl = $window.FindName($pair.Input)
                    $labelEnd = $label.TranslatePoint([System.Windows.Point]::new($label.ActualWidth, 0), $window).X
                    $inputStart = $inputControl.TranslatePoint([System.Windows.Point]::new(0, 0), $window).X
                    ($inputStart - $labelEnd) | Should -BeGreaterOrEqual 8
                }
                $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::Column)
                $pending = [System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new()
                $pending.Push($grid)
                $headers = @{}
                while ($pending.Count -gt 0) {
                    $element = $pending.Pop()
                    if ($element -is [System.Windows.Controls.Primitives.DataGridColumnHeader] -and $null -ne $element.Column) {
                        $headers[[string]$element.Column.Header] = $element
                    }
                    for ($index = 0; $index -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($element); $index++) {
                        $pending.Push([System.Windows.Media.VisualTreeHelper]::GetChild($element, $index))
                    }
                }
                foreach ($column in $grid.Columns) {
                    $header = $headers[[string]$column.Header]
                    $header | Should -Not -BeNullOrEmpty
                    $text = $column.GetCellContent($item)
                    $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($text)
                    while ($null -ne $cell -and $cell -isnot [System.Windows.Controls.DataGridCell]) {
                        $cell = [System.Windows.Media.VisualTreeHelper]::GetParent($cell)
                    }
                    $headerX = $header.TranslatePoint([System.Windows.Point]::new(0, 0), $grid).X
                    $cellX = $cell.TranslatePoint([System.Windows.Point]::new(0, 0), $grid).X
                    [Math]::Abs($headerX - $cellX) | Should -BeLessOrEqual 1
                }
            }
            finally { $window.Close() }
        }
    }

    It 'opens and closes the inspector with <Count> matching apps' -ForEach @(
        @{ Count = 0 }
        @{ Count = 1 }
        @{ Count = 2 }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Count = $Count } {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonLoaded = $true
                $apps = @(for ($index = 0; $index -lt $Count; $index++) {
                    [PSCustomObject]@{
                        IntuneAppId = "app-$index"; DisplayName = "Imported app $index"; DisplayVersion = '1.0'
                        AllowedArchitectures = 'x64'; Role = 'Current app'; AppKind = 'Deployment app'
                        Supersedes = 'No verified predecessor'; SupersededBy = 'No verified successor'
                        SupersededAppIds = @(); SelectionLabel = "Imported app $index / 1.0"
                    }
                })
                $row = [PSCustomObject]@{
                    RowType = 'Definition'; DefinitionName = 'Definition'; Publisher = 'Publisher'; AvailableVersion = '2.0'
                    IsSelected = $false; MatchingAppCount = $Count; MatchingApps = $apps; RelationshipsVerified = $true
                    IntuneAppId = if ($Count) { 'app-0' } else { '' }
                    DeploymentBlocker = ''; UpdateBlocker = ''
                }
                $state.IntuneComparison = @($row)
                $state.IntuneComparisonListView.ItemsSource = @($row)
                $state.IntuneComparisonListView.SelectedItem = $row
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $state.IntuneDefinitionDrawer.Visibility.ToString() | Should -Be 'Visible'
                $state.IntunePredecessorCombo.Items.Count | Should -Be $Count
                $window.FindName('IntuneMatchingAppsControl').Items.Count | Should -Be $Count
                if ($Count) {
                    $state.IntunePredecessorCombo.SelectedValue | Should -Be 'app-0'
                    $window.FindName('IntuneMatchingAppsControl').Items[0].DisplayName | Should -Be 'Imported app 0'
                }
                $state.CloseIntuneDefinitionDrawerButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $state.IntuneDefinitionDrawer.Visibility.ToString() | Should -Be 'Collapsed'
                $state.IntunePredecessorCombo.Items.Count | Should -Be 0
            }
            finally { $window.Close() }
        }
    }

    It 'does not repeatedly rebuild the inspector when checked rows are rendered' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonLoaded = $true
                Update-EwWorkbenchIntuneView -State $state
                $state.InspectorUpdateCount = 0
                $originalInvoker = $state.ModuleInvoker
                $state.ModuleInvoker = {
                    param($Name, $Parameters)
                    if ($Name -eq 'Update-EwWorkbenchIntuneView') { $state.InspectorUpdateCount++; return }
                    & $originalInvoker -Name $Name -Parameters $Parameters
                }.GetNewClosure()
                $rows = @(1..100 | ForEach-Object {
                    [PSCustomObject]@{
                        RowType = 'Definition'; DefinitionName = "App $_"; IsSelected = $true
                        Publisher = 'Publisher'; AvailableVersion = '2.0'; Architecture = 'x64'; Readiness = 'Update available'; MatchingAppCount = 0
                    }
                })
                $state.IntuneComparison = $rows
                $state.IntuneComparisonListView.ItemsSource = $rows
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()
                $state.InspectorUpdateCount | Should -Be 0
            }
            finally { $window.Close() }
        }
    }

    It 'uses cached artifacts for browsing while keeping comparison in the background' {
        InModuleScope EvergreenUI {
            Mock Invoke-EwWorkbenchJob {
                & $ScriptBlock @ArgumentList
            }
            Mock Import-Module {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant' } }
            Mock Compare-EwIntuneApp { @() }
            $state = @{ Settings = @{ IntuneDefinitionsPath = 'C:\Definitions' }; IntuneTenantId = 'tenant' }
            Invoke-EwWorkbenchIntuneComparison -State $state
            Should -Invoke Invoke-EwWorkbenchJob -Exactly 1 -ParameterFilter { $Kind -eq 'IntuneCompare' }
            Should -Invoke Compare-EwIntuneApp -Exactly 1 -ParameterFilter { $DefinitionView -and -not $NoCache }
        }
    }

    It 'opens a closable inspector with all matching apps without grouping or duplicating definition rows' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $window.WindowStartupLocation = 'Manual'
                $window.Left = -10000
                $window.Top = -10000
                $window.Show()
                $window.FindName('AppsPanel').Visibility = 'Collapsed'
                $window.FindName('IntunePanel').Visibility = 'Visible'
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonLoaded = $true
                $grid = $window.FindName('IntuneComparisonListView')
                $row = [PSCustomObject]@{
                    RowType = 'Definition'; DefinitionName = 'Local name'; Publisher = 'Publisher'; AvailableVersion = '2.0'
                    IsSelected = $false; MatchingAppCount = 2; RelationshipsVerified = $true; IntuneAppId = 'current'
                    MatchingApps = @([PSCustomObject]@{ IntuneAppId = 'current'; DisplayName = 'Current app'; DisplayVersion = '2.0' }, [PSCustomObject]@{ IntuneAppId = 'old'; DisplayName = 'Earlier app'; DisplayVersion = '1.0' })
                    DeploymentBlocker = 'Already imported'; UpdateBlocker = 'Already imported'
                }
                $rows = @($row)
                $state.IntuneComparison = $rows
                $grid.ItemsSource = $rows
                $grid.SelectedItem = $row
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $window.UpdateLayout()

                $grid.Items.Count | Should -Be 1
                $state.IntuneDefinitionDrawer.Visibility.ToString() | Should -Be 'Visible'
                $window.FindName('IntuneInspectedDefinitionNameText').Text | Should -Be 'Local name'
                $window.FindName('IntuneInspectedVersionText').Text | Should -Be 'Version available to import: 2.0'
                $window.FindName('IntuneMatchingAppsControl').Items.Count | Should -Be 2
                $state.CloseIntuneDefinitionDrawerButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $state.IntuneDefinitionDrawer.Visibility.ToString() | Should -Be 'Collapsed'
                $grid.Items.Count | Should -Be 1
                $pending = [System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new()
                $pending.Push($grid.ItemContainerGenerator.ContainerFromItem($row))
                $checkBox = $null
                while ($pending.Count -gt 0) {
                    $element = $pending.Pop()
                    if ($element -is [System.Windows.Controls.CheckBox]) { $checkBox = $element; break }
                    for ($index = 0; $index -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($element); $index++) {
                        $pending.Push([System.Windows.Media.VisualTreeHelper]::GetChild($element, $index))
                    }
                }
                $checkBox | Should -Not -BeNullOrEmpty
                $checkBox.IsChecked = $true
                $row.IsSelected | Should -BeTrue
                $state.IntuneSelectionSummaryText.Text | Should -Match '1 selected: Local name'
                $state.PublishSelectedIntuneButton.IsEnabled | Should -BeFalse
                $state.IntuneDefinitionSearchBox.Text = 'Does not match'
                $grid.Items.Count | Should -Be 0
                $row.IsSelected | Should -BeTrue
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'uses one readable confirmation with explicit update effects and a verb-labelled action' {
        InModuleScope EvergreenUI {
            $selection = @(
                [PSCustomObject]@{ DefinitionName = 'Existing & Co'; ImportAsUpdate = $true; IntuneAppId = 'previous-id'; IntuneDisplayName = 'Earlier & Co'; IntuneVersion = '1.0'; AvailableVersion = '2.0'; Architecture = 'x64'; RequirementArchitecture = 'x64,arm64'; DefinitionVersion = '1.0' }
            )
            Mock Confirm-EwWorkbenchAction { $true }
            Confirm-EwWorkbenchIntuneBatch -Window ([object]::new()) -Selection $selection -TenantId 'tenant-id' |
                Should -BeTrue
            Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                $Title -eq 'Confirm Intune publishing' -and -not $DefaultYes -and
                $Message -match 'Tenant: tenant-id' -and
                $Message -match 'Existing & Co' -and
                $Message -match "supersede 'Earlier & Co', version 1.0" -and
                $Message -match 'Required for All Devices' -and
                $Message -match 'application-presence' -and $AcceptText -eq 'Import 1 update app' -and $DeclineText -eq 'Cancel' -and
                $Message -match 'Definition and Source\\Install.json files may be updated on disk'
            }
        }
    }

    It 'renders the confirmation in <Mode> mode with the <Default> default' -ForEach @(
        @{ Mode = 'Light'; Default = 'Yes' }
        @{ Mode = 'Dark'; Default = 'No' }
        @{ Mode = 'System'; Default = 'Yes' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ Mode = $Mode; Default = $Default } {
            $owner = Get-EwWorkbenchWindow
            $dialog = $null
            try {
                $owner.ThemeMode = [System.Windows.ThemeMode]::$Mode
                $owner.Show()
                $message = "Tenant: tenant & co`n`nAn <application> will change."
                $dialog = New-EwWorkbenchConfirmationDialog -Owner $owner -Title 'Confirm action' `
                    -Message $message -DefaultYes ($Default -eq 'Yes')
                $dialog.Show()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $dialog.UpdateLayout()

                $dialog.Owner | Should -Be $owner
                $dialog.ThemeMode | Should -Be $owner.ThemeMode
                $dialog.WindowStartupLocation | Should -Be ([System.Windows.WindowStartupLocation]::CenterOwner)
                $dialog.ShowInTaskbar | Should -BeFalse
                $dialog.ResizeMode | Should -Be ([System.Windows.ResizeMode]::NoResize)
                $dialog.SizeToContent | Should -Be ([System.Windows.SizeToContent]::WidthAndHeight)
                $dialog.ActualWidth | Should -BeLessThan $dialog.MaxWidth
                $dialog.ActualHeight | Should -BeLessThan 300
                $dialog.TryFindResource('ApplicationBackgroundBrush').Color |
                    Should -Be $owner.TryFindResource('ApplicationBackgroundBrush').Color
                $dialog.FindName('ConfirmationHeadingText').Text | Should -Be 'Confirm action'
                $dialog.FindName('ConfirmationMessageText').Text | Should -Be $message
                $dialog.FindName('ConfirmationYesButton').IsDefault | Should -Be ($Default -eq 'Yes')
                $dialog.FindName('ConfirmationNoButton').IsDefault | Should -Be ($Default -eq 'No')
                $dialog.FindName('ConfirmationNoButton').IsCancel | Should -BeTrue
                $dialog.FindName("Confirmation${Default}Button").Style |
                    Should -Be $dialog.TryFindResource('AccentButtonStyle')
            }
            finally {
                if ($null -ne $dialog) { $dialog.Close() }
                $owner.Close()
            }
        }
    }

    It 'keeps long confirmation details scrollable and actions visible' -Skip:($env:GITHUB_ACTIONS -eq 'true') {
        InModuleScope EvergreenUI {
            $owner = Get-EwWorkbenchWindow
            $dialog = $null
            try {
                $owner.Height = 660
                $owner.FontSize = 20
                $owner.Show()
                $message = ((1..80 | ForEach-Object { "Application $_`: $([string]('long-name' * 12))" }) -join "`n")
                $dialog = New-EwWorkbenchConfirmationDialog -Owner $owner -Title 'Confirm action' `
                    -Message $message -DefaultYes $true
                $dialog.Show()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $dialog.UpdateLayout()

                $dialog.FontSize | Should -Be 20
                $dialog.ActualWidth | Should -BeLessOrEqual $dialog.MaxWidth
                $dialog.ActualHeight | Should -BeLessOrEqual $dialog.MaxHeight
                $dialog.FindName('ConfirmationMessageText').Text | Should -Be $message
                $dialog.FindName('ConfirmationMessageText').TextWrapping | Should -Be ([System.Windows.TextWrapping]::Wrap)
                $scroll = $dialog.FindName('ConfirmationDetailsScrollViewer')
                $scroll.ScrollableHeight | Should -BeGreaterThan 0
                $scroll.ScrollToEnd()
                $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $scroll.VerticalOffset | Should -Be $scroll.ScrollableHeight
                $yes = $dialog.FindName('ConfirmationYesButton')
                $position = $yes.TranslatePoint([System.Windows.Point]::new(0, 0), $dialog)
                ($position.Y + $yes.ActualHeight) | Should -BeLessOrEqual $dialog.ActualHeight
            }
            finally {
                if ($null -ne $dialog) { $dialog.Close() }
                $owner.Close()
            }
        }
    }

    It 'returns <Accepted> for <Action> with Yes default <DefaultYes>' -ForEach @(
        @{ Action = 'Yes'; DefaultYes = $true; Accepted = $true }
        @{ Action = 'No'; DefaultYes = $true; Accepted = $false }
        @{ Action = 'Close'; DefaultYes = $true; Accepted = $false }
        @{ Action = 'Return'; DefaultYes = $true; Accepted = $true }
        @{ Action = 'Return'; DefaultYes = $false; Accepted = $false }
        @{ Action = 'Escape'; DefaultYes = $true; Accepted = $false }
    ) {
        if ($env:GITHUB_ACTIONS -eq 'true' -and $Action -in 'Return', 'Escape') {
            Set-ItResult -Skipped -Because 'Keyboard focus requires an interactive desktop.'
            return
        }
        InModuleScope EvergreenUI -Parameters @{ Action = $Action; DefaultYes = $DefaultYes; Accepted = $Accepted } {
            $owner = Get-EwWorkbenchWindow
            $observed = @{ Action = $Action; DefaultYes = $DefaultYes; InitiallyFocused = $false; VisibleAfter = $null }
            try {
                $owner.Show()
                $null = $owner.Dispatcher.BeginInvoke([action]{
                    $dialog = @($owner.OwnedWindows)[0]
                    $default = if ($observed.DefaultYes) { 'Yes' } else { 'No' }
                    $observed.InitiallyFocused = $dialog.FindName("Confirmation${default}Button").IsKeyboardFocused
                    if ($observed.Action -in 'Return', 'Escape') {
                        $key = [System.Windows.Input.Key]::Parse([System.Windows.Input.Key], $observed.Action)
                        $keyArgs = [System.Windows.Input.KeyEventArgs]::new(
                            [System.Windows.Input.Keyboard]::PrimaryDevice,
                            [System.Windows.PresentationSource]::FromVisual($dialog), 0, $key
                        )
                        $keyArgs.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
                        $null = [System.Windows.Input.InputManager]::Current.ProcessInput($keyArgs)
                    }
                    elseif ($observed.Action -in 'Yes', 'No') {
                        $button = $dialog.FindName("Confirmation$($observed.Action)Button")
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                        $provider = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
                        $provider.Invoke()
                        $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                    }
                    else { $dialog.Close() }
                    $observed.VisibleAfter = $dialog.IsVisible
                    if ($dialog.IsVisible) { $dialog.Close() }
                }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
                $result = Confirm-EwWorkbenchAction -Window $owner -Title 'Confirm action' `
                    -Message 'Proceed?' -DefaultYes $DefaultYes
                $result | Should -Be $Accepted
                if ($env:GITHUB_ACTIONS -ne 'true') { $observed.InitiallyFocused | Should -BeTrue }
                $observed.VisibleAfter | Should -BeFalse
            }
            finally { $owner.Close() }
        }
    }

    It 'requires approval before retrying Intune supersedence' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $item = [PSCustomObject]@{
                    Status = 'Supersedence failed'; TenantId = 'tenant'
                    IntuneAppId = 'new-id'; PreviousAppId = 'old-id'
                }
                $state.IntuneResults.Add($item)
                $state.IntunePublishResultsListView.SelectedItem = $item
                Mock Confirm-EwWorkbenchAction { $false }
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.RetryIntuneSupersedenceButton.RaiseEvent($click)
                Should -Invoke Confirm-EwWorkbenchAction -Exactly 1 -ParameterFilter {
                    $DefaultYes -and $Title -eq 'Confirm supersedence retry' -and
                    $Message -match 'Tenant: tenant' -and $Message -match 'New app: new-id' -and
                    $Message -match 'Previous app: old-id'
                }
                Should -Invoke Start-EwJob -Exactly 0
                Mock Confirm-EwWorkbenchAction { $true }
                $state.RetryIntuneSupersedenceButton.RaiseEvent($click)
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Retry Intune supersedence' -and
                    $ArgumentList[0] -eq 'new-id' -and $ArgumentList[1] -eq 'old-id' -and $ArgumentList[2] -eq 'tenant'
                }
            }
            finally { $window.Close() }
        }
    }

    It 'toggles the connection action only after successful sign-in and sign-out' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantIdBox.Text = 'requested-tenant'
                $state.UseIntuneDeviceCodeToggle.IsChecked = $true
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                Mock Remove-EwJob {}

                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.ConnectIntuneButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntuneConnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeFalse
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Connect to Intune' -and
                    $ArgumentList[0] -eq 'requested-tenant' -and $ArgumentList[1] -eq $true
                }

                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Succeeded = $true; AccountId = 'person@example.com'; TenantId = 'connected-tenant'
                            })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -Be 'connected-tenant'
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'person@example.com'
                $state.ConnectIntuneButton.Content | Should -Be 'Disconnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeTrue
                $state.CompareIntuneButton.IsEnabled | Should -BeTrue
                $state.IntuneComparisonLoaded | Should -BeFalse
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Compare definitions'

                $state.ConnectIntuneButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntuneDisconnect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeFalse
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter { $Name -eq 'Disconnect from Intune' }
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $false; Error = 'Disconnect failed' })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -Be 'connected-tenant'
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'person@example.com'
                $state.ConnectIntuneButton.Content | Should -Be 'Disconnect'

                $state.ConnectIntuneButton.RaiseEvent($click)
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $true; Error = '' })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -BeNullOrEmpty
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'Not connected'
                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.CompareIntuneButton.IsEnabled | Should -BeFalse
                $state.IntuneComparisonLoaded | Should -BeFalse
                $state.IntuneComparisonInstructionText.Text | Should -Match 'Connect to Intune'
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'keeps the connection action disconnected after sign-in fails' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntuneConnect'
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{ Succeeded = $false; Error = 'Sign-in failed' })
                    }
                }
                Mock Remove-EwJob {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneTenantId | Should -BeNullOrEmpty
                $state.IntuneConnectionStatusLabel.Text | Should -Be 'Not connected'
                $state.ConnectIntuneButton.Content | Should -Be 'Connect'
                $state.ConnectIntuneButton.IsEnabled | Should -BeTrue
                $state.CompareIntuneButton.IsEnabled | Should -BeFalse
            }
            finally {
                $window.Close()
            }
        }
    }

    It 'starts a confirmed batch and requests cooperative cancellation' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.NavIntune.IsChecked = $true
                $state.IntunePanel.Visibility.ToString() | Should -Be 'Visible'
                $state.IntuneTenantId = 'tenant'
                $state.IntuneComparisonRoot = 'C:\Definitions'
                $state.IntuneComparisonLoaded = $true
                $state.Settings.IntuneDefinitionsPath = 'C:\Definitions'
                $state.Settings.PackageOutputPath = 'C:\Packages'
                $row = [PSCustomObject]@{
                    DefinitionName = 'App'; DefinitionPath = 'C:\Definitions\App\App.json'
                    RowType = 'Definition'; MatchStatus = 'Matched (update required)'; IntuneAppId = 'old-id'; ImportAsUpdate = $true
                    IsSelected = $true; DeploymentBlocker = ''; UpdateBlocker = ''; MatchingApps = @(); MatchingAppCount = 0; RelationshipsVerified = $true
                }
                $unselected = $row.PSObject.Copy()
                $unselected.DefinitionName = 'Unselected'
                $unselected.DefinitionPath = 'C:\Definitions\Other\App.json'
                $unselected.IsSelected = $false
                $inventory = [PSCustomObject]@{ RowType = 'Intune'; IntuneDisplayName = 'Inventory app'; IntuneAppId = 'inventory' }
                $state.IntuneComparison = @($row, $unselected, $inventory)
                $state.IntuneComparisonListView.ItemsSource = @($row, $unselected)
                $state.IntuneComparisonListView.SelectedItem = $row
                Mock Confirm-EwWorkbenchIntuneBatch { $true }
                Mock Start-EwJob { [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = $Name } }
                $click = [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
                $state.PublishIntuneUpdateButton.RaiseEvent($click)
                $state.ActiveJobKind | Should -Be 'IntuneReview'
                Should -Invoke Confirm-EwWorkbenchIntuneBatch -Exactly 0
                Mock Remove-EwJob {}
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @(); TerminatingError = $null
                        Output = @([PSCustomObject]@{ Items = @($row); Comparison = @($row); Changed = $false })
                    }
                }
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.ActiveJobKind | Should -Be 'IntunePublish'
                $state.IntuneComparison.Count | Should -Be 3
                $state.IntuneComparisonListView.Items.Count | Should -Be 2
                $state.IntuneOnlyAppsListView.Items.Count | Should -Be 1
                ($state.IntuneComparison | Where-Object { $_.RowType -eq 'Definition' -and $_.DefinitionName -eq 'Unselected' }).IsSelected | Should -BeFalse
                $state.CancelIntuneBatchButton.IsEnabled | Should -BeTrue
                Should -Invoke Confirm-EwWorkbenchIntuneBatch -Exactly 1 -ParameterFilter {
                    $TenantId -eq 'tenant' -and $Selection[0].ImportAsUpdate
                }
                Should -Invoke Start-EwJob -Exactly 1 -ParameterFilter {
                    $Name -eq 'Build and publish Intune apps' -and $ArgumentList[0] -eq 'C:\Definitions' -and $ArgumentList[2] -eq 'C:\Packages' -and
                    $ArgumentList[3] -eq 'tenant'
                }
                $state.CancelIntuneBatchButton.RaiseEvent($click)
                $state.IntuneCancellation.IsCancellationRequested | Should -BeTrue
            }
            finally {
                if ($null -ne $state.IntuneCancellation) { $state.IntuneCancellation.Dispose() }
                $window.Close()
            }
        }
    }

    It 'preserves partial results and refreshes the comparison after a batch' {
        InModuleScope EvergreenUI {
            $window = Get-EwWorkbenchWindow
            try {
                $state = Get-EwWorkbenchState -Window $window -Settings (Get-EwSetting)
                $state.IntuneTenantId = 'tenant'
                $state.ActiveJobId = [guid]::NewGuid()
                $state.ActiveJobKind = 'IntunePublish'
                $state.IntuneCancellation = [System.Threading.CancellationTokenSource]::new()
                Mock Get-EwJob {
                    [PSCustomObject]@{
                        Id = $Id; State = 'Completed'; Progress = @(); Information = @(); Errors = @()
                        TerminatingError = $null
                        Output = @([PSCustomObject]@{
                                Name = 'App'; Status = 'Supersedence failed'; Succeeded = $false
                                IntuneAppId = 'new-id'; PreviousAppId = 'old-id'
                                ChangedPaths = @(); Error = 'link failed'
                            })
                    }
                }
                Mock Remove-EwJob {}
                Mock Invoke-EwWorkbenchIntuneComparison {}
                Invoke-EwWorkbenchJobMonitor -State $state
                $state.IntuneResults.Count | Should -Be 1
                $state.IntuneResults[0].TenantId | Should -Be 'tenant'
                $state.IntuneResults[0].IntuneAppId | Should -Be 'new-id'
                $state.IntunePublishResultsListView.SelectedItem = $state.IntuneResults[0]
                $state.RetryIntuneSupersedenceButton.IsEnabled | Should -BeTrue
                Should -Invoke Invoke-EwWorkbenchIntuneComparison -Exactly 1
            }
            finally {
                $window.Close()
            }
        }
    }
}
