#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies that the Evergreen module is installed and importable.

.DESCRIPTION
    Checks for the Evergreen module using Get-Module -ListAvailable. If found,
    returns the installed version as a string. If not found, throws a
    terminating error with an actionable message.

    Called once from Start-EvergreenUI before the window is constructed. The
    result is also used to populate the module status indicator in the title bar.

.OUTPUTS
    System.String — the installed Evergreen module version (e.g. '2503.412').

.EXAMPLE
    $version = Test-EvergreenModule
    # Returns '2503.412' or throws if not installed.
#>
function Test-EvergreenModule {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $module = Get-Module -Name 'Evergreen' -ListAvailable -ErrorAction SilentlyContinue |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

    if ($null -eq $module) {
        throw (
            'The Evergreen PowerShell module is not installed. ' +
            'Install it with: Install-Module -Name Evergreen -Scope CurrentUser'
        )
    }

    return $module.Version.ToString()
}
