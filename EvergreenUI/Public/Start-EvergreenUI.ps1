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
$ProgressPreference = 'SilentlyContinue'

# ── STA guard (PowerShell 7+ may start MTA) ──────────────────────────────────
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Verbose 'Current thread is MTA - restarting on an STA thread.'
    $sta = [powershell]::Create()
    $sta.AddScript({ Import-Module EvergreenUI; Start-EvergreenUI }) | Out-Null
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
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
        Window                     = $null
        LogTextBox                 = $null
        LogScrollViewer            = $null
        IsRunning                  = $false
        AppList                    = $null
        CurrentAppResults          = $null
        FilterState                = @{}
        VersionsListView           = $null
        ResultsCountLabel          = $null
        DownloadQueueListView      = $null
        QueueCountLabel            = $null
        DownloadAllButton          = $null
        LibraryContentsListView    = $null
        LibraryDetailsListView     = $null
        LibraryStatusLabel         = $null
        LibraryUpdateButton        = $null
        LibraryData                = @()
        ActiveBackgroundOperations = [System.Collections.Generic.List[object]]::new()
        BackgroundOperationsTimer  = $null
        DownloadQueue              = [System.Collections.Generic.List[PSCustomObject]]::new()
        EvergreenVersion           = ''
        Config                     = $config
        PendingLoadTimer           = $null
        PendingLoadPS              = $null
        PendingLoadRunspace        = $null
        PendingLoadAsync           = $null
        PendingLoadAppName         = $null
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

        <!-- ── Brushes - placeholder transparent; theme functions fill them on Loaded ── -->
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
        <SolidColorBrush x:Key="SecondaryButtonBackgroundBrush" Color="Transparent"/>
        <SolidColorBrush x:Key="SecondaryButtonBorderBrush"     Color="Transparent"/>

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
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
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
            <Setter Property="Background"      Value="{DynamicResource SecondaryButtonBackgroundBrush}"/>
            <Setter Property="Foreground"      Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush"     Value="{DynamicResource SecondaryButtonBorderBrush}"/>
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
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ListViewItem">
                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                        <Setter Property="Padding"                    Value="0"/>
                        <Setter Property="Foreground"                 Value="{DynamicResource TextPrimaryBrush}"/>
                        <Setter Property="FocusVisualStyle"           Value="{x:Null}"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListViewItem">
                                    <Border x:Name="bd"
                                            Background="Transparent"
                                            Padding="{TemplateBinding Padding}">
                                        <GridViewRowPresenter Content="{TemplateBinding Content}"
                                                              HorizontalAlignment="Stretch"
                                                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="bd" Property="Background"
                                                    Value="{DynamicResource AccentLightBrush}"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="bd" Property="Background"
                                                    Value="{DynamicResource AccentLightBrush}"/>
                                            <Setter Property="Foreground"
                                                    Value="{DynamicResource AccentBrush}"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── FluentCheckBox ── -->
        <Style x:Key="FluentCheckBox" TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="Cursor"     Value="Hand"/>
        </Style>

        <!-- ── FluentComboBox ── -->
        <Style x:Key="FluentComboBox" TargetType="ComboBox">
            <Setter Property="Background"               Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground"               Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush"              Value="{DynamicResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness"          Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Padding"                  Value="8,0"/>
            <Setter Property="Cursor"                   Value="Hand"/>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="{DynamicResource ControlBackgroundBrush}"/>
                        <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
                        <Setter Property="Padding"    Value="8,6"/>
                        <Setter Property="Cursor"     Value="Hand"/>
                        <Style.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter Property="Background" Value="{DynamicResource AccentLightBrush}"/>
                                <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="{DynamicResource AccentLightBrush}"/>
                                <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </Setter.Value>
            </Setter>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="bd"
                                    Background="{DynamicResource ControlBackgroundBrush}"
                                    BorderBrush="{DynamicResource ControlBorderBrush}"
                                    BorderThickness="1"
                                    CornerRadius="4">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="28"/>
                                    </Grid.ColumnDefinitions>
                                    <ContentPresenter Grid.Column="0"
                                                      IsHitTestVisible="False"
                                                      Content="{TemplateBinding SelectionBoxItem}"
                                                      ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                      Margin="10,0,4,0"
                                                      VerticalAlignment="Center"/>
                                    <Path Grid.Column="1"
                                          Data="M 0 0 L 4 4 L 8 0"
                                          Stroke="{DynamicResource TextSecondaryBrush}"
                                          StrokeThickness="1.5"
                                          HorizontalAlignment="Center"
                                          VerticalAlignment="Center"
                                          IsHitTestVisible="False"/>
                                    <ToggleButton Grid.Column="0"
                                                  Grid.ColumnSpan="2"
                                                  Focusable="False"
                                                  Background="Transparent"
                                                  BorderThickness="0"
                                                  IsChecked="{Binding IsDropDownOpen, Mode=TwoWay,
                                                              RelativeSource={RelativeSource TemplatedParent}}"
                                                  ClickMode="Press">
                                        <ToggleButton.Template>
                                            <ControlTemplate TargetType="ToggleButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </ToggleButton.Template>
                                    </ToggleButton>
                                </Grid>
                            </Border>
                            <Popup x:Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide">
                                <Border Background="{DynamicResource ControlBackgroundBrush}"
                                        BorderBrush="{DynamicResource ControlBorderBrush}"
                                        BorderThickness="1"
                                        CornerRadius="0,0,4,4"
                                        MinWidth="{Binding ActualWidth,
                                                   RelativeSource={RelativeSource AncestorType=ComboBox}}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer SnapsToDevicePixels="True">
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="BorderBrush"
                                        Value="{DynamicResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ── NavRailRadioButton - Fluent NavigationView item pattern ── -->
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

        <!-- ── StatusDot - 8x8 coloured indicator ── -->
        <Style x:Key="StatusDot" TargetType="Ellipse">
            <Setter Property="Width"             Value="8"/>
            <Setter Property="Height"            Value="8"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin"            Value="0,0,5,0"/>
        </Style>

        <!-- ScrollBar helper: transparent repeat button -->
        <Style x:Key="ScrollBarFlatRepeatButton" TargetType="RepeatButton">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Focusable"             Value="False"/>
            <Setter Property="IsTabStop"             Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Rectangle Fill="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar helper: themed thumb -->
        <Style x:Key="ScrollBarThumbStyle" TargetType="Thumb">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop"             Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="r"
                                CornerRadius="3"
                                Background="{DynamicResource ControlBorderBrush}"
                                Opacity="0.9"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="r" Property="Background"
                                        Value="{DynamicResource AccentBrush}"/>
                                <Setter TargetName="r" Property="Opacity" Value="1"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="r" Property="Background"
                                        Value="{DynamicResource AccentBrush}"/>
                                <Setter TargetName="r" Property="Opacity" Value="1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar vertical and horizontal templates -->
        <ControlTemplate x:Key="VerticalScrollBarTemplate" TargetType="ScrollBar">
            <Border Background="{DynamicResource WindowBackgroundBrush}">
                <Track x:Name="PART_Track" IsDirectionReversed="True">
                    <Track.DecreaseRepeatButton>
                        <RepeatButton Style="{StaticResource ScrollBarFlatRepeatButton}"
                                      Command="ScrollBar.PageUpCommand"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                        <Thumb Style="{StaticResource ScrollBarThumbStyle}" Margin="2,0"/>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                        <RepeatButton Style="{StaticResource ScrollBarFlatRepeatButton}"
                                      Command="ScrollBar.PageDownCommand"/>
                    </Track.IncreaseRepeatButton>
                </Track>
            </Border>
        </ControlTemplate>

        <ControlTemplate x:Key="HorizontalScrollBarTemplate" TargetType="ScrollBar">
            <Border Background="{DynamicResource WindowBackgroundBrush}">
                <Track x:Name="PART_Track" IsDirectionReversed="False">
                    <Track.DecreaseRepeatButton>
                        <RepeatButton Style="{StaticResource ScrollBarFlatRepeatButton}"
                                      Command="ScrollBar.PageLeftCommand"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                        <Thumb Style="{StaticResource ScrollBarThumbStyle}" Margin="0,2"/>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                        <RepeatButton Style="{StaticResource ScrollBarFlatRepeatButton}"
                                      Command="ScrollBar.PageRightCommand"/>
                    </Track.IncreaseRepeatButton>
                </Track>
            </Border>
        </ControlTemplate>

        <!-- ScrollBar implicit style - applies to all scrollbars in the window -->
        <Style TargetType="ScrollBar">
            <Setter Property="OverridesDefaultStyle"    Value="True"/>
            <Setter Property="Stylus.IsFlicksEnabled"  Value="False"/>
            <Setter Property="Width"                   Value="10"/>
            <Setter Property="MinWidth"                Value="10"/>
            <Setter Property="Template"                Value="{StaticResource VerticalScrollBarTemplate}"/>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width"    Value="Auto"/>
                    <Setter Property="MinWidth" Value="0"/>
                    <Setter Property="Height"   Value="10"/>
                    <Setter Property="MinHeight" Value="10"/>
                    <Setter Property="Template" Value="{StaticResource HorizontalScrollBarTemplate}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

    </Window.Resources>

    <!-- ══════════════════════════════════ Root grid ════════════════════════════════════ -->
    <Grid x:Name="RootGrid">
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>                        <!-- 0  Title bar    -->
            <RowDefinition Height="*" MinHeight="200"/>         <!-- 1  Main area     -->
            <RowDefinition Height="5"/>                         <!-- 2  GridSplitter  -->
            <RowDefinition Height="182" MinHeight="40"/>        <!-- 3  Status + Log  -->
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="140"/>     <!-- Nav rail -->
            <ColumnDefinition Width="*"/>       <!-- Content  -->
        </Grid.ColumnDefinitions>

        <!-- ══ ROW 0: Title bar ══════════════════════════════════════════════════════ -->
        <Border Grid.Row="0" Grid.ColumnSpan="2"
                Background="{DynamicResource AccentBrush}">
            <DockPanel LastChildFill="False" Margin="16,0">
                <TextBlock Text="EvergreenUI (beta)"
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

            <!-- Apps view -->
            <Grid x:Name="AppsPanel"
                  Visibility="Visible"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <!-- App list (left) + detail (right) - search inside left column -->
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="300" MinWidth="180"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Left: Search + APPLICATIONS list -->
                    <Border Grid.Column="0"
                            BorderBrush="{DynamicResource ControlBorderBrush}"
                            BorderThickness="0,0,1,0"
                            Background="{DynamicResource WindowBackgroundBrush}">
                        <DockPanel>
                            <!-- Search bar matching list width -->
                            <Border DockPanel.Dock="Top"
                                    BorderBrush="{DynamicResource ControlBorderBrush}"
                                    BorderThickness="0,0,0,1"
                                    Padding="8,8"
                                    Background="{DynamicResource WindowBackgroundBrush}">
                                <Grid>
                                        <TextBox x:Name="AppSearchBox"
                                                 Style="{StaticResource FluentTextBox}"/>
                                        <TextBlock Text="Search applications..."
                                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                                   IsHitTestVisible="False"
                                                   Margin="10,0,0,0"
                                                   VerticalAlignment="Center"
                                                   FontSize="13">
                                            <TextBlock.Style>
                                                <Style TargetType="TextBlock">
                                                    <Setter Property="Visibility" Value="Collapsed"/>
                                                    <Style.Triggers>
                                                        <DataTrigger Binding="{Binding Text, ElementName=AppSearchBox}" Value="">
                                                            <Setter Property="Visibility" Value="Visible"/>
                                                        </DataTrigger>
                                                    </Style.Triggers>
                                                </Style>
                                            </TextBlock.Style>
                                        </TextBlock>
                                </Grid>
                            </Border>
                            <!-- APPLICATIONS header -->
                            <Border DockPanel.Dock="Top"
                                    BorderBrush="{DynamicResource ControlBorderBrush}"
                                    BorderThickness="0,0,0,1"
                                    Padding="12,8"
                                    Background="{DynamicResource ControlBackgroundBrush}">
                                <DockPanel LastChildFill="False">
                                    <TextBlock Text="APPLICATIONS"
                                               FontSize="11"
                                               FontWeight="SemiBold"
                                               Foreground="{DynamicResource TextSecondaryBrush}"
                                               VerticalAlignment="Center"
                                               DockPanel.Dock="Left"/>
                                    <TextBlock x:Name="AppCountLabel"
                                               Text=""
                                               FontSize="11"
                                               Foreground="{DynamicResource TextSecondaryBrush}"
                                               VerticalAlignment="Center"
                                               DockPanel.Dock="Right"/>
                                </DockPanel>
                            </Border>
                            <!-- Refresh apps list button pinned to bottom of sidebar -->
                            <Border DockPanel.Dock="Bottom"
                                    BorderBrush="{DynamicResource ControlBorderBrush}"
                                    BorderThickness="0,1,0,0"
                                    Padding="8,8"
                                    Background="{DynamicResource WindowBackgroundBrush}">
                                <Button x:Name="RefreshAppsButton"
                                        Content="Refresh apps list"
                                        Style="{StaticResource FluentSecondaryButton}"
                                        HorizontalAlignment="Stretch"
                                        Padding="10,6"/>
                            </Border>
                            <ListBox x:Name="AppsComboBox"
                                     BorderThickness="0"
                                     Background="{DynamicResource WindowBackgroundBrush}"
                                     Foreground="{DynamicResource TextPrimaryBrush}"
                                     SelectedValuePath="Name"
                                     VirtualizingPanel.IsVirtualizing="True"
                                     VirtualizingPanel.VirtualizationMode="Recycling"
                                     ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <TextBlock Text="{Binding FriendlyName}"
                                                   TextTrimming="CharacterEllipsis"/>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                                <ListBox.ItemContainerStyle>
                                    <Style TargetType="ListBoxItem">
                                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                        <Setter Property="Padding"                   Value="12,7"/>
                                        <Setter Property="Cursor"                    Value="Hand"/>
                                        <Setter Property="FontSize"                  Value="13"/>
                                        <Setter Property="Foreground"                Value="{DynamicResource TextPrimaryBrush}"/>
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="ListBoxItem">
                                                    <Border x:Name="bd"
                                                            Background="Transparent"
                                                            Padding="{TemplateBinding Padding}"
                                                            CornerRadius="4"
                                                            Margin="4,1">
                                                        <ContentPresenter/>
                                                    </Border>
                                                    <ControlTemplate.Triggers>
                                                        <Trigger Property="IsMouseOver" Value="True">
                                                            <Setter TargetName="bd" Property="Background"
                                                                    Value="{DynamicResource AccentLightBrush}"/>
                                                        </Trigger>
                                                        <Trigger Property="IsSelected" Value="True">
                                                            <Setter TargetName="bd" Property="Background"
                                                                    Value="{DynamicResource AccentLightBrush}"/>
                                                            <Setter Property="Foreground"
                                                                    Value="{DynamicResource AccentBrush}"/>
                                                            <Setter Property="FontWeight" Value="SemiBold"/>
                                                        </Trigger>
                                                    </ControlTemplate.Triggers>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </ListBox.ItemContainerStyle>
                            </ListBox>
                        </DockPanel>
                    </Border>

                    <!-- Right: Version detail -->
                    <Grid Grid.Column="1" Margin="14,14,14,14">

                        <!-- Empty state -->
                        <Border x:Name="AppDetailEmpty"
                                BorderThickness="1"
                                BorderBrush="{DynamicResource ControlBorderBrush}"
                                Background="{DynamicResource ControlBackgroundBrush}"
                                CornerRadius="4"
                                Visibility="Visible">
                            <TextBlock Text="Select an application to view version details"
                                       HorizontalAlignment="Center"
                                       VerticalAlignment="Center"
                                       Foreground="{DynamicResource TextSecondaryBrush}"
                                       FontSize="13"/>
                        </Border>

                        <!-- Loading state -->
                        <Border x:Name="AppDetailLoading"
                                BorderThickness="1"
                                BorderBrush="{DynamicResource ControlBorderBrush}"
                                Background="{DynamicResource ControlBackgroundBrush}"
                                CornerRadius="4"
                                Visibility="Collapsed">
                            <StackPanel HorizontalAlignment="Center"
                                        VerticalAlignment="Center"
                                        Width="360">
                                <TextBlock x:Name="AppDetailLoadingLabel"
                                           Text="Retrieving application details from Evergreen…"
                                           HorizontalAlignment="Center"
                                           TextAlignment="Center"
                                           Foreground="{DynamicResource TextPrimaryBrush}"
                                           FontSize="13"
                                           FontWeight="SemiBold"
                                           TextWrapping="Wrap"
                                           Margin="0,0,0,14"/>
                                <ProgressBar IsIndeterminate="True"
                                             Height="3"
                                             Foreground="{DynamicResource AccentBrush}"
                                             Background="{DynamicResource ControlBorderBrush}"
                                             BorderThickness="0"/>
                                <TextBlock Text="Some applications may take a moment to respond"
                                           HorizontalAlignment="Center"
                                           TextAlignment="Center"
                                           Foreground="{DynamicResource TextSecondaryBrush}"
                                           FontSize="11"
                                           Margin="0,10,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Detail panel -->
                        <Border x:Name="AppDetailContent"
                                BorderThickness="1"
                                BorderBrush="{DynamicResource ControlBorderBrush}"
                                Background="{DynamicResource ControlBackgroundBrush}"
                                CornerRadius="4"
                                Visibility="Collapsed">
                            <DockPanel>

                                <!-- Header: Refresh + APPNAME VERSION DETAILS -->
                                <Border DockPanel.Dock="Top"
                                        BorderBrush="{DynamicResource ControlBorderBrush}"
                                        BorderThickness="0,0,0,1"
                                        Padding="14,8"
                                        Background="{DynamicResource ControlBackgroundBrush}">
                                    <DockPanel LastChildFill="True">
                                        <Button x:Name="LoadAppVersionsButton"
                                                Content="Refresh"
                                                DockPanel.Dock="Left"
                                                Style="{StaticResource FluentSecondaryButton}"
                                                Padding="25,6"
                                                FontSize="12"
                                                Margin="0,0,12,0"/>
                                        <TextBlock x:Name="AppDetailTitle"
                                                   Text=""
                                                   FontSize="13"
                                                   FontWeight="Bold"
                                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                                   VerticalAlignment="Center"/>
                                    </DockPanel>
                                </Border>

                                <!-- Filters strip -->
                                <Border DockPanel.Dock="Top"
                                        BorderBrush="{DynamicResource ControlBorderBrush}"
                                        BorderThickness="0,0,0,1"
                                        Padding="12,10">
                                    <WrapPanel x:Name="FilterWrapPanel"
                                               Orientation="Horizontal"/>
                                </Border>

                                <!-- Results meta + action buttons -->
                                <DockPanel DockPanel.Dock="Top"
                                           LastChildFill="False"
                                           Margin="14,8">
                                    <TextBlock x:Name="ResultsCountLabel"
                                               Text="Showing 0 of 0"
                                               Foreground="{DynamicResource TextSecondaryBrush}"
                                               FontSize="12"
                                               VerticalAlignment="Center"
                                               DockPanel.Dock="Left"/>
                                    <StackPanel Orientation="Horizontal"
                                                DockPanel.Dock="Right">
                                        <Button x:Name="ClearFiltersButton"
                                                Content="Clear filters"
                                                Style="{StaticResource FluentSecondaryButton}"
                                                Padding="10,6"
                                                FontSize="12"
                                                Margin="0,0,6,0"/>
                                        <Button x:Name="AddToQueueButton"
                                                Content="+ Add to download queue"
                                                Style="{StaticResource FluentButton}"
                                                Padding="12,6"
                                                FontSize="12"/>
                                    </StackPanel>
                                </DockPanel>

                                <!-- Versions table -->
                                <ListView x:Name="VersionsListView"
                                          Style="{StaticResource FluentListView}"
                                          BorderBrush="{DynamicResource ControlBorderBrush}"
                                          BorderThickness="0,1,0,0"
                                          SelectionMode="Extended">
                                    <ListView.Resources>
                                        <Style TargetType="GridViewColumnHeader">
                                            <Setter Property="Background"                 Value="{DynamicResource ControlBackgroundBrush}"/>
                                            <Setter Property="Foreground"                 Value="{DynamicResource TextSecondaryBrush}"/>
                                            <Setter Property="FontSize"                   Value="11"/>
                                            <Setter Property="FontWeight"                 Value="SemiBold"/>
                                            <Setter Property="Padding"                    Value="12,6"/>
                                            <Setter Property="BorderBrush"                Value="{DynamicResource ControlBorderBrush}"/>
                                            <Setter Property="BorderThickness"            Value="0,0,1,1"/>
                                            <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                        </Style>
                                    </ListView.Resources>
                                    <ListView.View>
                                        <GridView>
                                            <GridViewColumn Header="Version"       DisplayMemberBinding="{Binding Version}"       Width="130"/>
                                            <GridViewColumn Header="Channel"       DisplayMemberBinding="{Binding Channel}"       Width="110"/>
                                            <GridViewColumn Header="Release"       DisplayMemberBinding="{Binding Release}"       Width="100"/>
                                            <GridViewColumn Header="Architecture"  DisplayMemberBinding="{Binding Architecture}"  Width="110"/>
                                            <GridViewColumn Header="Type"          DisplayMemberBinding="{Binding Type}"          Width="70"/>
                                            <GridViewColumn Header="Date"          DisplayMemberBinding="{Binding Date}"          Width="100"/>
                                            <GridViewColumn Header="Uri"           DisplayMemberBinding="{Binding URI}"           Width="460"/>
                                        </GridView>
                                    </ListView.View>
                                </ListView>

                            </DockPanel>
                        </Border>

                    </Grid>
                </Grid>
            </Grid>

            <!-- Download view - Phase 5 -->
            <Grid x:Name="DownloadPanel"
                  Visibility="Collapsed"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <Grid Margin="22,18,22,12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <DockPanel Grid.Row="0" LastChildFill="False" Margin="0,0,0,12">
                        <StackPanel DockPanel.Dock="Left">
                            <TextBlock Text="Download"
                                       FontSize="20"
                                       FontWeight="SemiBold"
                                       Foreground="{DynamicResource TextPrimaryBrush}"/>
                            <TextBlock x:Name="QueueCountLabel"
                                       Text="Queue: 0 items"
                                       Foreground="{DynamicResource TextSecondaryBrush}"
                                       Margin="0,3,0,0"/>
                        </StackPanel>

                        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button x:Name="RemoveQueueItemButton"
                                    Content="Remove selected"
                                    Style="{StaticResource FluentSecondaryButton}"
                                    Padding="10,6"
                                    Margin="0,0,6,0"/>
                            <Button x:Name="ClearQueueButton"
                                    Content="Clear queue"
                                    Style="{StaticResource FluentSecondaryButton}"
                                    Padding="10,6"
                                    Margin="0,0,6,0"/>
                            <Button x:Name="DownloadAllButton"
                                    Content="Download all"
                                    Style="{StaticResource FluentButton}"
                                    Padding="12,6"/>
                        </StackPanel>
                    </DockPanel>

                    <Border Grid.Row="1"
                            BorderThickness="1"
                            BorderBrush="{DynamicResource ControlBorderBrush}"
                            Background="{DynamicResource ControlBackgroundBrush}"
                            CornerRadius="4"
                            Padding="10">
                        <ListView x:Name="DownloadQueueListView"
                                  Style="{StaticResource FluentListView}"
                                  BorderBrush="{DynamicResource ControlBorderBrush}"
                                  BorderThickness="1"
                                  SelectionMode="Single">
                            <ListView.Resources>
                                <Style TargetType="GridViewColumnHeader">
                                    <Setter Property="Background"                 Value="{DynamicResource ControlBackgroundBrush}"/>
                                    <Setter Property="Foreground"                 Value="{DynamicResource TextSecondaryBrush}"/>
                                    <Setter Property="FontSize"                   Value="11"/>
                                    <Setter Property="FontWeight"                 Value="SemiBold"/>
                                    <Setter Property="Padding"                    Value="12,6"/>
                                    <Setter Property="BorderBrush"                Value="{DynamicResource ControlBorderBrush}"/>
                                    <Setter Property="BorderThickness"            Value="0,0,1,1"/>
                                    <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                </Style>
                            </ListView.Resources>
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="App"          DisplayMemberBinding="{Binding AppName}"       Width="180"/>
                                    <GridViewColumn Header="Version"      DisplayMemberBinding="{Binding Version}"       Width="130"/>
                                    <GridViewColumn Header="Platform"     DisplayMemberBinding="{Binding Platform}"      Width="90"/>
                                    <GridViewColumn Header="Channel"      DisplayMemberBinding="{Binding Channel}"       Width="110"/>
                                    <GridViewColumn Header="Architecture" DisplayMemberBinding="{Binding Architecture}"  Width="110"/>
                                    <GridViewColumn Header="Status"       DisplayMemberBinding="{Binding Status}"        Width="110"/>
                                    <GridViewColumn Header="Uri"          DisplayMemberBinding="{Binding Uri}"           Width="440"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </Border>

                    <TextBlock Grid.Row="2"
                               Text="Downloads are processed sequentially and in queue order."
                               Foreground="{DynamicResource TextSecondaryBrush}"
                               Margin="0,10,0,0"/>
                </Grid>
            </Grid>

            <!-- Library view - Phase 6 -->
            <Grid x:Name="LibraryPanel"
                  Visibility="Collapsed"
                  Background="{DynamicResource WindowBackgroundBrush}">
                <Grid Margin="22,18,22,12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="2*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,8,0">
                            <TextBlock Text="Library path"
                                       Foreground="{DynamicResource TextSecondaryBrush}"
                                       FontSize="12"
                                       Margin="0,0,0,4"/>
                            <TextBox x:Name="LibraryPathViewBox"
                                     Style="{StaticResource FluentTextBox}"/>
                        </StackPanel>

                        <Button Grid.Column="1"
                                x:Name="LibraryBrowseButton"
                                Content="Browse"
                                Style="{StaticResource FluentSecondaryButton}"
                                Margin="0,18,6,0"
                                Padding="10,6"/>

                        <Button Grid.Column="2"
                                x:Name="LibraryNewButton"
                                Content="New"
                                Style="{StaticResource FluentSecondaryButton}"
                                Margin="0,18,6,0"
                                Padding="10,6"/>

                        <Button Grid.Column="3"
                                x:Name="LibraryRefreshButton"
                                Content="Refresh"
                                Style="{StaticResource FluentSecondaryButton}"
                                Margin="0,18,6,0"
                                Padding="10,6"/>

                        <Button Grid.Column="4"
                                x:Name="LibraryOpenFolderButton"
                                Content="Open folder"
                                Style="{StaticResource FluentSecondaryButton}"
                                Margin="0,18,0,0"
                                Padding="10,6"/>
                    </Grid>

                    <Border Grid.Row="1"
                            BorderThickness="1"
                            BorderBrush="{DynamicResource ControlBorderBrush}"
                            Background="{DynamicResource ControlBackgroundBrush}"
                            CornerRadius="4"
                            Padding="10">
                        <DockPanel>
                            <TextBlock DockPanel.Dock="Top"
                                       Text="Library contents"
                                       FontWeight="SemiBold"
                                       Foreground="{DynamicResource TextPrimaryBrush}"
                                       Margin="0,0,0,8"/>

                            <ListView x:Name="LibraryContentsListView"
                                      Style="{StaticResource FluentListView}"
                                      BorderBrush="{DynamicResource ControlBorderBrush}"
                                      BorderThickness="1"
                                      SelectionMode="Single">
                                <ListView.Resources>
                                    <Style TargetType="GridViewColumnHeader">
                                        <Setter Property="Background"                 Value="{DynamicResource ControlBackgroundBrush}"/>
                                        <Setter Property="Foreground"                 Value="{DynamicResource TextSecondaryBrush}"/>
                                        <Setter Property="FontSize"                   Value="11"/>
                                        <Setter Property="FontWeight"                 Value="SemiBold"/>
                                        <Setter Property="Padding"                    Value="12,6"/>
                                        <Setter Property="BorderBrush"                Value="{DynamicResource ControlBorderBrush}"/>
                                        <Setter Property="BorderThickness"            Value="0,0,1,1"/>
                                        <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                    </Style>
                                </ListView.Resources>
                                <ListView.View>
                                    <GridView>
                                        <GridViewColumn Header="App"          DisplayMemberBinding="{Binding Name}"         Width="220"/>
                                        <GridViewColumn Header="Version"      DisplayMemberBinding="{Binding Version}"       Width="140"/>
                                        <GridViewColumn Header="Architecture" DisplayMemberBinding="{Binding Architecture}"  Width="100"/>
                                        <GridViewColumn Header="Path"         DisplayMemberBinding="{Binding Path}"          Width="590"/>
                                    </GridView>
                                </ListView.View>
                            </ListView>
                        </DockPanel>
                    </Border>

                    <DockPanel Grid.Row="2" Margin="0,10,0,8" LastChildFill="False">
                        <TextBlock x:Name="LibraryStatusLabel"
                                   Text="Select an app row to view versions from library."
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   VerticalAlignment="Center"
                                   DockPanel.Dock="Left"/>
                        <Button x:Name="LibraryUpdateButton"
                                Content="Update library"
                                Style="{StaticResource FluentButton}"
                                DockPanel.Dock="Right"
                                Padding="12,6"/>
                    </DockPanel>

                    <Border Grid.Row="3"
                            BorderThickness="1"
                            BorderBrush="{DynamicResource ControlBorderBrush}"
                            Background="{DynamicResource ControlBackgroundBrush}"
                            CornerRadius="4"
                            Padding="10">
                        <DockPanel>
                            <TextBlock DockPanel.Dock="Top"
                                       Text="Selected app details"
                                       FontWeight="SemiBold"
                                       Foreground="{DynamicResource TextPrimaryBrush}"
                                       Margin="0,0,0,8"/>

                            <ListView x:Name="LibraryDetailsListView"
                                      Style="{StaticResource FluentListView}"
                                      BorderBrush="{DynamicResource ControlBorderBrush}"
                                      BorderThickness="1"
                                      SelectionMode="Single">
                                <ListView.Resources>
                                    <Style TargetType="GridViewColumnHeader">
                                        <Setter Property="Background"                 Value="{DynamicResource ControlBackgroundBrush}"/>
                                        <Setter Property="Foreground"                 Value="{DynamicResource TextSecondaryBrush}"/>
                                        <Setter Property="FontSize"                   Value="11"/>
                                        <Setter Property="FontWeight"                 Value="SemiBold"/>
                                        <Setter Property="Padding"                    Value="12,6"/>
                                        <Setter Property="BorderBrush"                Value="{DynamicResource ControlBorderBrush}"/>
                                        <Setter Property="BorderThickness"            Value="0,0,1,1"/>
                                        <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                    </Style>
                                </ListView.Resources>
                                <ListView.View>
                                    <GridView>
                                        <GridViewColumn Header="Version"      DisplayMemberBinding="{Binding Version}"       Width="130"/>
                                        <GridViewColumn Header="Type"         DisplayMemberBinding="{Binding Type}"          Width="90"/>
                                        <GridViewColumn Header="Channel"      DisplayMemberBinding="{Binding Channel}"       Width="110"/>
                                        <GridViewColumn Header="Architecture" DisplayMemberBinding="{Binding Architecture}"  Width="110"/>
                                        <GridViewColumn Header="Uri"          DisplayMemberBinding="{Binding URI}"           Width="630"/>
                                    </GridView>
                                </ListView.View>
                            </ListView>
                        </DockPanel>
                    </Border>
                </Grid>
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

                        <!-- Log verbosity -->
                        <TextBlock Text="Log verbosity"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   Margin="0,0,0,4"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,16" VerticalAlignment="Center">
                            <ToggleButton x:Name="LogVerbosityToggle"
                                          Width="34" Height="18"
                                          Cursor="Hand"
                                          ToolTip="Toggle between Normal and Verbose logging"
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
                            <TextBlock x:Name="LogVerbosityLabel"
                                       Text="Normal"
                                       Foreground="{DynamicResource TextPrimaryBrush}"
                                       VerticalAlignment="Center"
                                       Margin="8,0,0,0"
                                       FontSize="13"/>
                        </StackPanel>

                        <!-- Startup view -->
                        <TextBlock Text="Startup view"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   Margin="0,0,0,4"/>
                        <ComboBox x:Name="StartupViewComboBox"
                                  Style="{StaticResource FluentComboBox}"
                                  Margin="0,0,0,24"
                                  Height="32">
                            <ComboBoxItem Content="Apps"/>
                            <ComboBoxItem Content="Download"/>
                            <ComboBoxItem Content="Library"/>
                            <ComboBoxItem Content="Settings"/>
                        </ComboBox>

                        <!-- Cache -->
                        <TextBlock Text="App version cache"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   Margin="0,0,0,4"/>
                        <TextBlock Text="Cached version data is stored locally and loaded automatically when you select an app. Clear the cache to force a fetch via Evergreen on next selection."
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   FontSize="12"
                                   TextWrapping="Wrap"
                                   Margin="0,0,0,8"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,0">
                            <Button x:Name="OpenCacheFolderButton"
                                    Content="Open cache folder"
                                    Style="{StaticResource FluentSecondaryButton}"
                                    Margin="0,0,8,0"/>
                            <Button x:Name="ClearCacheButton"
                                    Content="Clear cache"
                                    Style="{StaticResource FluentSecondaryButton}"/>
                        </StackPanel>

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

            <!-- Status bar - always visible, docked at top of row 3 -->
            <Border DockPanel.Dock="Top"
                    BorderBrush="{DynamicResource ControlBorderBrush}"
                    BorderThickness="0,1,0,1"
                    Height="40"
                    Background="{DynamicResource WindowBackgroundBrush}">
                <DockPanel LastChildFill="False" Margin="12,4">

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
                                Padding="10,6"
                                FontSize="12"
                                Margin="0,0,6,0"/>
                        <Button x:Name="SaveLogButton"
                                Content="Save log"
                                Style="{StaticResource FluentSecondaryButton}"
                                Padding="10,6"
                                FontSize="12"
                                Margin="0,0,6,0"/>
                        <ToggleButton x:Name="LogToggleButton"
                                      Content="Hide progress log"
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
                                            Padding="{TemplateBinding Padding}"
                                            TextElement.Foreground="{DynamicResource TextPrimaryBrush}">
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

            <!-- Log TextBox - fills remainder of row 3 -->
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
$syncHash.Window = $window
$syncHash.LogTextBox = $window.FindName('LogTextBox')
$syncHash.LogScrollViewer = $window.FindName('LogScrollViewer')

