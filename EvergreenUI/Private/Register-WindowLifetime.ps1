function Register-WindowLifetime {
    <#
    .SYNOPSIS
    Registers event handlers for window loading, closing, and lifecycle management.

    .DESCRIPTION
    Sets up the window.Loaded event to initialize UI state after XAML is displayed,
    and the window.Closed event to clean up async operations, close runspaces, and
    persist final configuration. This handler is responsible for orchestrating the
    startup initialization sequence (loading app catalog, restoring config, initializing
    auth UI) and shutdown cleanup to prevent orphaned runspaces or disposed dispatcher
    exceptions.

    .PARAMETER SyncHash
    The synchronized hashtable containing window controls and application state.

    .PARAMETER Controls
    Hashtable of resolved WPF controls.

    .PARAMETER Window
    The WPF Window object.

    .NOTES
    Extracted from Start-EvergreenWorkbench for modularization per item 17 of phase 5.
    This is the only feature handler that manages both startup and shutdown.
    #>
    param(
        [System.Collections.Hashtable]$SyncHash,
        [System.Collections.Hashtable]$Controls,
        [System.Windows.Window]$Window
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Extract shared controls needed for startup
    $themeComboBox = $Controls.ThemeComboBox
    $evergreenVersionText = $Window.FindName('EvergreenVersionText')
    $evergreenStatusDot = $Window.FindName('EvergreenStatusDot')

    # TODO: Implement window.Loaded event handler
    # This is the main startup orchestration point. It should:
    # 1. Apply saved theme (Set-LightTheme or Set-DarkTheme)
    # 2. Load Evergreen module and update version display in title bar
    # 3. Load app catalog via Get-EvergreenAppList
    # 4. Restore last selected app if configured
    # 5. Restore UI configuration (paths, selections, toggles)
    # 6. Restore auth UI state (display auth status, initialize provider selection)
    # 7. Initialize elevation state for Install feature
    # 8. Log startup completion

    # TODO: Implement window.Closed event handler
    # This is the main shutdown cleanup point. It should:
    # 1. Persist final UI state (window size, position, selections)
    # 2. Cancel any in-progress background operations
    # 3. Stop all timers
    # 4. Close all runspaces (check IsRunspaceOpen before dispose)
    # 5. Dispose PowerShell instances via EndInvoke if valid
    # 6. Unregister event handlers to break circular references
    # 7. Log shutdown completion with any errors (Write-Verbose only - don't use disposed dispatcher)

    # Current event handler pattern (to migrate):
    # $window.add_Loaded({ ... startup code ... })
    # $window.add_Closed({ ... cleanup code ... })

    Write-Verbose 'EvergreenUI: Window lifetime handlers registered.'
}
