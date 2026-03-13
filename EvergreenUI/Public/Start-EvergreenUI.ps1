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

# ── Launch main window ────────────────────────────────────────────────────────
# TODO: Replace this stub with the real window construction call once
#       the shell window (Phase 3) is implemented.
Write-Warning 'EvergreenUI is not yet implemented. This is a scaffold stub.'