$rootGrid = $window.FindName('RootGrid')
$evergreenVersionText = $window.FindName('EvergreenVersionText')
$evergreenStatusDot = $window.FindName('EvergreenStatusDot')
$themeToggle = $window.FindName('ThemeToggle')
$themeLabel = $window.FindName('ThemeLabel')

$navApps = $window.FindName('NavApps')
$navDownload = $window.FindName('NavDownload')
$navLibrary = $window.FindName('NavLibrary')
$navSettings = $window.FindName('NavSettings')

$appsPanel = $window.FindName('AppsPanel')
$downloadPanel = $window.FindName('DownloadPanel')
$libraryPanel = $window.FindName('LibraryPanel')
$settingsPanel = $window.FindName('SettingsPanel')

$refreshAppsButton = $window.FindName('RefreshAppsButton')
$appSearchBox = $window.FindName('AppSearchBox')
$appsComboBox = $window.FindName('AppsComboBox')
$loadAppVersionsButton = $window.FindName('LoadAppVersionsButton')
$filterWrapPanel = $window.FindName('FilterWrapPanel')
$clearFiltersButton = $window.FindName('ClearFiltersButton')
$addToQueueButton = $window.FindName('AddToQueueButton')

$removeQueueItemButton = $window.FindName('RemoveQueueItemButton')
$clearQueueButton = $window.FindName('ClearQueueButton')

