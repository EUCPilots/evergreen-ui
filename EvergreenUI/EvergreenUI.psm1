#Requires -Version 7.6
<#
.SYNOPSIS
    EvergreenUI - WPF graphical frontend for the Evergreen PowerShell module.

.DESCRIPTION
    Root module file. Loads private helpers before public functions.

.NOTES
    - Windows only. The headless commands do not load WPF.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ewNerdioContext = $null

foreach ($directory in @('Private', 'Public')) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $directory
    if (Test-Path -LiteralPath $path -PathType Container) {
        Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File -Recurse |
            Sort-Object -Property FullName |
            ForEach-Object { . $_.FullName }
    }

    $script:ewJobs = @{}
    $script:ewAppCatalogCache = @{
        RetrievedAt = $null
        Items = @()
    }
    $script:ewRunspacePool = $null
    $script:ewModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'EvergreenUI.psd1'

    $ExecutionContext.SessionState.Module.OnRemove = {
        foreach ($job in $script:ewJobs.Values) {
            try {
                if (-not $job.Handle.IsCompleted) {
                    $job.PowerShell.Stop()
                }
            }
            finally {
                $job.PowerShell.Dispose()
            }
        }
        if ($null -ne $script:ewRunspacePool) {
            $script:ewRunspacePool.Dispose()
        }
    }
}
