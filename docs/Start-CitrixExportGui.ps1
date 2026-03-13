#Requires -Version 5.1
<#
.SYNOPSIS
    WPF GUI wrapper for Export-CitrixDaas.ps1 with Fluent design.

.DESCRIPTION
    Provides a graphical user interface for configuring and running Citrix DaaS exports.
    Features include SDK status checking, file browsing, real-time progress logging,
    and light/dark theme switching.

.NOTES
    - Requires PowerShell 5.1 or later with Desktop edition
    - Pure PowerShell implementation using WPF (no external DLLs)
    - Must be run on Windows with .NET Framework support
#>

[CmdletBinding()]
param()

# Set strict mode and preferences
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Load required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Define XAML for the WPF window with Fluent design
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Citrix DaaS Export"
    Height="600"
    Width="900"
    MinWidth="900"
    MinHeight="600"
    WindowStartupLocation="CenterScreen"
    Background="{DynamicResource WindowBackgroundBrush}">
    
    <Window.Resources>
        <!-- Light Theme Colors (Default) -->
        <SolidColorBrush x:Key="WindowBackgroundBrush" Color="#F0F0F0"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="#000000"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#606060"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#3D6EA5"/>
        <SolidColorBrush x:Key="ControlBackgroundBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="ControlBorderBrush" Color="#C8C8C8"/>
        <SolidColorBrush x:Key="ButtonHoverBrush" Color="#E6E6E6"/>
        <SolidColorBrush x:Key="ButtonForegroundBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="ToggleThumbBrush" Color="#FFFFFF"/>
        
        <!-- Button Style with Fluent design -->
        <Style x:Key="FluentButton" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Opacity" Value="0.8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        
        <!-- TextBox Style -->
        <Style x:Key="FluentTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        
        <!-- GroupBox Style -->
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8"/>
        </Style>
        
        <!-- TextBlock Style -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
    </Window.Resources>
    
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>  <!-- SDK status -->
            <RowDefinition Height="Auto"/>  <!-- SDK hint text -->
            <RowDefinition Height="Auto"/>  <!-- Export script path -->
            <RowDefinition Height="Auto"/>  <!-- Secure client file -->
            <RowDefinition Height="Auto"/>  <!-- Customer ID -->
            <RowDefinition Height="Auto"/>  <!-- Output directory -->
            <RowDefinition Height="*"/>     <!-- Progress log -->
            <RowDefinition Height="Auto"/>  <!-- Bottom actions -->
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="150"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        
        <!-- Citrix SDK status and install -->
        <TextBlock Grid.Row="0" Grid.Column="0"
                   Text="Citrix SDK:"
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <TextBlock x:Name="SdkStatusTextBlock"
                   Grid.Row="0" Grid.Column="1"
                   Text="Checking..."
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <Button x:Name="DownloadSdkButton"
                Grid.Row="0" Grid.Column="2"
                Content="Download &amp; install SDK"
                Style="{StaticResource FluentButton}"
                Margin="0,0,0,8"
                MinWidth="180"/>
        
        <!-- SDK hint text -->
        <TextBlock Grid.Row="1" Grid.ColumnSpan="3"
                   Margin="0,0,0,24"
                   TextWrapping="Wrap"
                   Foreground="{DynamicResource TextSecondaryBrush}"
                   Text="Citrix PowerShell SDK install requires elevation. If not installed, install the SDK separately, or run this app as an administrator."/>
        
        <!-- Export script path -->
        <TextBlock Grid.Row="2" Grid.Column="0"
                   Text="Export script:"
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <TextBox x:Name="ExportScriptPathTextBox"
                 Grid.Row="2" Grid.Column="1"
                 Style="{StaticResource FluentTextBox}"
                 IsReadOnly="True"
                 Margin="0,0,8,8"
                 MinHeight="32"/>
        <Button x:Name="BrowseExportScriptButton"
                Grid.Row="2" Grid.Column="2"
                Content="Browse"
                Style="{StaticResource FluentButton}"
                Margin="0,0,0,8"
                MinWidth="100"/>
        
        <!-- Secure client file -->
        <TextBlock Grid.Row="3" Grid.Column="0"
                   Text="Secure client file:"
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <TextBox x:Name="SecureClientFileTextBox"
                 Grid.Row="3" Grid.Column="1"
                 Style="{StaticResource FluentTextBox}"
                 IsReadOnly="True"
                 Margin="0,0,8,8"
                 MinHeight="32"/>
        <Button x:Name="BrowseSecureClientFileButton"
                Grid.Row="3" Grid.Column="2"
                Content="Browse"
                Style="{StaticResource FluentButton}"
                Margin="0,0,0,8"
                MinWidth="100"/>
        
        <!-- Customer ID -->
        <TextBlock Grid.Row="4" Grid.Column="0"
                   Text="Customer ID:"
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <TextBox x:Name="CustomerIdTextBox"
                 Grid.Row="4" Grid.Column="1"
                 Grid.ColumnSpan="2"
                 Style="{StaticResource FluentTextBox}"
                 Margin="0,0,0,8"
                 MinHeight="32"/>
        
        <!-- Output directory -->
        <TextBlock Grid.Row="5" Grid.Column="0"
                   Text="Output directory:"
                   VerticalAlignment="Center"
                   Margin="0,0,8,8"/>
        <TextBox x:Name="OutputDirectoryTextBox"
                 Grid.Row="5" Grid.Column="1"
                 Style="{StaticResource FluentTextBox}"
                 IsReadOnly="True"
                 Margin="0,0,8,8"
                 MinHeight="32"/>
        <Button x:Name="BrowseOutputDirectoryButton"
                Grid.Row="5" Grid.Column="2"
                Content="Browse"
                Style="{StaticResource FluentButton}"
                Margin="0,0,0,8"
                MinWidth="100"/>
        
        <!-- Progress log -->
        <GroupBox Grid.Row="6" Grid.ColumnSpan="3"
                  Header="Progress"
                  Margin="0,8,0,8">
            <ScrollViewer x:Name="LogScrollViewer"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled">
                <TextBox x:Name="LogTextBox"
                         Background="{DynamicResource ControlBackgroundBrush}"
                         Foreground="{DynamicResource TextPrimaryBrush}"
                         BorderThickness="0"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         AcceptsReturn="True"
                         VerticalScrollBarVisibility="Disabled"
                         FontFamily="Consolas"
                         FontSize="12"
                         Padding="4"/>
            </ScrollViewer>
        </GroupBox>
        
        <!-- Actions and theme toggle -->
        <Grid Grid.Row="7" Grid.ColumnSpan="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            
                <!-- Theme toggle -->
                <StackPanel Grid.Column="0"
                       Orientation="Horizontal"
                       VerticalAlignment="Center"
                       Margin="0,0,8,0">
                <ToggleButton x:Name="ThemeToggle"
                         Width="40"
                         Height="20"
                         IsChecked="False"
                         ToolTip="Toggle between dark and light themes">
                    <ToggleButton.Template>
                    <ControlTemplate TargetType="ToggleButton">
                        <Grid>
                        <Border x:Name="Track"
                            CornerRadius="11"
                            Background="#7A7A7A"/>
                        <Ellipse x:Name="Thumb"
                             Width="12"
                             Height="12"
                             Fill="{DynamicResource ToggleThumbBrush}"
                             HorizontalAlignment="Left"
                             Margin="4,4,0,4"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Track"
                                Property="Background"
                                Value="{DynamicResource AccentBrush}"/>
                            <Setter TargetName="Thumb"
                                Property="HorizontalAlignment"
                                Value="Right"/>
                            <Setter TargetName="Thumb"
                                Property="Margin"
                                Value="0,4,4,4"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="False">
                            <Setter TargetName="Track"
                                Property="Background"
                                Value="#7A7A7A"/>
                            <Setter TargetName="Thumb"
                                Property="HorizontalAlignment"
                                Value="Left"/>
                            <Setter TargetName="Thumb"
                                Property="Margin"
                                Value="4,4,0,4"/>
                        </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                    </ToggleButton.Template>
                </ToggleButton>
                  <TextBlock x:Name="ThemeLabelTextBlock"
                      Text="Light theme"
                       Margin="8,0,0,0"
                       VerticalAlignment="Center"
                       Foreground="{DynamicResource TextPrimaryBrush}"/>
                </StackPanel>
            
            <!-- Action buttons -->
            <StackPanel Grid.Column="2"
                       Orientation="Horizontal"
                       HorizontalAlignment="Right">
                <Button x:Name="RunExportButton"
                        Content="Run export"
                        Style="{StaticResource FluentButton}"
                        Margin="0,0,8,0"
                        MinWidth="100"/>
                <Button x:Name="OpenFolderButton"
                        Content="Open folder"
                        Style="{StaticResource FluentButton}"
                        MinWidth="100"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

