#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the EvergreenUI graphical interface.

.DESCRIPTION
    Start-EvergreenUI is the single exported function of the EvergreenUI module.
    It checks that the Evergreen module is available, loads required WPF
    assemblies, builds the main window, and blocks until the window is closed.

    The function must be called from a thread with STA apartment state. In
    PowerShell 5.1 this is always the case. In PowerShell 7+ the host may be
    MTA; the function detects this and re-launches itself on an STA thread
    automatically.

.EXAMPLE
    Start-EvergreenUI

    Opens the EvergreenUI window. All interaction happens inside the GUI.

.NOTES
    - Windows only.
    - Requires the Evergreen module to be installed.
    - No parameters are accepted; all configuration is done inside the GUI and
      persisted to $env:APPDATA\EvergreenUI\config.json.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ── STA guard (PowerShell 7+ may start MTA) ──────────────────────────────────
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Verbose 'Current thread is MTA — restarting on an STA thread.'
    $sta = [powershell]::Create()
    $sta.AddScript({ Import-Module EvergreenUI; Start-EvergreenUI }) | Out-Null
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()
    $sta.Runspace = $runspace
    $sta.Invoke()
    $sta.Dispose()
    $runspace.Dispose()
    return
}

# ── Dependency check ─────────────────────────────────────────────────────────
Test-EvergreenModule

# ── Load WPF assemblies ───────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ── Load saved config ────────────────────────────────────────────────────────
$config = Get-UIConfig

# ── Shared state ─────────────────────────────────────────────────────────────
$syncHash = [hashtable]::Synchronized(@{
    Window            = $null
    LogTextBox        = $null
    LogScrollViewer   = $null
    IsRunning         = $false
    IsAdmin           = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                            [Security.Principal.WindowsBuiltInRole]::Administrator)
    AppList           = $null
    CurrentAppResults = $null
    FilterState       = @{}
    VersionsListView  = $null
    ResultsCountLabel = $null
    DownloadQueue     = [System.Collections.Generic.List[PSCustomObject]]::new()
    EvergreenVersion  = ''
    Config            = $config
})

# ── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EvergreenUI"
        MinWidth="900" MinHeight="600"
        Width="1200" Height="750"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource WindowBackgroundBrush}"
        FontFamily="Segoe UI"
        FontSize="13">

    <Window.Resources>

        <!-- ── Brushes — placeholder transparent; theme functions fill them on Loaded ── -->
        <SolidColorBrush x:Key="WindowBackgroundBrush"  Color="Transparent"/>
        <SolidColorBrush x:Key="TextPrimaryBrush"       Color="Transparent"/>
        <SolidColorBrush x:Key="TextSecondaryBrush"     Color="Transparent"/>
        <SolidColorBrush x:Key="AccentBrush"            Color="Transparent"/>
        <SolidColorBrush x:Key="AccentHoverBrush"       Color="Transparent"/>
        <SolidColorBrush x:Key="AccentLightBrush"       Color="Transparent"/>
        <SolidColorBrush x:Key="ControlBackgroundBrush" Color="Transparent"/>
        <SolidColorBrush x:Key="ControlBorderBrush"     Color="Transparent"/>
        <SolidColorBrush x:Key="ButtonForegroundBrush"  Color="Transparent"/>
        <SolidColorBrush x:Key="ToggleThumbBrush"       Color="Transparent"/>

        <!-- ── FluentButton ── -->
        <Style x:Key="FluentButton" TargetType="Button">
            <Setter Property="Background"      Value="{DynamicResource AccentBrush}"/>
            <Setter Property="Foreground"      Value="{DynamicResource ButtonForegroundBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding"         Value="16,6"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.82"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.65"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── FluentSecondaryButton ── -->
        <Style x:Key="FluentSecondaryButton" TargetType="Button" BasedOn="{StaticResource FluentButton}">
            <Setter Property="Background"      Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground"      Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush"     Value="{DynamicResource ControlBorderBrush}"/>
        </Style>

        <!-- ── FluentTextBox ── -->
        <Style x:Key="FluentTextBox" TargetType="TextBox">
            <Setter Property="Background"               Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground"               Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush"              Value="{DynamicResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness"          Value="1"/>
            <Setter Property="Padding"                  Value="8,6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="CaretBrush"               Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="SelectionBrush"           Value="{DynamicResource AccentLightBrush}"/>
        </Style>

        <!-- ── FluentListView ── -->
        <Style x:Key="FluentListView" TargetType="ListView">
            <Setter Property="Background"      Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Foreground"      Value="{DynamicResource TextPrimaryBrush}"/>
        </Style>

        <!-- ── FluentCheckBox ── -->
        <Style x:Key="FluentCheckBox" TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="Cursor"     Value="Hand"/>
        </Style>

        <!-- ── NavRailRadioButton — Fluent NavigationView item pattern ── -->
        <Style x:Key="NavRailRadioButton" TargetType="RadioButton">
            <Setter Property="GroupName"                 Value="Navigation"/>
            <Setter Property="HorizontalAlignment"       Value="Stretch"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding"                   Value="14,10"/>
            <Setter Property="Background"                Value="Transparent"/>
            <Setter Property="Foreground"                Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderThickness"           Value="0"/>
            <Setter Property="Cursor"                    Value="Hand"/>
            <Setter Property="FontSize"                  Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Margin="4,1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="3"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <!-- Active indicator bar -->
                                <Border x:Name="accent"
                                        Grid.Column="0"
                                        CornerRadius="2"
                                        Margin="0,8"
                                        Background="Transparent"/>
                                <ContentPresenter Grid.Column="1"
                                                  Margin="{TemplateBinding Padding}"
                                                  VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="bd"     Property="Background"
                                        Value="{DynamicResource AccentLightBrush}"/>
                                <Setter TargetName="accent" Property="Background"
                                        Value="{DynamicResource AccentBrush}"/>
                                <Setter Property="Foreground"
                                        Value="{DynamicResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── StatusDot — 8×8 coloured indicator ── -->
        <Style x:Key="StatusDot" TargetType="Ellipse">
            <Setter Property="Width"             Value="8"/>
            <Setter Property="Height"            Value="8"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin"            Value="0,0,5,0"/>
        </Style>

    </Window.Resources>

    <!-- ══════════════════════════════════ Root grid ════════════════════════════════════ -->
    <Grid x:Name="RootGrid">
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>                        <!-- 0  Title bar    -->
            <RowDefinition Height="*" MinHeight="200"/>         <!-- 1  Main area     -->
            <RowDefinition Height="5"/>                         <!-- 2  GridSplitter  -->
            <RowDefinition Height="182" MinHeight="32"/>        <!-- 3  Status + Log  -->
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="140"/>     <!-- Nav rail -->
            <ColumnDefinition Width="*"/>       <!-- Content  -->
        </Grid.ColumnDefinitions>

        <!-- ══ ROW 0: Title bar ══════════════════════════════════════════════════════ -->
        <Border Grid.Row="0" Grid.ColumnSpan="2"
                Background="{DynamicResource AccentBrush}">
            <DockPanel LastChildFill="False" Margin="16,0">
                <TextBlock Text="Evergreen"
                           Foreground="{DynamicResource ButtonForegroundBrush}"
                           FontSize="16" FontWeight="SemiBold"
                           VerticalAlignment="Center"
                           DockPanel.Dock="Left"/>
                <StackPanel Orientation="Horizontal"
                            VerticalAlignment="Center"
                            DockPanel.Dock="Right">
                    <Ellipse x:Name="EvergreenStatusDot"
                             Style="{StaticResource StatusDot}"
                             Fill="#88FFFFFF"/>
                    <TextBlock x:Name="EvergreenVersionText"
                               Text="Evergreen: checking..."
                               Foreground="{DynamicResource ButtonForegroundBrush}"
                               FontSize="12"
                               VerticalAlignment="Center"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- ══ ROW 1, COL 0: Navigation rail ════════════════════════════════════════ -->
        <Border Grid.Row="1" Grid.Column="0"
                BorderBrush="{DynamicResource ControlBorderBrush}"
                BorderThickness="0,0,1,0"
                Background="{DynamicResource WindowBackgroundBrush}">
            <StackPanel Margin="4,12,4,0">
                <RadioButton x:Name="NavApps"
                             Content="Apps"
                             IsChecked="True"
                             Style="{StaticResource NavRailRadioButton}"/>
                <RadioButton x:Name="NavDownload"
                             Content="Download"
                             Style="{StaticResource NavRailRadioButton}"/>
                <RadioButton x:Name="NavLibrary"
                             Content="Library"
                             Style="{StaticResource NavRailRadioButton}"/>
                <Separator Margin="14,8"
                           Background="{DynamicResource ControlBorderBrush}"/>
                <RadioButton x:Name="NavSettings"
                             Content="Settings"
                             Style="{StaticResource NavRailRadioButton}"/>
            </StackPanel>
        </Border>

        <!-- ══ ROW 1, COL 1: Content panels (visibility-swapped) ════════════════════ -->
        <Grid Grid.Row="1" Grid.Column="1">

            <!-- Apps view — Phase 4 -->
            <Grid x:Name="AppsPanel"
                  Visibility="Visible"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <TextBlock Text="Apps view — coming in Phase 4"
                           Foreground="{DynamicResource TextSecondaryBrush}"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"/>
            </Grid>

            <!-- Download view — Phase 5 -->
            <Grid x:Name="DownloadPanel"
                  Visibility="Collapsed"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <TextBlock Text="Download view — coming in Phase 5"
                           Foreground="{DynamicResource TextSecondaryBrush}"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"/>
            </Grid>

            <!-- Library view — Phase 6 -->
            <Grid x:Name="LibraryPanel"
                  Visibility="Collapsed"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <TextBlock Text="Library view — coming in Phase 6"
                           Foreground="{DynamicResource TextSecondaryBrush}"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"/>
            </Grid>

            <!-- Settings view -->
            <Grid x:Name="SettingsPanel"
                  Visibility="Collapsed"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <ScrollViewer VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="28,24" MaxWidth="520" HorizontalAlignment="Left">

                        <TextBlock Text="Settings"
                                   FontSize="20" FontWeight="SemiBold"
                                   Foreground="{DynamicResource TextPrimaryBrush}"
                                   Margin="0,0,0,20"/>

                        <!-- Download output path -->
                        <TextBlock Text="Download output path"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   Margin="0,0,0,4"/>
                        <DockPanel Margin="0,0,0,16">
                            <Button x:Name="BrowseOutputButton"
                                    Content="Browse..."
                                    DockPanel.Dock="Right"
                                    Style="{StaticResource FluentSecondaryButton}"
                                    Margin="8,0,0,0"/>
                            <TextBox x:Name="OutputPathBox"
                                     Style="{StaticResource FluentTextBox}"/>
                        </DockPanel>

                        <!-- Evergreen library path -->
                        <TextBlock Text="Evergreen library path"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   Margin="0,0,0,4"/>
                        <DockPanel Margin="0,0,0,24">
                            <Button x:Name="BrowseLibraryButton"
                                    Content="Browse..."
                                    DockPanel.Dock="Right"
                                    Style="{StaticResource FluentSecondaryButton}"
                                    Margin="8,0,0,0"/>
                            <TextBox x:Name="LibraryPathBox"
                                     Style="{StaticResource FluentTextBox}"/>
                        </DockPanel>

                        <!-- Admin / environment info -->
                        <TextBlock x:Name="AdminStatusText"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"/>

                    </StackPanel>
                </ScrollViewer>
            </Grid>

        </Grid>

        <!-- ══ ROW 2: GridSplitter ═══════════════════════════════════════════════════ -->
        <GridSplitter Grid.Row="2" Grid.ColumnSpan="2"
                      HorizontalAlignment="Stretch"
                      VerticalAlignment="Stretch"
                      Background="{DynamicResource ControlBorderBrush}"
                      ResizeDirection="Rows"
                      ResizeBehavior="PreviousAndNext"
                      ShowsPreview="False"
                      Cursor="SizeNS"/>

        <!-- ══ ROW 3: Status bar + Log panel ═════════════════════════════════════════ -->
        <DockPanel Grid.Row="3" Grid.ColumnSpan="2"
                   LastChildFill="True"
                   Background="{DynamicResource WindowBackgroundBrush}">

            <!-- Status bar — always visible, docked at top of row 3 -->
            <Border DockPanel.Dock="Top"
                    BorderBrush="{DynamicResource ControlBorderBrush}"
                    BorderThickness="0,1,0,1"
                    Height="32"
                    Background="{DynamicResource WindowBackgroundBrush}">
                <DockPanel LastChildFill="False" Margin="12,0">

                    <!-- Theme toggle (left) -->
                    <StackPanel Orientation="Horizontal"
                                VerticalAlignment="Center"
                                DockPanel.Dock="Left">
                        <ToggleButton x:Name="ThemeToggle"
                                      Width="34" Height="18"
                                      Cursor="Hand"
                                      ToolTip="Toggle dark / light theme"
                                      Focusable="False">
                            <ToggleButton.Template>
                                <ControlTemplate TargetType="ToggleButton">
                                    <Border x:Name="track"
                                            CornerRadius="9"
                                            Background="{DynamicResource ControlBorderBrush}"
                                            Width="34" Height="18">
                                        <Ellipse x:Name="thumb"
                                                 Width="12" Height="12"
                                                 Fill="{DynamicResource AccentBrush}"
                                                 HorizontalAlignment="Left"
                                                 Margin="3,0"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsChecked" Value="True">
                                            <Setter TargetName="track" Property="Background"
                                                    Value="{DynamicResource AccentBrush}"/>
                                            <Setter TargetName="thumb" Property="Fill"
                                                    Value="{DynamicResource ToggleThumbBrush}"/>
                                            <Setter TargetName="thumb" Property="HorizontalAlignment"
                                                    Value="Right"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </ToggleButton.Template>
                        </ToggleButton>
                        <TextBlock x:Name="ThemeLabel"
                                   Text="Light theme"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   VerticalAlignment="Center"
                                   Margin="7,0,0,0"
                                   FontSize="12"/>
                    </StackPanel>

                    <!-- Log controls (right) -->
                    <StackPanel Orientation="Horizontal"
                                VerticalAlignment="Center"
                                DockPanel.Dock="Right">
                        <Button x:Name="CopyLogButton"
                                Content="Copy log"
                                Style="{StaticResource FluentSecondaryButton}"
                                Padding="10,3"
                                FontSize="12"
                                Margin="0,0,6,0"/>
                        <Button x:Name="SaveLogButton"
                                Content="Save log"
                                Style="{StaticResource FluentSecondaryButton}"
                                Padding="10,3"
                                FontSize="12"
                                Margin="0,0,6,0"/>
                        <ToggleButton x:Name="LogToggleButton"
                                      Content="&#x25BE; Progress log"
                                      IsChecked="True"
                                      Padding="10,3"
                                      FontSize="12"
                                      Cursor="Hand">
                            <ToggleButton.Template>
                                <ControlTemplate TargetType="ToggleButton">
                                    <Border x:Name="bd"
                                            Background="{DynamicResource ControlBackgroundBrush}"
                                            BorderBrush="{DynamicResource ControlBorderBrush}"
                                            BorderThickness="1"
                                            CornerRadius="4"
                                            Padding="{TemplateBinding Padding}">
                                        <ContentPresenter HorizontalAlignment="Center"
                                                          VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="bd" Property="Opacity" Value="0.8"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </ToggleButton.Template>
                        </ToggleButton>
                    </StackPanel>

                </DockPanel>
            </Border>

            <!-- Log TextBox — fills remainder of row 3 -->
            <ScrollViewer x:Name="LogScrollViewer"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Auto"
                          Background="{DynamicResource ControlBackgroundBrush}">
                <TextBox x:Name="LogTextBox"
                         IsReadOnly="True"
                         AcceptsReturn="True"
                         TextWrapping="NoWrap"
                         FontFamily="Consolas"
                         FontSize="12"
                         Foreground="{DynamicResource TextPrimaryBrush}"
                         Background="{DynamicResource ControlBackgroundBrush}"
                         BorderThickness="0"
                         Padding="8,6"
                         VerticalAlignment="Top"/>
            </ScrollViewer>

        </DockPanel>

    </Grid>
