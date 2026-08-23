#Requires -Version 5.1

Describe 'Module import' -Tag 'Integration' {
    It 'Imports from source and exposes the public command' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
        try {
            Import-Module -Name $modulePath -Force -ErrorAction Stop

            Get-Command -Name Start-EvergreenWorkbench -Module EvergreenUI |
                Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
        }
    }
}