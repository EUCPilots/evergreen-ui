#Requires -Version 5.1
<#
.SYNOPSIS
    Factory function — creates a clean STA runspace ready for WPF background work.

.DESCRIPTION
    Creates, configures, and opens a PowerShell runspace with STA apartment state
    and ReuseThread thread options. Injects $syncHash so the background script can
    communicate back to the UI thread via Dispatcher.Invoke.

    The caller is responsible for:
      - Attaching a [powershell] instance to the returned runspace
      - Calling BeginInvoke on the powershell instance
      - Disposing both the powershell instance and the runspace when done

.PARAMETER SyncHash
    The shared [hashtable]::Synchronized hashtable that contains UI control
    references and shared state. Injected into the runspace as $syncHash.

.OUTPUTS
    System.Management.Automation.Runspaces.Runspace

.EXAMPLE
    $rs = New-WpfRunspace -SyncHash $syncHash
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({ $syncHash.Window.Dispatcher.Invoke([action]{ ... }, 'Normal') })
    [void]$ps.BeginInvoke()
#>
function New-WpfRunspace {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.Runspace])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('syncHash', $SyncHash)

    return $runspace
}