$libraryPathViewBox = $window.FindName('LibraryPathViewBox')
$libraryBrowseButton = $window.FindName('LibraryBrowseButton')
$libraryNewButton = $window.FindName('LibraryNewButton')
$libraryRefreshButton = $window.FindName('LibraryRefreshButton')
$libraryOpenFolderButton = $window.FindName('LibraryOpenFolderButton')

$syncHash.LibraryContentsListView = $window.FindName('LibraryContentsListView')
$syncHash.LibraryDetailsListView = $window.FindName('LibraryDetailsListView')
$syncHash.LibraryStatusLabel = $window.FindName('LibraryStatusLabel')
$syncHash.LibraryUpdateButton = $window.FindName('LibraryUpdateButton')

$syncHash.DownloadQueueListView = $window.FindName('DownloadQueueListView')
$syncHash.QueueCountLabel = $window.FindName('QueueCountLabel')
$syncHash.DownloadAllButton = $window.FindName('DownloadAllButton')

$syncHash.VersionsListView = $window.FindName('VersionsListView')
$syncHash.ResultsCountLabel = $window.FindName('ResultsCountLabel')
$appCountLabel = $window.FindName('AppCountLabel')
$appDetailEmpty = $window.FindName('AppDetailEmpty')
$appDetailLoading = $window.FindName('AppDetailLoading')
$appDetailLoadingLabel = $window.FindName('AppDetailLoadingLabel')
$appDetailContent = $window.FindName('AppDetailContent')
$appDetailTitle = $window.FindName('AppDetailTitle')

