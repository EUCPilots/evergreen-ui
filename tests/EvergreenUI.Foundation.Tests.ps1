#Requires -Version 7.6

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'EvergreenUI v2 foundation' {
    BeforeEach {
        $originalAppData = $env:APPDATA
        $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        New-Item -Path $env:APPDATA -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        $env:APPDATA = $originalAppData
    }

    It 'imports the implemented public commands from a valid preview manifest' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        $manifest.Version.ToString() | Should -Be '2.0.0'
        $manifest.PrivateData.PSData.Prerelease | Should -Be 'preview'
        $manifest.PrivateData.PSData.ExternalModuleDependencies | Should -Contain 'IntuneWin32App'
        Get-Command -Name Get-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Set-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Reset-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
    }

    It 'uses fresh defaults without reading v1 settings or writing a file' {
        $v1Path = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        New-Item -Path $v1Path -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $v1Path -ChildPath 'settings.json') -Value '{"Theme":"Dark"}'
        $settings = Get-EwSetting
        $settings.Theme | Should -Be 'System'
        $settings.SchemaVersion | Should -Be 1
        Test-Path -Path (Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\settings.json') | Should -BeFalse
    }

    It 'persists changes and resets v2 without removing v1 settings' {
        $v1Path = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\settings.json'
        New-Item -Path (Split-Path -Path $v1Path -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $v1Path -Value '{"Theme":"Light"}'
        Set-EwSetting -Name Theme -Value Dark
        (Get-EwSetting).Theme | Should -Be 'Dark'
        Reset-EwSetting -Confirm:$false
        (Get-EwSetting).Theme | Should -Be 'System'
        Test-Path -Path $v1Path | Should -BeTrue
    }

    It 'does not write or reset when WhatIf is specified' {
        Set-EwSetting -Name Theme -Value Dark -WhatIf
        (Get-EwSetting).Theme | Should -Be 'System'
        Set-EwSetting -Name Theme -Value Dark
        Reset-EwSetting -WhatIf
        (Get-EwSetting).Theme | Should -Be 'Dark'
    }

    It 'fills missing defaults while retaining unknown keys' {
        $directory = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench'
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $directory -ChildPath 'settings.json') -Value '{"SchemaVersion":1,"Future":"retained"}'
        $settings = Get-EwSetting
        $settings.Theme | Should -Be 'System'
        Set-EwSetting -Name Theme -Value Light
        (Get-EwSetting).Future | Should -Be 'retained'
    }

    It 'reports corrupt or unsupported settings rather than overwriting them' {
        $directory = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench'
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
        $path = Join-Path -Path $directory -ChildPath 'settings.json'
        Set-Content -Path $path -Value '{"SchemaVersion":2}'
        { Set-EwSetting -Name Theme -Value Dark } | Should -Throw '*schema*'
        Get-Content -Path $path -Raw | Should -Match '"SchemaVersion":2'
        Set-Content -Path $path -Value '{invalid'
        { Get-EwSetting } | Should -Throw
    }

    It 'rejects invalid theme values' {
        { Set-EwSetting -Name Theme -Value Blue } | Should -Throw '*Theme*'
    }
}

Describe 'Optional module checks' {
    It 'explains how to install an unavailable module' {
        InModuleScope EvergreenUI {
            Mock Get-Module { @() }
            { Assert-EwModule -Name Az.Storage } | Should -Throw '*Install-Module*Az.Storage*'
        }
    }

    It 'imports the requested module when available' {
        InModuleScope EvergreenUI {
            Mock Get-Module { [PSCustomObject]@{ Name = 'Az.Storage' } }
            Mock Import-Module {}
            Assert-EwModule -Name Az.Storage
            Should -Invoke Import-Module -Exactly 1 -ParameterFilter { $Name -eq 'Az.Storage' }
        }
    }

    It 'surfaces an optional module import failure' {
        InModuleScope EvergreenUI {
            Mock Get-Module { [PSCustomObject]@{ Name = 'Az.Storage' } }
            Mock Import-Module { throw 'Import failed' }
            { Assert-EwModule -Name Az.Storage } | Should -Throw '*Import failed*'
        }
    }
}