</Window>
'@

# ── Parse XAML and build the window ──────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# ── Resolve named controls ────────────────────────────────────────────────────
$syncHash.Window          = $window
$syncHash.LogTextBox      = $window.FindName('LogTextBox')
$syncHash.LogScrollViewer = $window.FindName('LogScrollViewer')

$rootGrid              = $window.FindName('RootGrid')
$evergreenVersionText  = $window.FindName('EvergreenVersionText')
$evergreenStatusDot    = $window.FindName('EvergreenStatusDot')
$themeToggle           = $window.FindName('ThemeToggle')
$themeLabel            = $window.FindName('ThemeLabel')

$navApps               = $window.FindName('NavApps')
$navDownload           = $window.FindName('NavDownload')
$navLibrary            = $window.FindName('NavLibrary')
$navSettings           = $window.FindName('NavSettings')

$appsPanel             = $window.FindName('AppsPanel')
$downloadPanel         = $window.FindName('DownloadPanel')
$libraryPanel          = $window.FindName('LibraryPanel')
$settingsPanel         = $window.FindName('SettingsPanel')

$copyLogButton         = $window.FindName('CopyLogButton')
$saveLogButton         = $window.FindName('SaveLogButton')
$logToggleButton       = $window.FindName('LogToggleButton')

$outputPathBox         = $window.FindName('OutputPathBox')
$libraryPathBox        = $window.FindName('LibraryPathBox')
$browseOutputButton    = $window.FindName('BrowseOutputButton')
$browseLibraryButton   = $window.FindName('BrowseLibraryButton')
$adminStatusText       = $window.FindName('AdminStatusText')

