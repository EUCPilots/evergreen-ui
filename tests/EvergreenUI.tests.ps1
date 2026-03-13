#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the EvergreenUI module.

.DESCRIPTION
    Run with: Invoke-Pester -Path .\tests\EvergreenUI.tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module from source (not from an installed copy)
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'Has a valid module manifest' {
        $manifestPath = Join-Path $PSScriptRoot '..\EvergreenUI\EvergreenUI.psd1'
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Exports only Start-EvergreenUI' {
        $manifest = Import-PowerShellDataFile -Path (
            Join-Path $PSScriptRoot '..\EvergreenUI\EvergreenUI.psd1'
        )
        $manifest.FunctionsToExport | Should -Be @('Start-EvergreenUI')
    }
}

Describe 'Get-FilterableProperties' {
    BeforeAll {
        # Minimal mock data representing Get-EvergreenApp output
        $script:edgeData = @(
            [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x64'; Type='msi'; URI='https://example.com/edge-x64.msi'; Date='2026-03-01' }
            [PSCustomObject]@{ Version='145.0.0'; Channel='Stable'; Architecture='x86'; Type='msi'; URI='https://example.com/edge-x86.msi'; Date='2026-03-01' }
            [PSCustomObject]@{ Version='145.0.0'; Channel='Beta';   Architecture='x64'; Type='msi'; URI='https://example.com/edge-beta-x64.msi'; Date='2026-03-01' }
        )

        $script:uriOnlyData = @(
            [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app.exe' }
            [PSCustomObject]@{ Version='1.0.0'; URI='https://example.com/app2.msi' }
        )
    }

    It 'Returns filterable properties excluding display-only columns' {
        $result = Get-FilterableProperties -AppResults $edgeData
        $result.Name | Should -Contain 'Architecture'
        $result.Name | Should -Contain 'Channel'
        $result.Name | Should -Contain 'Type'
        $result.Name | Should -Not -Contain 'Version'
        $result.Name | Should -Not -Contain 'URI'
        $result.Name | Should -Not -Contain 'Date'
    }

    It 'Assigns CheckBoxStrip control type when unique value count is <= 6' {
        $result = Get-FilterableProperties -AppResults $edgeData
        $archProp = $result | Where-Object { $_.Name -eq 'Architecture' }
        $archProp.ControlType | Should -Be 'CheckBoxStrip'
    }

    It 'Returns empty array for empty input' {
        $result = Get-FilterableProperties -AppResults @()
        $result | Should -HaveCount 0
    }

    It 'Creates synthetic File type property when Type is absent but URI is present' {
        $result = Get-FilterableProperties -AppResults $uriOnlyData
        $synthetic = $result | Where-Object { $_.IsSynthetic -eq $true }
        $synthetic | Should -Not -BeNullOrEmpty
        $synthetic.DisplayName | Should -BeLike '*derived*'
    }
}

Describe 'Get-UIConfig' {
    It 'Returns a default config object when no config file exists' {
        # Temporarily redirect APPDATA to a temp path with no config file
        $originalAppData = $env:APPDATA
        $env:APPDATA = Join-Path $env:TEMP 'EvergreenUI_TestNoConfig'
        try {
            $config = Get-UIConfig
            $config.Theme        | Should -Be 'Light'
            $config.LogVerbosity | Should -Be 'Normal'
            $config.LogHeight    | Should -Be 150
        }
        finally {
            $env:APPDATA = $originalAppData
        }
    }
}

Describe 'Set-UIConfig and Get-UIConfig round-trip' {
    It 'Persists and retrieves config values correctly' {
        $tempAppData = Join-Path $env:TEMP "EvergreenUI_TestRoundTrip_$(Get-Random)"
        $originalAppData = $env:APPDATA
        $env:APPDATA = $tempAppData
        try {
            $config = Get-UIConfig
            $config.Theme = 'Dark'
            $config.OutputPath = 'C:\TestOutput'
            Set-UIConfig -Config $config

            $loaded = Get-UIConfig
            $loaded.Theme      | Should -Be 'Dark'
            $loaded.OutputPath | Should -Be 'C:\TestOutput'
        }
        finally {
            $env:APPDATA = $originalAppData
            Remove-Item -Path $tempAppData -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
