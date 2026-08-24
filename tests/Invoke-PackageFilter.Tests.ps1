#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Invoke-PackageFilter' -Tag 'Unit' {
    It 'Executes the supported Evergreen predicate and selection pipeline' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp {
                @(
                    [PSCustomObject]@{ Version = '1.0'; Type = 'exe' }
                    [PSCustomObject]@{ Version = '2.0'; Type = 'intunewin' }
                    [PSCustomObject]@{ Version = '3.0'; Type = 'intunewin' }
                )
            }

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name "WindowsEnterpriseDefaults" | Where-Object { $_.Type -eq "intunewin" } | Select-Object -First 1'

            $result.Succeeded | Should -BeTrue
            $result.Results | Should -HaveCount 1
            $result.Results[0].Version | Should -Be '2.0'
            Should -Invoke -CommandName Get-EvergreenApp -Times 1 -Exactly -ParameterFilter { $Name -eq 'WindowsEnterpriseDefaults' }
        }
    }

    It 'Executes supported VcRedist predicates and sorting' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-VcList {
                @(
                    [PSCustomObject]@{ Version = [version]'1.0'; Architecture = 'x64' }
                    [PSCustomObject]@{ Version = [version]'3.0'; Architecture = 'x86' }
                    [PSCustomObject]@{ Version = [version]'2.0'; Architecture = 'x64' }
                )
            }

            $result = Invoke-PackageFilter -FilterExpression 'Get-VcList -Release 2019 -Architecture x64 | Where-Object { $_.Architecture -eq "x64" } | Sort-Object -Property Version -Descending | Select-Object -First 1'

            $result.Succeeded | Should -BeTrue
            $result.Results[0].Version | Should -Be ([version]'2.0')
            Should -Invoke -CommandName Get-VcList -Times 1 -Exactly -ParameterFilter {
                $Release -eq 2019 -and $Architecture -eq 'x64'
            }
        }
    }

    It 'Supports combined literal property predicates' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp {
                @(
                    [PSCustomObject]@{ Channel = 'Stable'; Architecture = 'x64' }
                    [PSCustomObject]@{ Channel = 'Beta'; Architecture = 'x64' }
                )
            }

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name Test | Where-Object { $_.Channel -eq "Stable" -and $_.Architecture -like "x*" }'

            $result.Succeeded | Should -BeTrue
            $result.Results | Should -HaveCount 1
            $result.Results[0].Channel | Should -Be 'Stable'
        }
    }

    It 'Passes a safe literal ErrorAction to Get-EvergreenApp' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp {
                [PSCustomObject]@{ Version = '1.0' }
            }

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name "FoxitReader" -ErrorAction "SilentlyContinue"'

            $result.Succeeded | Should -BeTrue
            Should -Invoke -CommandName Get-EvergreenApp -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'FoxitReader' -and $ErrorAction -eq 'SilentlyContinue'
            }
        }
    }

    It 'Rejects interactive ErrorAction values without invoking the source' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name Test -ErrorAction Inquire'

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match "ErrorAction 'Inquire' is not supported"
            Should -Invoke -CommandName Get-EvergreenApp -Times 0 -Exactly
        }
    }

    It 'Passes a safe literal WarningAction to Get-EvergreenApp' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp {
                [PSCustomObject]@{ Version = '1.0' }
            }

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name "NotepadPlusPlus" -WarningAction "SilentlyContinue"'

            $result.Succeeded | Should -BeTrue
            Should -Invoke -CommandName Get-EvergreenApp -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'NotepadPlusPlus' -and $WarningAction -eq 'SilentlyContinue'
            }
        }
    }

    It 'Rejects interactive WarningAction values without invoking the source' {
        InModuleScope EvergreenUI {
            Mock -CommandName Get-EvergreenApp

            $result = Invoke-PackageFilter -FilterExpression 'Get-EvergreenApp -Name Test -WarningAction Inquire'

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match "WarningAction 'Inquire' is not supported"
            Should -Invoke -CommandName Get-EvergreenApp -Times 0 -Exactly
        }
    }

    It 'Rejects unsafe expressions without invoking an approved source' -ForEach @(
        @{ Expression = 'Get-EvergreenApp -Name Test; Get-Process' }
        @{ Expression = '& Get-EvergreenApp -Name Test' }
        @{ Expression = '. Get-EvergreenApp -Name Test' }
        @{ Expression = 'Get-EvergreenApp -Name $(Get-Process)' }
        @{ Expression = 'Get-EvergreenApp -Name $env:TEMP' }
        @{ Expression = 'Get-EvergreenApp -Name ([System.IO.File]::ReadAllText("x"))' }
        @{ Expression = 'Get-EvergreenApp -Name Test > output.txt' }
        @{ Expression = 'Get-VcList -Export output.xml' }
        @{ Expression = 'Get-EvergreenApp -Name Test | ForEach-Object { Remove-Item $_.URI }' }
    ) {
        InModuleScope EvergreenUI -Parameters @{ FilterExpression = $Expression } {
            Mock -CommandName Get-EvergreenApp
            Mock -CommandName Get-VcList

            $result = Invoke-PackageFilter -FilterExpression $FilterExpression

            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'rejected|not supported'
            Should -Invoke -CommandName Get-EvergreenApp -Times 0 -Exactly
            Should -Invoke -CommandName Get-VcList -Times 0 -Exactly
        }
    }

    It 'Rejects <SideEffect> side effects without executing any command' -ForEach @(
        @{
            SideEffect = 'process'
            Expression = 'Get-EvergreenApp -Name Test; Start-Process -FilePath calc.exe'
        }
        @{
            SideEffect = 'file'
            Expression = 'Get-EvergreenApp -Name Test | ForEach-Object { Set-Content -LiteralPath "owned.txt" -Value $_.URI }'
        }
        @{
            SideEffect = 'network'
            Expression = 'Get-EvergreenApp -Name Test | ForEach-Object { Invoke-WebRequest -Uri $_.URI }'
        }
    ) {
        InModuleScope EvergreenUI -Parameters @{ FilterExpression = $Expression } {
            Mock -CommandName Get-EvergreenApp
            Mock -CommandName Get-VcList
            Mock -CommandName Start-Process
            Mock -CommandName Set-Content
            Mock -CommandName Invoke-WebRequest

            $result = Invoke-PackageFilter -FilterExpression $FilterExpression

            $result.Succeeded | Should -BeFalse
            Should -Invoke -CommandName Get-EvergreenApp -Times 0 -Exactly
            Should -Invoke -CommandName Get-VcList -Times 0 -Exactly
            Should -Invoke -CommandName Start-Process -Times 0 -Exactly
            Should -Invoke -CommandName Set-Content -Times 0 -Exactly
            Should -Invoke -CommandName Invoke-WebRequest -Times 0 -Exactly
        }
    }
}