# Log row is RowDefinitions[3]; track its height for collapse/restore
$logRowDef = $rootGrid.RowDefinitions[3]

# ── Apply initial log height from config ──────────────────────────────────────
$initialLogHeight = [Math]::Max(32, 32 + $config.LogHeight)
$logRowDef.Height = [System.Windows.GridLength]::new($initialLogHeight)

# ── Event: Window.Loaded ─────────────────────────────────────────────────────
$window.add_Loaded({
    # Apply saved theme (before any logging so colours are correct)
    if ($syncHash.Config.Theme -eq 'Dark') {
        $themeToggle.IsChecked = $true
        Set-DarkTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
    }
    else {
        $themeToggle.IsChecked = $false
        Set-LightTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
    }

    # Populate Evergreen version info in title bar
    try {
        $egModule = Get-Module -Name Evergreen | Select-Object -First 1
        if ($null -ne $egModule) {
            $syncHash.EvergreenVersion  = "v$($egModule.Version)"
            $evergreenVersionText.Text  = "Evergreen $($syncHash.EvergreenVersion)"
            $evergreenStatusDot.Fill    = [System.Windows.Media.Brushes]::LightGreen
        }
        else {
            $evergreenVersionText.Text = 'Evergreen: not loaded'
            $evergreenStatusDot.Fill   = [System.Windows.Media.Brushes]::OrangeRed
        }
    }
    catch {
        $evergreenVersionText.Text = 'Evergreen: error'
        $evergreenStatusDot.Fill   = [System.Windows.Media.Brushes]::OrangeRed
    }

    Write-UILog -SyncHash $syncHash -Message "EvergreenUI started. $($syncHash.EvergreenVersion)" -Level Info
    if ($syncHash.IsAdmin) {
        Write-UILog -SyncHash $syncHash -Message 'Running as administrator.' -Level Info
    }
})

