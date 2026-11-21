#Requires -RunAsAdministrator
<#
    .SYNOPSIS
        Installs an application based on logic defined in Install.json. Simple alternative to PSAppDeployToolkit.

    .DESCRIPTION
        This script reads package installation configuration from Install.json in the current directory
        and executes the installation, pre-installation tasks (stopping processes, uninstalling previous
        versions), and post-installation tasks (copying files, running additional scripts). Includes
        automatic 64-bit process restart if running in 32-bit session on 64-bit OS.

    .EXAMPLE
        PS C:\> .\Install.ps1
        Executes the installation using configuration from Install.json in the current directory.

    .OUTPUTS
        System.Int32
        Returns the exit code from the installer (0 for success).

    .NOTES
        Author: Aaron Parker
        - Requires Install.json configuration file in the current working directory
        - Logs are written to $Env:ProgramData\Microsoft\IntuneManagementExtension\Logs\PSPackageFactoryInstall.log
        - Supports both EXE and MSI installers
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param ()

# Set strict mode and error handling
Set-StrictMode -Version "Latest"
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

# Log file path. Parent directory should exist if device is enrolled in Intune
$Script:LogFile = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs\PSPackageFactoryInstall.log"

#region Logging Function
function Write-LogFile {
    <#
        .SYNOPSIS
            This function creates or appends a line to a log file

        .DESCRIPTION
            This function writes a log line to a log file in the form synonymous with
            ConfigMgr logs so that tools such as CMtrace and SMStrace can easily parse
            the log file.  It uses the ConfigMgr client log format's file section
            to add the line of the script in which it was called.

        .PARAMETER  Message
            The message parameter is the log message you'd like to record to the log file

        .PARAMETER  LogLevel
            The logging level is the severity rating for the message you're recording. Like ConfigMgr
            clients, you have 3 severity levels available; 1, 2 and 3 from informational messages
            for FYI to critical messages that stop the install. This defaults to 1.

        .EXAMPLE
            PS C:\> Write-LogFile -Message 'Value1' -LogLevel 'Value2'
            This example shows how to call the Write-LogFile function with named parameters.

        .NOTES
            Constantin Lotz;
            Adam Bertram, https://github.com/adbertram/PowerShellTipsToWriteBy/blob/f865c4212284dc25fe613ca70d9a4bafb6c7e0fe/chapter_7.ps1#L5
    #>
    [CmdletBinding(SupportsShouldProcess = $false)]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
        [System.String] $Message,

        [Parameter(Position = 1, Mandatory = $false)]
        [ValidateSet(1, 2, 3)]
        [System.Int16] $LogLevel = 1
    )

    process {
        ## Build the line which will be recorded to the log file
        $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format "yyyy-MM-dd"), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
        $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">' -f $LineFormat

        Write-Information -MessageData $Message -InformationAction "Continue"
        Add-Content -Value $Line -Path $Script:LogFile
    }
}
#endregion