$copyLogButton = $window.FindName('CopyLogButton')
$saveLogButton = $window.FindName('SaveLogButton')
$logToggleButton = $window.FindName('LogToggleButton')

$outputPathBox = $window.FindName('OutputPathBox')
$libraryPathBox = $window.FindName('LibraryPathBox')
$logVerbosityToggle = $window.FindName('LogVerbosityToggle')
$logVerbosityLabel  = $window.FindName('LogVerbosityLabel')
$startupViewComboBox = $window.FindName('StartupViewComboBox')
$browseOutputButton = $window.FindName('BrowseOutputButton')
$browseLibraryButton = $window.FindName('BrowseLibraryButton')
$clearCacheButton = $window.FindName('ClearCacheButton')
$openCacheFolderButton = $window.FindName('OpenCacheFolderButton')
# Log row is RowDefinitions[3]; track its height for collapse/restore
$logRowDef = $rootGrid.RowDefinitions[3]

# Apply persisted window size with safe minimums
$window.Width = [Math]::Max(900, [double]$syncHash.Config.WindowWidth)
$window.Height = [Math]::Max(600, [double]$syncHash.Config.WindowHeight)

# ── Apps view helpers ───────────────────────────────────────────────────────
$updateAppsComboSource = {
    param([string]$SearchText = '')

    $allApps = @($syncHash.AppList)
    if ($allApps.Count -eq 0) {
        $appsComboBox.ItemsSource = @()
        $appCountLabel.Text = ''
        return
    }

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        $appsComboBox.ItemsSource = $allApps
        $appCountLabel.Text = " $($allApps.Count) of $($allApps.Count)"
        return
    }

    $needle = $SearchText.Trim()
    $filtered = $allApps | Where-Object {
        $_.Name -like "*$needle*" -or $_.FriendlyName -like "*$needle*"
    }

    $appsComboBox.ItemsSource = @($filtered)
    $appCountLabel.Text = " $(@($filtered).Count) of $($allApps.Count)"
}

