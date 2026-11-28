Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-EvergreenWorkbench {
    <#
    .SYNOPSIS
        Opens the Evergreen Workbench graphical interface.
    .DESCRIPTION
        Starts the v2 WPF interface for browsing Evergreen applications,
        queuing downloads, managing a library, and publishing to Intune. Longer
        operations run through the module's background job pool. On an
        MTA thread, the interface is hosted on a dedicated STA runspace.
    .EXAMPLE
        Start-EvergreenWorkbench
    .OUTPUTS
        None.
    .NOTES
        Windows only. Requires PowerShell 7.6 or later.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $IsWindows) {
        throw 'Evergreen Workbench requires Windows because its user interface uses WPF.'
    }
    if (-not $PSCmdlet.ShouldProcess('Evergreen Workbench', 'Open graphical interface')) {
        return
    }

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        Write-Verbose -Message 'EvergreenUI: Starting the WPF interface on a dedicated STA runspace'
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
        $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $runspace.Open()
        $powerShell = [powershell]::Create()
        $powerShell.Runspace = $runspace
        try {
            $null = $powerShell.AddScript({
                param($ModulePath)
                Import-Module -Name $ModulePath -ErrorAction Stop
                Start-EvergreenWorkbench
            }.ToString()).AddArgument($script:ewModulePath)
            $null = $powerShell.Invoke()
            if ($powerShell.HadErrors) {
                $PSCmdlet.ThrowTerminatingError($powerShell.Streams.Error[0])
            }
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'WorkbenchSTAStartupFailed',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        finally {
            $powerShell.Dispose()
            $runspace.Dispose()
        }
        return
    }

    $window = Get-EwWorkbenchWindow
    $settings = Get-EwSetting
    $window.ThemeMode = switch ([string]$settings.Theme) {
        'Light' { [System.Windows.ThemeMode]::Light }
        'Dark' { [System.Windows.ThemeMode]::Dark }
        default { [System.Windows.ThemeMode]::System }
    }
    $state = Get-EwWorkbenchState -Window $window -Settings $settings -DeferPackageDefinitionsStartup
    Restore-EwWorkbenchWindowSize -Window $window -Settings $settings
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        & $state.ModuleInvoker -Name 'Invoke-EwWorkbenchJobMonitor' -Parameters @{ State = $state }
    }.GetNewClosure())
    $window.Add_Loaded({
        try {
            & $state.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $state
                Kind = 'Apps'
                Name = 'Load application catalog'
                ScriptBlock = { Get-EwApp }
            }
        }
        catch {
            & $state.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $state
                Message = $_.Exception.Message
                Level = 'Error'
            }
        }
        finally {
            $state.PackageDefinitionsStartupDeferred = $false
        }
        $timer.Start()
    }.GetNewClosure())
    $window.Add_Closed({
        $timer.Stop()
    }.GetNewClosure())
    $window.Add_Closing({
        param($eventSource, $closingArgs)
        if ($eventSource -eq $state.Window) {
            & $state.ModuleInvoker -Name 'Invoke-EwWorkbenchClosingGuard' -Parameters @{ State = $state; ClosingArgs = $closingArgs }
            if (-not $closingArgs.Cancel) {
                & $state.ModuleInvoker -Name 'Save-EwWorkbenchWindowSize' -Parameters @{ State = $state }
            }
        }
    }.GetNewClosure())
    Write-Verbose -Message 'EvergreenUI: Showing Workbench window'
    $null = $window.ShowDialog()
}