# ── Event: Window.Closing — persist config ────────────────────────────────────
$window.add_Closing({
    try {
        $currentLogHeight = [int]$logRowDef.Height.Value - 32
        if ($currentLogHeight -gt 0) {
            $syncHash.Config.LogHeight = $currentLogHeight
        }
        $syncHash.Config.Theme = if ($themeToggle.IsChecked) { 'Dark' } else { 'Light' }
        Set-UIConfig -Config $syncHash.Config
    }
    catch {
        # Never block window close for a config-save failure
    }
})

# ── Navigation: Checked handler swaps content panels ─────────────────────────
$panelMap = @{
    NavApps     = $appsPanel
    NavDownload = $downloadPanel
    NavLibrary  = $libraryPanel
    NavSettings = $settingsPanel
}

$navCheckedHandler = {
    param($s, $e)
    foreach ($entry in $panelMap.GetEnumerator()) {
        $entry.Value.Visibility = if ($entry.Key -eq $s.Name) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
    }
}

foreach ($navBtn in @($navApps, $navDownload, $navLibrary, $navSettings)) {
    $navBtn.add_Checked($navCheckedHandler)
}

# ── Navigation: Settings panel — populate form on activation ─────────────────
$navSettings.add_Checked({
    $outputPathBox.Text  = $syncHash.Config.OutputPath
    $libraryPathBox.Text = $syncHash.Config.LibraryPath
    $adminStatusText.Text = if ($syncHash.IsAdmin) {
        'Running as administrator'
    }
    else {
        'Not running as administrator. Some operations may require elevation.'
    }
})