$loadAppCatalog = {
    param([switch]$Force)

    $refreshAppsButton.IsEnabled = $false
    try {
        [void](Get-EvergreenAppList -SyncHash $syncHash -Force:$Force)
        & $updateAppsComboSource -SearchText $appSearchBox.Text
    }
    finally {
        $refreshAppsButton.IsEnabled = $true
    }
}

# Rebuilds the VersionsListView GridView columns to match the properties returned
# by Get-EvergreenApp for the current app. Version is always first, URI always last.
$rebuildVersionColumns = {
    param([PSObject[]]$AppResults)

    if ($null -eq $AppResults -or $AppResults.Count -eq 0) { return }

    $allProps = [string[]]$AppResults[0].PSObject.Properties.Name

    # Well-known preferred widths
    $widths = @{
        Version      = 140
        Architecture = 110
        Channel      = 130
        Release      = 100
        Platform     = 90
        Language     = 90
        Ring         = 110
        Track        = 90
        Type         = 80
        Product      = 110
        Date         = 100
        URI          = 460
    }

    # Order: Version first, URI last, everything else in declared order
    $skip = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('Version', 'URI'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $middle = $allProps | Where-Object { -not $skip.Contains($_) }
    $ordered = @(
        if ($allProps -contains 'Version') { 'Version' }
    ) + @($middle) + @(
        if ($allProps -contains 'URI') { 'URI' }
    )

    $gv = [System.Windows.Controls.GridView]::new()
    foreach ($prop in $ordered) {
        $col = [System.Windows.Controls.GridViewColumn]::new()
        $col.Header = $prop
        $col.DisplayMemberBinding = [System.Windows.Data.Binding]::new($prop)
        $col.Width = if ($widths.ContainsKey($prop)) { $widths[$prop] } else { 100 }
        [void]$gv.Columns.Add($col)
    }
    $syncHash.VersionsListView.View = $gv
}

# Returns the cache file path for a given app name, creating the cache directory if needed.
$getAppCacheFile = {
    param([string]$AppName)
    $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    Join-Path $cacheDir "$AppName.json"
}

# Populates the detail panel from a result array (used for both live and cached data).
$displayAppResults = {
    param([PSObject[]]$AppResults)
    $syncHash.CurrentAppResults = @($AppResults)
    & $rebuildVersionColumns -AppResults $syncHash.CurrentAppResults
    $filterProps = @(Get-FilterableProperties -AppResults $syncHash.CurrentAppResults)
    New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
        Invoke-FilterUpdate -SyncHash $syncHash
    }
    Invoke-FilterUpdate -SyncHash $syncHash
    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
}

$loadAppVersions = {
    $selectedApp = $appsComboBox.SelectedItem
    if ($null -eq $selectedApp) {
        Write-UILog -SyncHash $syncHash -Message 'Select an application first.' -Level Warning
        return
    }

    $appName = [string]$selectedApp.Name
    $loadAppVersionsButton.IsEnabled = $false

    # Show loading state
    $appDetailContent.Visibility     = [System.Windows.Visibility]::Collapsed
    $appDetailLoading.Visibility     = [System.Windows.Visibility]::Visible
    $appDetailLoadingLabel.Text      = "Retrieving details for $appName from Evergreen..."

    Write-UILog -SyncHash $syncHash -Message "Loading versions for $appName..." -Level Info

    $runspace = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
            param([string]$Name)
            Get-EvergreenApp -Name $Name -ErrorAction Stop
        }).AddArgument($appName)

    # Store async state in syncHash so the tick handler and cancellation logic can reach it
    $syncHash.PendingLoadPS       = $ps
    $syncHash.PendingLoadRunspace = $runspace
    $syncHash.PendingLoadAppName  = $appName
    $syncHash.PendingLoadAsync    = $ps.BeginInvoke()

    $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $syncHash.PendingLoadTimer = $pollTimer

    $pollTimer.add_Tick({
        # Guard against null (can happen if cancelled between ticks)
        if ($null -eq $syncHash.PendingLoadAsync -or -not $syncHash.PendingLoadAsync.IsCompleted) { return }

        $syncHash.PendingLoadTimer.Stop()
        $syncHash.PendingLoadTimer = $null

        # Grab refs before clearing syncHash slots
        $currentPS       = $syncHash.PendingLoadPS
        $currentRunspace = $syncHash.PendingLoadRunspace
        $currentAsync    = $syncHash.PendingLoadAsync
        $currentAppName  = $syncHash.PendingLoadAppName

        $syncHash.PendingLoadPS       = $null
        $syncHash.PendingLoadRunspace = $null
        $syncHash.PendingLoadAsync    = $null
        $syncHash.PendingLoadAppName  = $null

        try {
            $results = @($currentPS.EndInvoke($currentAsync))
            $currentPS.Dispose()
            $currentRunspace.Dispose()

            # Save results to cache
            $cachePath = & $getAppCacheFile -AppName $currentAppName
            try {
                $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding UTF8 -Force
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to write cache for ${currentAppName}: $_" -Level Warning
            }

            & $displayAppResults -AppResults $results

            Write-UILog -SyncHash $syncHash -Message "Loaded $($syncHash.CurrentAppResults.Count) versions for $currentAppName." -Level Info
        }
        catch {
            try { $currentPS.Dispose() } catch {}
            try { $currentRunspace.Dispose() } catch {}

            $syncHash.CurrentAppResults = @()
            $syncHash.VersionsListView.ItemsSource = @()
            $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
            $filterWrapPanel.Children.Clear()

            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Visible

            Write-UILog -SyncHash $syncHash -Message "Failed to load versions for ${currentAppName}: $_" -Level Error
        }
        finally {
            $loadAppVersionsButton.IsEnabled = $true
        }
    })
    $pollTimer.Start()
}

$refreshQueueView = {
    $syncHash.DownloadQueueListView.ItemsSource = $null
    $syncHash.DownloadQueueListView.ItemsSource = $syncHash.DownloadQueue
    $syncHash.DownloadQueueListView.Items.Refresh()

    $pending = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
    $done = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
    $failed = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
    $total = $syncHash.DownloadQueue.Count
    $syncHash.QueueCountLabel.Text = "Queue: $total items (Pending: $pending, Done: $done, Failed: $failed)"
}

$normalizeDirectoryPath = {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ''
    }

    return $PathValue.Trim().Trim('"')
}