# Parse XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get control references
$sdkStatusTextBlock = $window.FindName("SdkStatusTextBlock")
$downloadSdkButton = $window.FindName("DownloadSdkButton")
$exportScriptPathTextBox = $window.FindName("ExportScriptPathTextBox")
$browseExportScriptButton = $window.FindName("BrowseExportScriptButton")
$secureClientFileTextBox = $window.FindName("SecureClientFileTextBox")
$browseSecureClientFileButton = $window.FindName("BrowseSecureClientFileButton")
$customerIdTextBox = $window.FindName("CustomerIdTextBox")
$outputDirectoryTextBox = $window.FindName("OutputDirectoryTextBox")
$browseOutputDirectoryButton = $window.FindName("BrowseOutputDirectoryButton")
$logTextBox = $window.FindName("LogTextBox")
$logScrollViewer = $window.FindName("LogScrollViewer")
$themeToggle = $window.FindName("ThemeToggle")
$themeLabelTextBlock = $window.FindName("ThemeLabelTextBlock")
$runExportButton = $window.FindName("RunExportButton")
$openFolderButton = $window.FindName("OpenFolderButton")

# Synchronized hashtable for thread-safe communication
$syncHash = [hashtable]::Synchronized(@{
        Window             = $window
        LogTextBox         = $logTextBox
        LogScrollViewer    = $logScrollViewer
        SdkStatusTextBlock = $sdkStatusTextBlock
        RunExportButton    = $runExportButton
        DownloadSdkButton  = $downloadSdkButton
        IsRunning          = $false
        IsAdmin            = $false
    })