# ── Theme toggle ──────────────────────────────────────────────────────────────
$themeToggle.add_Click({
    if ($themeToggle.IsChecked) {
        Set-DarkTheme  -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
    }
    else {
        Set-LightTheme -Window $syncHash.Window -ThemeLabelTextBlock $themeLabel
    }
})

# ── Log panel collapse / expand ───────────────────────────────────────────────
# When expanded, the log area height (above the 32px status bar) is restored
# from config; when collapsed, row 3 drops to exactly the status bar height.
$logToggleButton.add_Click({
    if ($logToggleButton.IsChecked) {
        $restoreHeight = [Math]::Max(80, $syncHash.Config.LogHeight)
        $logRowDef.Height = [System.Windows.GridLength]::new(32 + $restoreHeight)
        $logToggleButton.Content = [char]0x25BE + ' Progress log'
    }
    else {
        # Save current displayed log height before collapsing
        $currentHeight = [int]$logRowDef.Height.Value - 32
        if ($currentHeight -gt 0) { $syncHash.Config.LogHeight = $currentHeight }
        $logRowDef.Height = [System.Windows.GridLength]::new(32)
        $logToggleButton.Content = [char]0x25B8 + ' Progress log'
    }
})

# ── Copy log ──────────────────────────────────────────────────────────────────
$copyLogButton.add_Click({
    if (-not [string]::IsNullOrEmpty($syncHash.LogTextBox.Text)) {
        [System.Windows.Clipboard]::SetText($syncHash.LogTextBox.Text)
        Write-UILog -SyncHash $syncHash -Message 'Log copied to clipboard.' -Level Info
    }
})

# ── Save log ──────────────────────────────────────────────────────────────────
$saveLogButton.add_Click({
    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Filter   = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $dlg.FileName = "EvergreenUI-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $syncHash.LogTextBox.Text |
                Set-Content -Path $dlg.FileName -Encoding UTF8 -ErrorAction Stop
            Write-UILog -SyncHash $syncHash -Message "Log saved: $($dlg.FileName)" -Level Info
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Failed to save log: $_" -Level Error
        }
    }
})

# ── Settings: Output path — Browse ───────────────────────────────────────────
$browseOutputButton.add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description  = 'Select download output folder'
    $dlg.SelectedPath = $outputPathBox.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputPathBox.Text                = $dlg.SelectedPath
        $syncHash.Config.OutputPath        = $dlg.SelectedPath
        Set-UIConfig -Config $syncHash.Config
    }
})

# ── Settings: Library path — Browse ──────────────────────────────────────────
$browseLibraryButton.add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description  = 'Select Evergreen library folder'
    $dlg.SelectedPath = $libraryPathBox.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $libraryPathBox.Text              = $dlg.SelectedPath
        $syncHash.Config.LibraryPath      = $dlg.SelectedPath
        Set-UIConfig -Config $syncHash.Config
    }
})

# ── Settings: persist path edits on focus-leave ───────────────────────────────
$outputPathBox.add_LostFocus({
    $syncHash.Config.OutputPath = $outputPathBox.Text
})
$libraryPathBox.add_LostFocus({
    $syncHash.Config.LibraryPath = $libraryPathBox.Text
})

# ── Show window (blocking) ────────────────────────────────────────────────────
[void]$window.ShowDialog()