$registerBackgroundOperation = {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.Management.Automation.PowerShell]$PowerShellInstance,
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.Runspace]$RunspaceInstance,
        [Parameter(Mandatory)]$AsyncResult
    )

    $operation = [PSCustomObject]@{
        Name       = $Name
        PowerShell = $PowerShellInstance
        Runspace   = $RunspaceInstance
        Async      = $AsyncResult
    }

    $syncHash.ActiveBackgroundOperations.Add($operation)

    if ($null -eq $syncHash.BackgroundOperationsTimer) {
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.add_Tick({
                $completed = @($syncHash.ActiveBackgroundOperations | Where-Object { $_.Async.IsCompleted })
                foreach ($op in $completed) {
                    try {
                        [void]$op.PowerShell.EndInvoke($op.Async)
                    }
                    catch {
                        Write-UILog -SyncHash $syncHash -Message "Background operation '$($op.Name)' completed with error: $_" -Level Error
                    }
                    finally {
                        try { $op.PowerShell.Dispose() } catch {}
                        try { $op.Runspace.Dispose() } catch {}
                        [void]$syncHash.ActiveBackgroundOperations.Remove($op)
                    }
                }

                if ($syncHash.ActiveBackgroundOperations.Count -eq 0) {
                    $syncHash.BackgroundOperationsTimer.Stop()
                }
            })
        $syncHash.BackgroundOperationsTimer = $timer
    }

    if (-not $syncHash.BackgroundOperationsTimer.IsEnabled) {
        $syncHash.BackgroundOperationsTimer.Start()
    }
}

$startQueueDownload = {
    if ($syncHash.IsRunning) {
        Write-UILog -SyncHash $syncHash -Message 'A queue operation is already running.' -Level Warning
        return
    }

    if ($syncHash.DownloadQueue.Count -eq 0) {
        Write-UILog -SyncHash $syncHash -Message 'Queue is empty. Add items from Apps view first.' -Level Warning
        return
    }

    $outputPath = & $normalizeDirectoryPath -PathValue $syncHash.Config.OutputPath
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        Write-UILog -SyncHash $syncHash -Message 'Set a download output path in Settings before starting queue downloads.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $outputPath -PathType Container)) {
        try {
            [void](New-Item -Path $outputPath -ItemType Directory -Force -ErrorAction Stop)
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Could not create output path '$outputPath': $_" -Level Error
            return
        }
    }

    $syncHash.Config.OutputPath = $outputPath
    $outputPathBox.Text = $outputPath
    Set-UIConfig -Config $syncHash.Config

    $syncHash.IsRunning = $true
    $syncHash.DownloadAllButton.IsEnabled = $false

    $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
    $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
    $invokeDownloadPath = Join-Path -Path $privateRoot -ChildPath 'Invoke-AppDownload.ps1'

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param(
                [string]$WriteUILogPath,
                [string]$InvokeDownloadPath
            )

            . $WriteUILogPath
            . $InvokeDownloadPath

            try {
                Import-Module Evergreen -ErrorAction Stop | Out-Null
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to import Evergreen in background runspace: $_" -Level Error
            }

            try {
                Write-UILog -SyncHash $syncHash -Message 'Starting queue download run (sequential).' -Level Info

                foreach ($item in @($syncHash.DownloadQueue)) {
                    if ($item.Status -eq 'Done') { continue }
                    Invoke-AppDownload -SyncHash $syncHash -QueueItem $item
                }

                Write-UILog -SyncHash $syncHash -Message 'Queue download run finished.' -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Queue download run failed: $_" -Level Error
            }
            finally {
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $syncHash.IsRunning = $false
                        if ($null -ne $syncHash.DownloadAllButton) {
                            $syncHash.DownloadAllButton.IsEnabled = $true
                        }
                        if ($null -ne $syncHash.DownloadQueueListView) {
                            $syncHash.DownloadQueueListView.Items.Refresh()
                        }
                        if ($null -ne $syncHash.QueueCountLabel) {
                            $pending = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Pending' }).Count
                            $done = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Done' }).Count
                            $failed = @($syncHash.DownloadQueue | Where-Object { $_.Status -eq 'Failed' }).Count
                            $total = $syncHash.DownloadQueue.Count
                            $syncHash.QueueCountLabel.Text = "Queue: $total items (Pending: $pending, Done: $done, Failed: $failed)"
                        }
                    }, 'Normal')
            }
        }).AddArgument($writeUILogPath).AddArgument($invokeDownloadPath)

    $async = $ps.BeginInvoke()
    & $registerBackgroundOperation -Name 'QueueDownload' -PowerShellInstance $ps -RunspaceInstance $rs -AsyncResult $async
}

$getLibraryItemName = {
    param([PSObject]$Item)
    if ($null -eq $Item) { return '' }

    foreach ($candidate in @('Name', 'AppName', 'Application', 'Product')) {
        if ($Item.PSObject.Properties.Name -contains $candidate -and -not [string]::IsNullOrWhiteSpace([string]$Item.$candidate)) {
            return [string]$Item.$candidate
        }
    }

    return [string]$Item
}

$refreshLibraryView = {
    $path = $libraryPathViewBox.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        $syncHash.LibraryStatusLabel.Text = 'Set a library path to load library contents.'
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        return
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $syncHash.LibraryStatusLabel.Text = "Library path does not exist: $path"
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        return
    }

    try {
        $syncHash.Config.LibraryPath = $path
        Set-UIConfig -Config $syncHash.Config

        $items = @()
        $libraryObj = Get-EvergreenLibrary -Path $path -ErrorAction Stop
        $inventory = if ($libraryObj.PSObject.Properties.Name -contains 'Inventory') {
            @($libraryObj.Inventory)
        } else {
            @($libraryObj)
        }

        foreach ($entry in $inventory) {
            $appName = if ($entry.PSObject.Properties.Name -contains 'ApplicationName') {
                [string]$entry.ApplicationName
            } else {
                & $getLibraryItemName -Item $entry
            }
            $versions = if ($entry.PSObject.Properties.Name -contains 'Versions') { $entry.Versions } else { $null }
            $version  = if ($null -ne $versions -and $versions.PSObject.Properties.Name -contains 'Version') {
                [string]$versions.Version
            } else { '' }
            $arch = if ($null -ne $versions -and $versions.PSObject.Properties.Name -contains 'Architecture') {
                [string]$versions.Architecture
            } else { '' }
            $itemPath = if ($null -ne $versions -and $versions.PSObject.Properties.Name -contains 'Path') {
                [string]$versions.Path
            } else { '' }

            $items += [PSCustomObject]@{
                Name         = $appName
                Version      = $version
                Architecture = $arch
                Path         = $itemPath
                SourceItem   = $entry
            }
        }

        $syncHash.LibraryData = @($items)
        $syncHash.LibraryContentsListView.ItemsSource = $syncHash.LibraryData
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = "Loaded $($syncHash.LibraryData.Count) library apps."
        Write-UILog -SyncHash $syncHash -Message "Library loaded from $path ($($syncHash.LibraryData.Count) apps)." -Level Info
    }
    catch {
        $syncHash.LibraryData = @()
        $syncHash.LibraryContentsListView.ItemsSource = @()
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = 'Failed to load library.'
        Write-UILog -SyncHash $syncHash -Message "Failed to load library: $_" -Level Error
    }
}
$syncHash.RefreshLibraryView = $refreshLibraryView

$loadLibraryAppDetails = {
    param([PSObject]$SelectedLibraryItem)

    if ($null -eq $SelectedLibraryItem) {
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        return
    }

    $appName = [string]$SelectedLibraryItem.Name
    $versions = $null
    if ($SelectedLibraryItem.PSObject.Properties.Name -contains 'SourceItem' -and
        $null -ne $SelectedLibraryItem.SourceItem -and
        $SelectedLibraryItem.SourceItem.PSObject.Properties.Name -contains 'Versions') {
        $versions = $SelectedLibraryItem.SourceItem.Versions
    }

    if ($null -eq $versions) {
        $syncHash.LibraryDetailsListView.ItemsSource = @()
        $syncHash.LibraryStatusLabel.Text = "No version details found for $appName."
        return
    }

    $syncHash.LibraryDetailsListView.ItemsSource = @($versions)
    $syncHash.LibraryStatusLabel.Text = "Details loaded for $appName."
}

$startLibraryUpdate = {
    if ($syncHash.IsRunning) {
        Write-UILog -SyncHash $syncHash -Message 'Another operation is currently running.' -Level Warning
        return
    }

    $path = $libraryPathViewBox.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-UILog -SyncHash $syncHash -Message 'Set a library path before updating.' -Level Warning
        return
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-UILog -SyncHash $syncHash -Message "Library path does not exist: $path" -Level Error
        return
    }

    $syncHash.Config.LibraryPath = $path
    Set-UIConfig -Config $syncHash.Config

    $syncHash.IsRunning = $true
    $syncHash.LibraryUpdateButton.IsEnabled = $false

    $privateRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Private'
    $writeUILogPath = Join-Path -Path $privateRoot -ChildPath 'Write-UILog.ps1'
    $invokeLibraryUpdatePath = Join-Path -Path $privateRoot -ChildPath 'Invoke-LibraryUpdate.ps1'

    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
            param(
                [string]$WriteUILogPath,
                [string]$InvokeLibraryUpdatePath
            )

            . $WriteUILogPath
            . $InvokeLibraryUpdatePath

            try {
                Import-Module Evergreen -ErrorAction Stop | Out-Null
                Invoke-LibraryUpdate -SyncHash $syncHash
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Library update run failed: $_" -Level Error
            }
            finally {
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $syncHash.IsRunning = $false
                        if ($null -ne $syncHash.LibraryUpdateButton) {
                            $syncHash.LibraryUpdateButton.IsEnabled = $true
                        }
                        & $syncHash.RefreshLibraryView
                    }, 'Normal')
            }
        }).AddArgument($writeUILogPath).AddArgument($invokeLibraryUpdatePath)

    $async = $ps.BeginInvoke()
    & $registerBackgroundOperation -Name 'LibraryUpdate' -PowerShellInstance $ps -RunspaceInstance $rs -AsyncResult $async
}