#region Helper Functions
function Write-Log {
    param([string]$Message)
    
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    $syncHash.Window.Dispatcher.Invoke([action] {
            $syncHash.LogTextBox.AppendText("$logEntry`r`n")
            $syncHash.LogScrollViewer.ScrollToEnd()
        }, "Normal")
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CitrixSdk {
    Write-Log -Message "Checking Citrix SDK..."
    
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("syncHash", $syncHash)
    
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    
    [void]$powershell.AddScript({
            try {
                $snapins = Get-PSSnapin -Name "Citrix*" -Registered -ErrorAction SilentlyContinue
                $installed = $null -ne $snapins -and $snapins.Count -gt 0
            
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $status = if ($installed) { "Installed" } else { "Not installed" }
                        $syncHash.SdkStatusTextBlock.Text = $status
                    }, "Normal")
            
                $message = if ($installed) { "Installed" } else { "Not installed" }
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $timestamp = Get-Date -Format "HH:mm:ss"
                        $syncHash.LogTextBox.AppendText("[$timestamp] Citrix SDK: $message`r`n")
                        $syncHash.LogScrollViewer.ScrollToEnd()
                    }, "Normal")
            }
            catch {
                $syncHash.Window.Dispatcher.Invoke([action] {
                        $syncHash.SdkStatusTextBlock.Text = "Check failed"
                        $timestamp = Get-Date -Format "HH:mm:ss"
                        $syncHash.LogTextBox.AppendText("[$timestamp] Failed to check Citrix SDK: $($_.Exception.Message)`r`n")
                        $syncHash.LogScrollViewer.ScrollToEnd()
                    }, "Normal")
            }
        })
    
    [void]$powershell.BeginInvoke()
}

