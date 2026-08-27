#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
}

Describe 'Theme callbacks' -Tag 'Unit' {
    It 'Applies light and dark themes from captured callbacks outside module scope' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $runspace = [RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = [Threading.ApartmentState]::STA
        $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseCurrentThread
        $pipeline = [PowerShell]::Create()
        $pipeline.Runspace = $runspace

        try {
            $runspace.Open()
            $null = $pipeline.AddScript({
                    param([string]$ModulePath)

                    Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop
                    Import-Module -Name $ModulePath -Force -ErrorAction Stop
                    $callbacks = InModuleScope EvergreenUI {
                        [PSCustomObject]@{
                            Light = ${function:Set-LightTheme}.GetNewClosure()
                            Dark  = ${function:Set-DarkTheme}.GetNewClosure()
                        }
                    }

                    $window = [System.Windows.Window]::new()
                    & $callbacks.Light -Window $window
                    $lightBackground = [string]$window.Resources['WindowBackgroundBrush'].Color

                    & $callbacks.Dark -Window $window
                    $darkBackground = [string]$window.Resources['WindowBackgroundBrush'].Color

                    [PSCustomObject]@{
                        LightBackground = $lightBackground
                        DarkBackground  = $darkBackground
                    }
                }).AddArgument($script:modulePath)

            $result = @($pipeline.Invoke())

            $pipeline.HadErrors | Should -BeFalse -Because ($pipeline.Streams.Error -join [Environment]::NewLine)
            $result | Should -HaveCount 1
            $result[0].LightBackground | Should -Be '#FFF3F4F4'
            $result[0].DarkBackground | Should -Be '#FF202020'
        }
        finally {
            $pipeline.Dispose()
            $runspace.Dispose()
        }
    }
}