#region Restart if running in a 32-bit session
if (!([System.Environment]::Is64BitProcess)) {
    if ([System.Environment]::Is64BitOperatingSystem) {

        # Create a string from the passed parameters
        [System.String]$ParameterString = ""
        foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
            $ParameterString += " -$($Parameter.Key) $($Parameter.Value)"
        }

        # Execute the script in a 64-bit process with the passed parameters
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Definition)`"$ParameterString"
        $ProcessPath = $(Join-Path -Path $Env:SystemRoot -ChildPath "\Sysnative\WindowsPowerShell\v1.0\powershell.exe")
        Write-LogFile -Message "Restarting in 64-bit PowerShell."
        Write-LogFile -Message "File path: $ProcessPath."
        Write-LogFile -Message "Arguments: $Arguments."
        $params = @{
            FilePath     = $ProcessPath
            ArgumentList = $Arguments
            Wait         = $true
            WindowStyle  = "Hidden"
        }
        Start-Process @params
        exit 0
    }
}
#endregion

#region Installer functions
function Get-InstallConfig {
    [CmdletBinding()]
    param (
        [System.String] $File = "Install.json",
        [System.Management.Automation.PathInfo] $Path = $PWD
    )
    try {
        $InstallFile = Join-Path -Path $Path -ChildPath $File
        Write-LogFile -Message "Read package install config: $InstallFile"
        $Config = Get-Content -Path $InstallFile -Raw | ConvertFrom-Json
        if ($null -eq $Config.PSObject.Properties["LogPath"] -or $null -eq $Config.LogPath) {
            $Config | Add-Member -MemberType NoteProperty -Name "LogPath" -Value "" -Force
        }

        if ($null -eq $Config.PSObject.Properties["InstallTasks"] -or $null -eq $Config.InstallTasks) {
            $Config | Add-Member -MemberType NoteProperty -Name "InstallTasks" -Value ([PSCustomObject]@{}) -Force
        }
        if ($null -eq $Config.InstallTasks.PSObject.Properties["ArgumentList"] -or $null -eq $Config.InstallTasks.ArgumentList) {
            $Config.InstallTasks | Add-Member -MemberType NoteProperty -Name "ArgumentList" -Value "" -Force
        }
        if ($null -eq $Config.InstallTasks.PSObject.Properties["UninstallMsi"] -or $null -eq $Config.InstallTasks.UninstallMsi) {
            $Config.InstallTasks | Add-Member -MemberType NoteProperty -Name "UninstallMsi" -Value @() -Force
        }
        if ($null -eq $Config.InstallTasks.PSObject.Properties["Wait"] -or $null -eq $Config.InstallTasks.Wait) {
            $Config.InstallTasks | Add-Member -MemberType NoteProperty -Name "Wait" -Value 0 -Force
        }

        if ($null -eq $Config.PSObject.Properties["PostInstall"] -or $null -eq $Config.PostInstall) {
            $Config | Add-Member -MemberType NoteProperty -Name "PostInstall" -Value ([PSCustomObject]@{}) -Force
        }
        if ($null -eq $Config.PostInstall.PSObject.Properties["StopPath"] -or $null -eq $Config.PostInstall.StopPath) {
            $Config.PostInstall | Add-Member -MemberType NoteProperty -Name "StopPath" -Value @() -Force
        }
        if ($null -eq $Config.PostInstall.PSObject.Properties["Remove"] -or $null -eq $Config.PostInstall.Remove) {
            $Config.PostInstall | Add-Member -MemberType NoteProperty -Name "Remove" -Value @() -Force
        }
        if ($null -eq $Config.PostInstall.PSObject.Properties["CopyFile"] -or $null -eq $Config.PostInstall.CopyFile) {
            $Config.PostInstall | Add-Member -MemberType NoteProperty -Name "CopyFile" -Value @() -Force
        }
        if ($null -eq $Config.PostInstall.PSObject.Properties["Run"] -or $null -eq $Config.PostInstall.Run) {
            $Config.PostInstall | Add-Member -MemberType NoteProperty -Name "Run" -Value @() -Force
        }
        return $Config
    }
    catch {
        Write-LogFile -Message "Get-InstallConfig: $($_.Exception.Message)" -LogLevel 3
        throw $_
    }
}

function Get-Installer {
    [CmdletBinding()]
    param (
        [System.String] $File,
        [System.Management.Automation.PathInfo] $Path = $PWD
    )
    $Installer = Get-ChildItem -Path $Path -Filter $File -Recurse | Select-Object -First 1
    if ($null -eq $Installer -or [System.String]::IsNullOrEmpty($Installer.FullName)) {
        Write-LogFile -Message "File not found: $File" -LogLevel 3
        throw [System.IO.FileNotFoundException]::New("File not found: $File")
    }
    else {
        Write-LogFile -Message "Found installer: $($Installer.FullName)"
        return $Installer.FullName
    }
}

function Copy-File {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [System.Array] $File,
        [System.Management.Automation.PathInfo] $Path = $PWD
    )
    process {
        foreach ($Item in $File) {
            try {
                $FilePath = Get-ChildItem -Path $Path -Filter $Item.Source -Recurse
                if ($null -eq $FilePath) {
                    Write-LogFile -Message "Copy-File: Source file not found: $($Item.Source)" -LogLevel 2
                    continue
                }
                Write-LogFile -Message "Copy-File: Source: $($FilePath.FullName)"
                Write-LogFile -Message "Copy-File: Destination: $($Item.Destination)"
                $params = @{
                    Path        = $FilePath.FullName
                    Destination = $Item.Destination
                    Container   = $false
                    Force       = $true
                }
                Copy-Item @params
            }
            catch {
                Write-LogFile -Message "Copy-File: $($_.Exception.Message)" -LogLevel 3
                Write-Warning -Message $_.Exception.Message
            }
        }
    }
}

function Remove-Path {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [System.String[]] $Path
    )
    process {
        foreach ($Item in $Path) {
            try {
                if (Test-Path -Path $Item -PathType "Container") {
                    $params = @{
                        Path    = $Item
                        Recurse = $true
                        Force   = $true
                    }
                    Remove-Item @params
                    Write-LogFile -Message "Remove-Item: $Item"
                }
                else {
                    $params = @{
                        Path  = $Item
                        Force = $true
                    }
                    Remove-Item @params
                    Write-LogFile -Message "Remove-Item: $Item"
                }
            }
            catch {
                Write-LogFile -Message "Remove-Path error: $($_.Exception.Message)" -LogLevel 3
                Write-Warning -Message $_.Exception.Message
            }
        }
    }
}

function Stop-PathProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [System.String[]] $Path,
        [System.Management.Automation.SwitchParameter] $Force
    )
    process {
        foreach ($Item in $Path) {
            try {
                Get-Process | Where-Object { $_.Path -like $Item } | ForEach-Object { Write-LogFile -Message "Stop-PathProcess: $($_.ProcessName)" }
                if ($PSBoundParameters.ContainsKey("Force")) {
                    Get-Process | Where-Object { $_.Path -like $Item } | `
                        Stop-Process -Force
                }
                else {
                    Get-Process | Where-Object { $_.Path -like $Item } | `
                        Stop-Process
                }
            }
            catch {
                Write-LogFile -Message "Stop-PathProcess error: $($_.Exception.Message)" -LogLevel 2
                Write-Warning -Message $_.Exception.Message
            }
        }
    }
}

function Uninstall-Msi {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [System.String[]] $ProductName,
        [System.String] $LogPath
    )
    process {
        foreach ($Item in $ProductName) {
            if ($PSCmdlet.ShouldProcess($Item)) {
                try {
                    $Product = Get-CimInstance -Class "Win32_InstalledWin32Program" | Where-Object { $_.Name -like $Item }
                    if ($null -eq $Product) {
                        Write-LogFile -Message "Product not found: $Item" -LogLevel 2
                        continue
                    }
                    $params = @{
                        FilePath     = "$Env:SystemRoot\System32\msiexec.exe"
                        ArgumentList = "/uninstall `"$($Product.MsiProductCode)`" /quiet /log `"$LogPath\Uninstall-$($Item -replace " ").log`""
                        NoNewWindow  = $true
                        PassThru     = $true
                        Wait         = $true
                    }
                    $result = Start-Process @params
                    Write-LogFile -Message "$Env:SystemRoot\System32\msiexec.exe /uninstall `"$($Product.MsiProductCode)`" /quiet /log `"$LogPath\Uninstall-$($Item -replace " ").log`""
                    Write-LogFile -Message "Msiexec result: $($result.ExitCode)"
                    return $result.ExitCode
                }
                catch {
                    Write-LogFile -Message "Uninstall-Msi error: $($_.Exception.Message)" -LogLevel 3
                    Write-Warning -Message $_.Exception.Message
                }
            }
        }
    }
}
#endregion