# ── Apply initial log height from config ──────────────────────────────────────
$initialLogHeight = [Math]::Max(40, 40 + $config.LogHeight)
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
                $syncHash.EvergreenVersion = "v$($egModule.Version)"
                $evergreenVersionText.Text = "Evergreen $($syncHash.EvergreenVersion)"
                $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::LightGreen
            }
            else {
                $evergreenVersionText.Text = 'Evergreen: not loaded'
                $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
            }
        }
        catch {
            $evergreenVersionText.Text = 'Evergreen: error'
            $evergreenStatusDot.Fill = [System.Windows.Media.Brushes]::OrangeRed
        }

        Write-UILog -SyncHash $syncHash -Message "EvergreenUI started. $($syncHash.EvergreenVersion)" -Level Info

        & $loadAppCatalog

        if (-not [string]::IsNullOrWhiteSpace($syncHash.Config.LastAppName)) {
            $savedApp = @($syncHash.AppList | Where-Object { $_.Name -eq $syncHash.Config.LastAppName } | Select-Object -First 1)
            if ($savedApp.Count -gt 0) {
                $appsComboBox.SelectedItem = $savedApp[0]
                $appsComboBox.ScrollIntoView($savedApp[0])
            }
        }

        & $refreshQueueView
        $libraryPathViewBox.Text = $syncHash.Config.LibraryPath

        switch ([string]$syncHash.Config.StartupView) {
            'Download' {
                $navDownload.IsChecked = $true
            }
            'Library' {
                $navLibrary.IsChecked = $true
            }
            'Settings' {
                $navSettings.IsChecked = $true
            }
            default {
                $navApps.IsChecked = $true
            }
        }
    })

# ── Event: Window.Closing - persist config ────────────────────────────────────
$window.add_Closing({
        try {
            $currentLogHeight = [int]$logRowDef.Height.Value - 40
            if ($currentLogHeight -gt 0) {
                $syncHash.Config.LogHeight = $currentLogHeight
            }
            $syncHash.Config.Theme = if ($themeToggle.IsChecked) { 'Dark' } else { 'Light' }
            $syncHash.Config.WindowWidth = [int]$window.Width
            $syncHash.Config.WindowHeight = [int]$window.Height
            $syncHash.Config.LastAppName = if ($null -ne $appsComboBox.SelectedItem) { [string]$appsComboBox.SelectedItem.Name } else { '' }

            $syncHash.Config.StartupView = if ($navDownload.IsChecked) {
                'Download'
            }
            elseif ($navLibrary.IsChecked) {
                'Library'
            }
            elseif ($navSettings.IsChecked) {
                'Settings'
            }
            else {
                'Apps'
            }

            Set-UIConfig -Config $syncHash.Config

            if ($null -ne $syncHash.BackgroundOperationsTimer -and $syncHash.BackgroundOperationsTimer.IsEnabled) {
                $syncHash.BackgroundOperationsTimer.Stop()
            }

            foreach ($op in @($syncHash.ActiveBackgroundOperations)) {
                try { $op.PowerShell.Stop() } catch {}
                try { $op.PowerShell.Dispose() } catch {}
                try { $op.Runspace.Dispose() } catch {}
            }
            $syncHash.ActiveBackgroundOperations.Clear()
        }
        catch {
            # Never block window close for a config-save failure
        }
    })

# ── Keyboard shortcuts (Phase 8 polish) ─────────────────────────────────────
# Ctrl+F: focus app search
# Ctrl+,: open settings
# Ctrl+D: start queue download (when Download view active)
# Ctrl+U: start library update (when Library view active)
# Ctrl+L: toggle log panel
# F5: refresh current active view
$window.add_PreviewKeyDown({
        param($sender, $e)

        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $ctrl = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0

        if ($e.Key -eq [System.Windows.Input.Key]::F5) {
            if ($navApps.IsChecked) {
                & $loadAppCatalog -Force
            }
            elseif ($navDownload.IsChecked) {
                & $refreshQueueView
            }
            elseif ($navLibrary.IsChecked) {
                & $refreshLibraryView
            }
            $e.Handled = $true
            return
        }

        if (-not $ctrl) {
            return
        }

        switch ($e.Key) {
            ([System.Windows.Input.Key]::F) {
                $navApps.IsChecked = $true
                [void]$appSearchBox.Focus()
                $appSearchBox.SelectAll()
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::OemComma) {
                $navSettings.IsChecked = $true
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::D) {
                if ($navDownload.IsChecked) {
                    & $startQueueDownload
                    $e.Handled = $true
                }
            }
            ([System.Windows.Input.Key]::U) {
                if ($navLibrary.IsChecked) {
                    & $startLibraryUpdate
                    $e.Handled = $true
                }
            }
            ([System.Windows.Input.Key]::L) {
                $logToggleButton.IsChecked = -not $logToggleButton.IsChecked
                $logToggleButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $e.Handled = $true
            }
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

$navApps.add_Checked({
        if ($null -eq $syncHash.AppList -or $syncHash.AppList.Count -eq 0) {
            & $loadAppCatalog
        }
    })

$navDownload.add_Checked({
        & $refreshQueueView
    })

$navLibrary.add_Checked({
        if ([string]::IsNullOrWhiteSpace($libraryPathViewBox.Text)) {
            $libraryPathViewBox.Text = $syncHash.Config.LibraryPath
        }
    })

$refreshAppsButton.add_Click({
        Write-UILog -SyncHash $syncHash -Message 'Refreshing Evergreen app catalog...' -Level Info
        & $loadAppCatalog -Force
    })

$appSearchBox.add_TextChanged({
        & $updateAppsComboSource -SearchText $appSearchBox.Text
    })

$loadAppVersionsButton.add_Click({
        & $loadAppVersions
    })

$appsComboBox.add_SelectionChanged({
        # Cancel any in-progress version load before starting a new one
        if ($null -ne $syncHash.PendingLoadTimer -and $syncHash.PendingLoadTimer.IsEnabled) {
            $syncHash.PendingLoadTimer.Stop()
            $syncHash.PendingLoadTimer = $null
        }
        if ($null -ne $syncHash.PendingLoadPS) {
            try { $syncHash.PendingLoadPS.Stop() } catch {}
            try { $syncHash.PendingLoadPS.Dispose() } catch {}
            $syncHash.PendingLoadPS = $null
        }
        if ($null -ne $syncHash.PendingLoadRunspace) {
            try { $syncHash.PendingLoadRunspace.Dispose() } catch {}
            $syncHash.PendingLoadRunspace = $null
        }
        $syncHash.PendingLoadAsync   = $null
        $syncHash.PendingLoadAppName = $null

        $syncHash.CurrentAppResults = @()
        $syncHash.VersionsListView.ItemsSource = @()
        $syncHash.ResultsCountLabel.Text = 'Showing 0 of 0'
        $filterWrapPanel.Children.Clear()
        $syncHash.FilterState = @{}

        $selectedApp = $appsComboBox.SelectedItem
        if ($null -ne $selectedApp) {
            $appDetailTitle.Text = "$($selectedApp.Name) Version Details"

            # Load from cache if available; otherwise show the panel empty (user clicks Refresh)
            $cachePath = & $getAppCacheFile -AppName $selectedApp.Name
            if (Test-Path -LiteralPath $cachePath) {
                try {
                    $cachedResults = @(Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json)
                    Write-UILog -SyncHash $syncHash -Message "Loaded $($cachedResults.Count) cached versions for $($selectedApp.Name)." -Level Info
                    & $displayAppResults -AppResults $cachedResults
                }
                catch {
                    Write-UILog -SyncHash $syncHash -Message "Cache read failed for $($selectedApp.Name), click Refresh to load: $_" -Level Warning
                    $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Collapsed
                    $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                    $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
                }
            }
            else {
                $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Collapsed
                $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
                $appDetailContent.Visibility = [System.Windows.Visibility]::Visible
            }
        }
        else {
            $appDetailEmpty.Visibility   = [System.Windows.Visibility]::Visible
            $appDetailContent.Visibility = [System.Windows.Visibility]::Collapsed
            $appDetailLoading.Visibility = [System.Windows.Visibility]::Collapsed
        }
    })

$clearFiltersButton.add_Click({
        if ($null -eq $syncHash.CurrentAppResults -or $syncHash.CurrentAppResults.Count -eq 0) {
            return
        }

        $filterProps = Get-FilterableProperties -AppResults $syncHash.CurrentAppResults
        New-FilterPanel -FilterProperties $filterProps -WrapPanel $filterWrapPanel -SyncHash $syncHash -OnChangeCallback {
            Invoke-FilterUpdate -SyncHash $syncHash
        }
        Invoke-FilterUpdate -SyncHash $syncHash
    })

$addToQueueButton.add_Click({
        $selectedApp = $appsComboBox.SelectedItem
        $selectedVersions = @($syncHash.VersionsListView.SelectedItems)

        if ($null -eq $selectedApp -or $selectedVersions.Count -eq 0) {
            Write-UILog -SyncHash $syncHash -Message 'Select one or more version rows before adding to queue.' -Level Warning
            return
        }

        foreach ($selectedVersion in $selectedVersions) {
            $queueItem = [PSCustomObject]@{
                AppName      = [string]$selectedApp.Name
                Version      = [string]$selectedVersion.Version
                Platform     = if ($selectedVersion.PSObject.Properties.Name -contains 'Platform') { [string]$selectedVersion.Platform } else { '' }
                Architecture = if ($selectedVersion.PSObject.Properties.Name -contains 'Architecture') { [string]$selectedVersion.Architecture } else { '' }
                Channel      = if ($selectedVersion.PSObject.Properties.Name -contains 'Channel') { [string]$selectedVersion.Channel } else { '' }
                Uri          = if ($selectedVersion.PSObject.Properties.Name -contains 'URI') { [string]$selectedVersion.URI } else { '' }
                Status       = 'Pending'
            }
            $syncHash.DownloadQueue.Add($queueItem)
            Write-UILog -SyncHash $syncHash -Message "Queued: $($queueItem.AppName) $($queueItem.Version)" -Level Info
        }
        & $refreshQueueView
    })

$removeQueueItemButton.add_Click({
        if ($syncHash.IsRunning) {
            Write-UILog -SyncHash $syncHash -Message 'Cannot remove queue items while downloads are running.' -Level Warning
            return
        }

        $selectedQueueItem = $syncHash.DownloadQueueListView.SelectedItem
        if ($null -eq $selectedQueueItem) {
            Write-UILog -SyncHash $syncHash -Message 'Select one queue item to remove.' -Level Warning
            return
        }

        [void]$syncHash.DownloadQueue.Remove($selectedQueueItem)
        Write-UILog -SyncHash $syncHash -Message 'Removed selected item from queue.' -Level Info
        & $refreshQueueView
    })

$clearQueueButton.add_Click({
        if ($syncHash.IsRunning) {
            Write-UILog -SyncHash $syncHash -Message 'Cannot clear queue while downloads are running.' -Level Warning
            return
        }

        $syncHash.DownloadQueue.Clear()
        Write-UILog -SyncHash $syncHash -Message 'Queue cleared.' -Level Info
        & $refreshQueueView
    })

$syncHash.DownloadAllButton.add_Click({
        & $startQueueDownload
    })

$libraryRefreshButton.add_Click({
        & $refreshLibraryView
    })

$libraryBrowseButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Evergreen library folder'
        $dlg.SelectedPath = $libraryPathViewBox.Text
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $libraryPathViewBox.Text = $dlg.SelectedPath
            $syncHash.Config.LibraryPath = $dlg.SelectedPath
            Set-UIConfig -Config $syncHash.Config
            & $refreshLibraryView
        }
    })

