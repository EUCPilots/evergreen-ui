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
        $manifest.Version.ToString() | Should -Be '2.0.3'
        $manifest.PrivateData.PSData.Prerelease | Should -Be 'preview'
        $manifest.PrivateData.PSData.ExternalModuleDependencies | Should -Contain 'IntuneWin32App'
        Get-Command -Name Get-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Set-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Reset-EwSetting -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EwApp -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EwFilterableProperty -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Save-EwArtifact -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EwLibrary -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Update-EwLibrary -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Start-EwJob -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EwJob -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Stop-EwJob -Module EvergreenUI | Should -Not -BeNullOrEmpty
        Get-Command -Name Remove-EwJob -Module EvergreenUI | Should -Not -BeNullOrEmpty
    }

    It 'uses defaults without reading other settings or writing a file' {
        $otherSettingsPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI'
        New-Item -Path $otherSettingsPath -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $otherSettingsPath -ChildPath 'settings.json') -Value '{"Theme":"Dark"}'
        $settings = Get-EwSetting
        $settings.Theme | Should -Be 'System'
        $settings.SchemaVersion | Should -Be 1
        Test-Path -Path (Join-Path -Path $env:APPDATA -ChildPath 'EvergreenWorkbench\settings.json') | Should -BeFalse
    }

    It 'persists changes and resets without removing other settings' {
        $otherSettingsPath = Join-Path -Path $env:APPDATA -ChildPath 'EvergreenUI\settings.json'
        New-Item -Path (Split-Path -Path $otherSettingsPath -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $otherSettingsPath -Value '{"Theme":"Light"}'
        Set-EwSetting -Name Theme -Value Dark
        (Get-EwSetting).Theme | Should -Be 'Dark'
        Reset-EwSetting -Confirm:$false
        (Get-EwSetting).Theme | Should -Be 'System'
        Test-Path -Path $otherSettingsPath | Should -BeTrue
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
        $settings.AppsListWidth | Should -Be 220
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

    It 'records distinct library paths most recent first and keeps ten' {
        (Get-EwSetting).LibraryPathHistory | Should -BeNullOrEmpty
        foreach ($index in 1..11) {
            Set-EwSetting -Name LibraryPath -Value "C:\Library$index"
        }
        Set-EwSetting -Name LibraryPath -Value 'c:\library5'
        Set-EwSetting -Name LibraryPath -Value ''
        $settings = Get-EwSetting
        $settings.LibraryPath | Should -Be ''
        $history = @($settings.LibraryPathHistory)
        $history.Count | Should -Be 10
        $history[0] | Should -BeExactly 'c:\library5'
        $history[1] | Should -Be 'C:\Library11'
        $history | Should -Not -Contain 'C:\Library1'
        @($history | Where-Object { $_ -eq 'C:\Library5' }).Count | Should -Be 1
    }

    It 'persists normalized optional artifact columns and clears the preference' {
        (Get-EwSetting).ArtifactHiddenColumns | Should -Be ''
        Set-EwSetting -Name ArtifactHiddenColumns -Value ' architecture, DATE, Architecture '
        (Get-EwSetting).ArtifactHiddenColumns | Should -BeExactly 'Architecture,Date'
        Set-EwSetting -Name ArtifactHiddenColumns -Value 'Channel' -WhatIf
        (Get-EwSetting).ArtifactHiddenColumns | Should -BeExactly 'Architecture,Date'
        Set-EwSetting -Name ArtifactHiddenColumns -Value ''
        (Get-EwSetting).ArtifactHiddenColumns | Should -Be ''
    }

    It 'persists app-specific hidden properties without case-insensitive duplicates' {
        Set-EwSetting -Name ArtifactHiddenColumns -Value 'Sha256, Size, SHA256'
        (Get-EwSetting).ArtifactHiddenColumns | Should -BeExactly 'Sha256,Size'
    }

    It 'rejects hiding required artifact column <Column>' -ForEach @(
        @{ Column = 'Version' }
        @{ Column = 'uri' }
    ) {
        Set-EwSetting -Name ArtifactHiddenColumns -Value 'Channel'
        { Set-EwSetting -Name ArtifactHiddenColumns -Value "Date,$Column" } |
            Should -Throw '*ArtifactHiddenColumns*'
        (Get-EwSetting).ArtifactHiddenColumns | Should -Be 'Channel'
    }

    It 'defaults, validates and stores typed window and navigation state' {
        $settings = Get-EwSetting
        $settings.StartupView | Should -Be 'Apps'
        $settings.LastAppName | Should -Be ''
        $settings.WindowWidth | Should -Be 1200
        $settings.WindowHeight | Should -Be 820
        $settings.DownloadTrayHeight | Should -Be 180
        $settings.AppsListWidth | Should -Be 220
        $settings.WindowMaximized | Should -BeFalse
        Set-EwSetting -Name StartupView -Value 'nerdio'
        Set-EwSetting -Name WindowWidth -Value '1400'
        Set-EwSetting -Name DownloadTrayHeight -Value '240'
        Set-EwSetting -Name AppsListWidth -Value '330'
        Set-EwSetting -Name WindowMaximized -Value 'True'
        Set-EwSetting -Name LastAppName -Value 'MicrosoftEdge'
        $settings = Get-EwSetting
        $settings.StartupView | Should -BeExactly 'Nerdio'
        $settings.WindowWidth | Should -Be 1400
        $settings.DownloadTrayHeight | Should -Be 240
        $settings.AppsListWidth | Should -Be 330
        [string]$settings.WindowWidth | Should -Match '^\d+$'
        $settings.WindowMaximized | Should -BeTrue
        $settings.LastAppName | Should -Be 'MicrosoftEdge'
        { Set-EwSetting -Name StartupView -Value 'Update' } | Should -Throw '*StartupView*'
        { Set-EwSetting -Name StartupView -Value 'Download' } | Should -Throw
        { Set-EwSetting -Name DownloadTrayHeight -Value '119' } | Should -Throw '*DownloadTrayHeight*'
        { Set-EwSetting -Name DownloadTrayHeight -Value '601' } | Should -Throw '*DownloadTrayHeight*'
        { Set-EwSetting -Name AppsListWidth -Value '159' } | Should -Throw '*AppsListWidth*'
        { Set-EwSetting -Name AppsListWidth -Value 'wide' } | Should -Throw '*whole number*'
        Set-EwSetting -Name AppsListWidth -Value '160'
        (Get-EwSetting).AppsListWidth | Should -Be 160
        { Set-EwSetting -Name WindowHeight -Value '0' } | Should -Throw '*WindowHeight*'
        { Set-EwSetting -Name WindowHeight -Value 'wide' } | Should -Throw '*WindowHeight*'
        { Set-EwSetting -Name WindowMaximized -Value 'maybe' } | Should -Throw '*WindowMaximized*'
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