function Set-LightTheme {
    $resources = $window.Resources
    
    $resources["WindowBackgroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(240, 240, 240))
    $resources["TextPrimaryBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 0, 0))
    $resources["TextSecondaryBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(96, 96, 96))
    $resources["AccentBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(61, 110, 165))
    $resources["ButtonForegroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 255, 255))
    $resources["ToggleThumbBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 255, 255))
    $resources["ControlBackgroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 255, 255))
    $resources["ControlBorderBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(200, 200, 200))
    $resources["ButtonHoverBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(230, 230, 230))
    
    $window.Background = $resources["WindowBackgroundBrush"]
    $themeLabelTextBlock.Text = "Light theme"
    Write-Log -Message "Theme changed to light mode"
}

function Set-DarkTheme {
    $resources = $window.Resources
    
    $resources["WindowBackgroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(32, 32, 32))
    $resources["TextPrimaryBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(255, 255, 255))
    $resources["TextSecondaryBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(176, 176, 176))
    $resources["AccentBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(96, 205, 255))
    $resources["ControlBackgroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(45, 45, 45))
    $resources["ControlBorderBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(64, 64, 64))
    $resources["ButtonHoverBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(61, 61, 61))
    $resources["ButtonForegroundBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 0, 0))
    $resources["ToggleThumbBrush"] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 0, 0))    
    $window.Background = $resources["WindowBackgroundBrush"]
    $themeLabelTextBlock.Text = "Dark theme"
    Write-Log -Message "Theme changed to dark mode"
}
#endregion

#region Event Handlers
# SDK Download Button
$downloadSdkButton.Add_Click({
        if (-not $syncHash.IsAdmin) {
            Write-Log -Message "SDK installation requires administrator privileges"
            return
        }
    
        $sdkUrl = "https://download.apps.cloud.com/CitrixPoshSdk.exe"
        $tempPath = Join-Path -Path $env:TEMP -ChildPath "CitrixPoshSdk.exe"
        Write-Log -Message "Starting Citrix SDK download..."
    
        try {
            Invoke-WebRequest -Uri $sdkUrl -OutFile $tempPath -UseBasicParsing
            Write-Log -Message "Download complete. Launching installer..."
            Start-Process -FilePath $tempPath
            Write-Log -Message "Follow the installer and restart this app afterwards."
        }
        catch {
            Write-Log -Message "ERROR: Failed to download SDK: $($_.Exception.Message)"
        }
    })

# Browse Export Script Button
$browseExportScriptButton.Add_Click({
        $dialog = New-Object -TypeName "System.Windows.Forms.OpenFileDialog"
        $dialog.Filter = "PowerShell script (Export-CitrixDaas.ps1)|Export-CitrixDaas.ps1|PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*"
        $dialog.Title = "Select Export-CitrixDaas.ps1"
        $dialog.FileName = "Export-CitrixDaas.ps1"
    
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $exportScriptPathTextBox.Text = $dialog.FileName
            Write-Log -Message "Export script selected: $($dialog.FileName)"
        }
    })

# Browse Secure Client File Button
$browseSecureClientFileButton.Add_Click({
        $dialog = New-Object -TypeName "System.Windows.Forms.OpenFileDialog"
        $dialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $dialog.Title = "Select Secure Client File"
    
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $secureClientFileTextBox.Text = $dialog.FileName
            Write-Log -Message "Secure client file selected: $($dialog.FileName)"
        }
    })

# Browse Output Directory Button
$browseOutputDirectoryButton.Add_Click({
        $dialog = New-Object -TypeName "System.Windows.Forms.FolderBrowserDialog"
        $dialog.Description = "Select Output Directory"
        $dialog.ShowNewFolderButton = $true
    
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputDirectoryTextBox.Text = $dialog.SelectedPath
            Write-Log -Message "Output directory selected: $($dialog.SelectedPath)"
        }
    })

# Theme Toggle
$themeToggle.Add_Checked({
        Set-DarkTheme
    })

$themeToggle.Add_Unchecked({
        Set-LightTheme
    })

# Run Export Button
$runExportButton.Add_Click({
        if ($syncHash.IsRunning) {
            Write-Log -Message "Export is already running"
            return
        }
    
        # Validate inputs
        $scriptPath = $exportScriptPathTextBox.Text
        $secureFile = $secureClientFileTextBox.Text
        $customerId = $customerIdTextBox.Text
        $outputPath = $outputDirectoryTextBox.Text
    
        if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path $scriptPath)) {
            Write-Log -Message "ERROR: Export script path is invalid. Select Export-CitrixDaas.ps1."
            return
        }
    
        if ([string]::IsNullOrWhiteSpace($secureFile) -or -not (Test-Path $secureFile)) {
            Write-Log -Message "ERROR: Secure client file path is invalid."
            return
        }
    
        if ([string]::IsNullOrWhiteSpace($customerId)) {
            Write-Log -Message "ERROR: Customer ID is required."
            return
        }
    
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            Write-Log -Message "ERROR: Output directory is required."
            return
        }
    
        # Create output directory if it doesn't exist
        if (-not (Test-Path $outputPath)) {
            try {
                New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
                Write-Log -Message "Created output directory: $outputPath"
            }
            catch {
                Write-Log -Message "ERROR: Failed to create output directory: $($_.Exception.Message)"
                return
            }
        }
    
        # Disable buttons during execution
        $syncHash.IsRunning = $true
        $runExportButton.IsEnabled = $false
        $downloadSdkButton.IsEnabled = $false
    
        Write-Log -Message "Starting export..."
        Write-Log -Message "Script: $scriptPath"
        Write-Log -Message "Customer ID: $customerId"
        Write-Log -Message "Output: $outputPath"
    
        # Create runspace for background execution
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = "STA"
        $runspace.ThreadOptions = "ReuseThread"
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable("syncHash", $syncHash)
        $runspace.SessionStateProxy.SetVariable("scriptPath", $scriptPath)
        $runspace.SessionStateProxy.SetVariable("outputPath", $outputPath)
        $runspace.SessionStateProxy.SetVariable("customerId", $customerId)
        $runspace.SessionStateProxy.SetVariable("secureFile", $secureFile)
    
        $powershell = [powershell]::Create()
        $powershell.Runspace = $runspace
    
        [void]$powershell.AddScript({
                try {
                    # Define progress callback
                    $progressCallback = {
                        param([string]$message)
                
                        if ([string]::IsNullOrWhiteSpace($message)) { return }
                
                        $syncHash.Window.Dispatcher.Invoke([action] {
                                $timestamp = Get-Date -Format "HH:mm:ss"
                                $syncHash.LogTextBox.AppendText("[$timestamp] $message`r`n")
                                $syncHash.LogScrollViewer.ScrollToEnd()
                            }, "Normal")
                    }
            
                    # Execute the export script
                    & $scriptPath -Path $outputPath -CustomerId $customerId -SecureClientFile $secureFile -ProgressCallback $progressCallback
            
                    # Success
                    $syncHash.Window.Dispatcher.Invoke([action] {
                            $timestamp = Get-Date -Format "HH:mm:ss"
                            $syncHash.LogTextBox.AppendText("[$timestamp] Export completed successfully!`r`n")
                            $syncHash.LogScrollViewer.ScrollToEnd()
                        }, "Normal")
                }
                catch {
                    # Error
                    $syncHash.Window.Dispatcher.Invoke([action] {
                            $timestamp = Get-Date -Format "HH:mm:ss"
                            $syncHash.LogTextBox.AppendText("[$timestamp] ERROR: $($_.Exception.Message)`r`n")
                            $syncHash.LogScrollViewer.ScrollToEnd()
                        }, "Normal")
                }
                finally {
                    # Re-enable buttons
                    $syncHash.Window.Dispatcher.Invoke([action] {
                            $syncHash.IsRunning = $false
                            $syncHash.RunExportButton.IsEnabled = $true
                            $syncHash.DownloadSdkButton.IsEnabled = $syncHash.IsAdmin
                        }, "Normal")
                }
            })
    
        [void]$powershell.BeginInvoke()
    })

# Open Folder Button
$openFolderButton.Add_Click({
        $outputPath = $outputDirectoryTextBox.Text
    
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            Write-Log -Message "ERROR: No output directory specified"
            return
        }
    
        if (Test-Path $outputPath) {
            Start-Process explorer.exe -ArgumentList $outputPath
            Write-Log -Message "Opened output directory in Explorer"
        }
        else {
            Write-Log -Message "ERROR: Output directory does not exist: $outputPath"
        }
    })
#endregion

#region Window Initialization
# Window Loaded event
$window.Add_Loaded({
        # Check administrator status
        $syncHash.IsAdmin = Test-Administrator
        $downloadSdkButton.IsEnabled = $syncHash.IsAdmin
    
        if ($syncHash.IsAdmin) {
            Write-Log -Message "Running with administrator privileges"
        }
        else {
            Write-Log -Message "Running without administrator privileges (SDK install disabled)"
        }
    
        # Set default values
        $scriptDir = Split-Path -Parent $PSCommandPath
        $exportScriptPathTextBox.Text = Join-Path -Path $scriptDir -ChildPath "Export-CitrixDaas.ps1"
        $secureClientFileTextBox.Text = Join-Path -Path $scriptDir -ChildPath "serviceprincipal.csv"
        $customerIdTextBox.Text = "ukmsctx002"
        $outputDirectoryTextBox.Text = Join-Path -Path $scriptDir -ChildPath "Export"
    
        Write-Log -Message "GUI initialized"
        Write-Log -Message "Default export script: $($exportScriptPathTextBox.Text)"
        Write-Log -Message "Default output: $($outputDirectoryTextBox.Text)"
    
        # Check SDK status asynchronously
        Test-CitrixSdk
    
        # Focus on Customer ID field
        $customerIdTextBox.Focus()
    })
#endregion

# Show the window
[void]$window.ShowDialog()
