#Requires -Version 5.1

Describe 'Module manifest' -Tag 'Unit' {
    BeforeAll {
        $script:manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    }

    It 'Has a valid module manifest' {
        { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Exports only Start-EvergreenWorkbench' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        $manifest.FunctionsToExport | Should -Be @('Start-EvergreenWorkbench')
    }
}