$libraryNewButton.add_Click({
        $path = $libraryPathViewBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-UILog -SyncHash $syncHash -Message 'Set a library path before creating a new library.' -Level Warning
            return
        }

        try {
            New-EvergreenLibrary -Path $path -ErrorAction Stop | Out-Null
            Write-UILog -SyncHash $syncHash -Message "Created Evergreen library: $path" -Level Info
            $syncHash.Config.LibraryPath = $path
            Set-UIConfig -Config $syncHash.Config
            & $refreshLibraryView
        }
        catch {
            Write-UILog -SyncHash $syncHash -Message "Failed to create library: $_" -Level Error
        }
    })

$libraryOpenFolderButton.add_Click({
        $path = $libraryPathViewBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            return
        }

        if (Test-Path -LiteralPath $path -PathType Container) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $path | Out-Null
        }
        else {
            Write-UILog -SyncHash $syncHash -Message "Library path does not exist: $path" -Level Warning
        }
    })

$syncHash.LibraryUpdateButton.add_Click({
        & $startLibraryUpdate
    })

$syncHash.LibraryContentsListView.add_MouseDoubleClick({
        $selected = $syncHash.LibraryContentsListView.SelectedItem
        & $loadLibraryAppDetails -SelectedLibraryItem $selected
    })

$syncHash.LibraryContentsListView.add_SelectionChanged({
        $selected = $syncHash.LibraryContentsListView.SelectedItem
        if ($null -eq $selected) {
            $syncHash.LibraryDetailsListView.ItemsSource = @()
            return
        }
        & $loadLibraryAppDetails -SelectedLibraryItem $selected
    })

$libraryPathViewBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $libraryPathViewBox.Text
        $libraryPathViewBox.Text = $normalised
        $syncHash.Config.LibraryPath = $normalised
        $libraryPathBox.Text = $normalised
        Set-UIConfig -Config $syncHash.Config
    })

$logVerbosityToggle.add_Click({
        $verbosity = if ($logVerbosityToggle.IsChecked) { 'Verbose' } else { 'Normal' }
        $logVerbosityLabel.Text = $verbosity
        $syncHash.Config.LogVerbosity = $verbosity
        Set-UIConfig -Config $syncHash.Config
    })

$startupViewComboBox.add_SelectionChanged({
        $item = $startupViewComboBox.SelectedItem
        if ($null -eq $item) { return }

        $selected = [string]$item.Content
        if ([string]::IsNullOrWhiteSpace($selected)) {
            $selected = 'Apps'
        }

        $syncHash.Config.StartupView = $selected
        Set-UIConfig -Config $syncHash.Config
    })

# ── Navigation: Settings panel - populate form on activation ─────────────────
$navSettings.add_Checked({
        $outputPathBox.Text = $syncHash.Config.OutputPath
        $libraryPathBox.Text = $syncHash.Config.LibraryPath

        $desiredVerbosity = [string]$syncHash.Config.LogVerbosity
        $logVerbosityToggle.IsChecked = ($desiredVerbosity -eq 'Verbose')
        $logVerbosityLabel.Text = if ($desiredVerbosity -eq 'Verbose') { 'Verbose' } else { 'Normal' }

        switch ([string]$syncHash.Config.StartupView) {
            'Download' { $startupViewComboBox.SelectedIndex = 1 }
            'Library' { $startupViewComboBox.SelectedIndex = 2 }
            'Settings' { $startupViewComboBox.SelectedIndex = 3 }
            default { $startupViewComboBox.SelectedIndex = 0 }
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

        $syncHash.Config.Theme = if ($themeToggle.IsChecked) { 'Dark' } else { 'Light' }
        Set-UIConfig -Config $syncHash.Config
    })

# ── Log panel collapse / expand ───────────────────────────────────────────────
# When expanded, the log area height (above the 32px status bar) is restored
# from config; when collapsed, row 3 drops to exactly the status bar height.
$logToggleButton.add_Click({
        if ($logToggleButton.IsChecked) {
            $restoreHeight = [Math]::Max(80, $syncHash.Config.LogHeight)
            $logRowDef.Height = [System.Windows.GridLength]::new(40 + $restoreHeight)
            $logToggleButton.Content = 'Hide progress log'
        }
        else {
            # Save current displayed log height before collapsing
            $currentHeight = [int]$logRowDef.Height.Value - 40
            if ($currentHeight -gt 0) { $syncHash.Config.LogHeight = $currentHeight }
            $logRowDef.Height = [System.Windows.GridLength]::new(40)
            $logToggleButton.Content = 'Show progress log'
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
        $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
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

# ── Settings: Output path - Browse ───────────────────────────────────────────
$browseOutputButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select download output folder'
        $dlg.SelectedPath = $outputPathBox.Text
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
            $outputPathBox.Text = $normalised
            $syncHash.Config.OutputPath = $normalised
            Set-UIConfig -Config $syncHash.Config
        }
    })

# ── Settings: Library path - Browse ──────────────────────────────────────────
$browseLibraryButton.add_Click({
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Select Evergreen library folder'
        $dlg.SelectedPath = $libraryPathBox.Text
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $normalised = & $normalizeDirectoryPath -PathValue $dlg.SelectedPath
            $libraryPathBox.Text = $normalised
            $libraryPathViewBox.Text = $normalised
            $syncHash.Config.LibraryPath = $normalised
            Set-UIConfig -Config $syncHash.Config
            & $refreshLibraryView
        }
    })

# ── Settings: Open cache folder ─────────────────────────────────────────
$openCacheFolderButton.add_Click({
        $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            $null = New-Item -ItemType Directory -Path $cacheDir -Force
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $cacheDir | Out-Null
    })

# ── Settings: Clear cache ────────────────────────────────────────────────────
$clearCacheButton.add_Click({
        $cacheDir = Join-Path $env:APPDATA 'EvergreenUI\cache'
        if (Test-Path -LiteralPath $cacheDir) {
            try {
                $files = Get-ChildItem -LiteralPath $cacheDir -Filter '*.json' -File -ErrorAction Stop
                $count = $files.Count
                $files | Remove-Item -Force -ErrorAction Stop
                Write-UILog -SyncHash $syncHash -Message "Cache cleared. $count file(s) removed." -Level Info
            }
            catch {
                Write-UILog -SyncHash $syncHash -Message "Failed to clear cache: $_" -Level Error
            }
        }
        else {
            Write-UILog -SyncHash $syncHash -Message 'Cache directory does not exist. Nothing to clear.' -Level Info
        }
    })

# ── Settings: persist path edits on focus-leave ───────────────────────────────
$outputPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $outputPathBox.Text
        $outputPathBox.Text = $normalised
        $syncHash.Config.OutputPath = $normalised
        Set-UIConfig -Config $syncHash.Config
    })
$libraryPathBox.add_LostFocus({
        $normalised = & $normalizeDirectoryPath -PathValue $libraryPathBox.Text
        $libraryPathBox.Text = $normalised
        $syncHash.Config.LibraryPath = $normalised
        $libraryPathViewBox.Text = $normalised
        Set-UIConfig -Config $syncHash.Config
    })

# ── Show window (blocking) ────────────────────────────────────────────────────
[void]$window.ShowDialog()
