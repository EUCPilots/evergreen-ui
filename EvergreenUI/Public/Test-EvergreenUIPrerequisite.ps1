#Requires -Version 5.1
<#
.SYNOPSIS
    Checks core and optional EvergreenUI module prerequisites.

.DESCRIPTION
    Checks installed module versions without importing optional dependencies. Missing
    optional modules are reported as actionable warnings and do not fail the check.
#>
function Test-EvergreenUIPrerequisite {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $manifestPath = (Resolve-Path -Path (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'EvergreenUI.psd1')).Path
    return Get-EvergreenUIPrerequisiteStatus -ManifestPath $manifestPath
}