#region Install logic
# Trim log if greater than 50 MB
if (Test-Path -Path $Script:LogFile) {
    if ((Get-Item -Path $Script:LogFile).Length -gt 50MB) {
        Clear-Content -Path $Script:LogFile
        Write-LogFile -Message "Log file size greater than 50MB. Clearing log." -LogLevel 2
    }
}

# Get the install details for this application
$Install = Get-InstallConfig
$Installer = Get-Installer -File $Install.PackageInformation.SetupFile

if ([System.String]::IsNullOrEmpty($Installer)) {
    Write-LogFile -Message "File not found: $($Install.PackageInformation.SetupFile)" -LogLevel 3
    throw [System.IO.FileNotFoundException]::New("File not found: $($Install.PackageInformation.SetupFile)")
}
else {

    # Stop processes before installing the application
    if ($null -ne $Install.InstallTasks.StopPath -and $Install.InstallTasks.StopPath.Count -gt 0) { Stop-PathProcess -Path $Install.InstallTasks.StopPath }

    # Uninstall the application
    if ($null -ne $Install.InstallTasks.UninstallMsi -and $Install.InstallTasks.UninstallMsi.Count -gt 0) { Uninstall-Msi -ProductName $Install.InstallTasks.UninstallMsi -LogPath $Install.LogPath }
    if ($null -ne $Install.InstallTasks.Remove -and $Install.InstallTasks.Remove.Count -gt 0) { Remove-Path -Path $Install.InstallTasks.Remove }

    # Create the log folder
    if (Test-Path -Path $Install.LogPath -PathType "Container") {
        Write-LogFile -Message "Directory exists: $($Install.LogPath)"
    }
    else {
        Write-LogFile -Message "Create directory: $($Install.LogPath)"
        New-Item -Path $Install.LogPath -ItemType "Directory" | Out-Null
    }

    # Build the argument list
    $ArgumentList = $Install.InstallTasks.ArgumentList -replace "#SetupFile", $Installer
    $ArgumentList = $ArgumentList -replace "#LogName", $Install.PackageInformation.SetupFile
    $ArgumentList = $ArgumentList -replace "#LogPath", $Install.LogPath
    $ArgumentList = $ArgumentList -replace "#PWD", $PWD.Path
    $ArgumentList = $ArgumentList -replace "#SetupDirectory", ([System.IO.Path]::GetDirectoryName($Installer))

    try {
        # Perform the application install
        $result = @{ ExitCode = 0 }
        switch ($Install.PackageInformation.SetupType) {
            "EXE" {
                Write-LogFile -Message "Installer: $Installer"
                Write-LogFile -Message "ArgumentList: $ArgumentList"
                $params = @{
                    FilePath     = $Installer
                    ArgumentList = $ArgumentList
                    NoNewWindow  = $true
                    PassThru     = $true
                    Wait         = $true
                }
                if ($PSCmdlet.ShouldProcess($Installer, $ArgumentList)) {
                    $result = Start-Process @params
                }
            }
            "MSI" {
                Write-LogFile -Message "Installer: $Env:SystemRoot\System32\msiexec.exe"
                Write-LogFile -Message "ArgumentList: $ArgumentList"
                $params = @{
                    FilePath     = "$Env:SystemRoot\System32\msiexec.exe"
                    ArgumentList = $ArgumentList
                    NoNewWindow  = $true
                    PassThru     = $true
                    Wait         = $true
                }
                if ($PSCmdlet.ShouldProcess("$Env:SystemRoot\System32\msiexec.exe", $ArgumentList)) {
                    $result = Start-Process @params
                }
            }
            default {
                Write-LogFile -Message "$($Install.PackageInformation.SetupType) not found in the supported setup types - EXE, MSI." -LogLevel 3
                throw "$($Install.PackageInformation.SetupType) not found in the supported setup types - EXE, MSI."
            }
        }

        # If wait specified, wait the specified seconds
        if ($null -ne $Install.InstallTasks.Wait -and $Install.InstallTasks.Wait -gt 0) { Start-Sleep -Seconds $Install.InstallTasks.Wait }

        # Stop processes after installing the application
        if ($null -ne $Install.PostInstall.StopPath -and $Install.PostInstall.StopPath.Count -gt 0) { Stop-PathProcess -Path $Install.PostInstall.StopPath }

        # Perform post install actions
        if ($null -ne $Install.PostInstall.Remove -and $Install.PostInstall.Remove.Count -gt 0) { Remove-Path -Path $Install.PostInstall.Remove }
        if ($null -ne $Install.PostInstall.CopyFile -and $Install.PostInstall.CopyFile.Count -gt 0) { Copy-File -File $Install.PostInstall.CopyFile }

        # Execute run tasks
        if ($null -ne $Install.PostInstall.Run -and $Install.PostInstall.Run.Count -gt 0) {
            foreach ($Task in $Install.PostInstall.Run) { & $Task }
        }
    }
    catch {
        Write-LogFile -Message $_.Exception.Message -LogLevel 3
        throw $_
    }
    finally {
        Write-LogFile -Message "Install.ps1 complete. Exit Code: $($result.ExitCode)"
        exit $result.ExitCode
    }
}
#endregion
