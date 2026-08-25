#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Set-LoadingState' -Tag 'Unit' {
    It 'Captures button state and shows loading controls while loading' {
        InModuleScope EvergreenUI {
            $button = [PSCustomObject]@{ Name = 'Action'; IsEnabled = $true }
            $panel = [PSCustomObject]@{ Visibility = 'Collapsed' }
            $progress = [PSCustomObject]@{ Visibility = 'Collapsed' }
            $loadingLabel = [PSCustomObject]@{ Text = 'Idle' }
            $statusLabel = [PSCustomObject]@{ Text = '' }
            $buttonStates = @{}

            Set-LoadingState -ButtonStates $buttonStates -IsLoading $true -Buttons $button `
                -LoadingControls @($panel, $progress) -LoadingLabel $loadingLabel `
                -LoadingMessage 'Fetching apps...' -StatusLabel $statusLabel

            $button.IsEnabled | Should -BeFalse
            $buttonStates['Action'] | Should -BeTrue
            $panel.Visibility | Should -Be 'Visible'
            $progress.Visibility | Should -Be 'Visible'
            $loadingLabel.Text | Should -Be 'Fetching apps...'
            $statusLabel.Text | Should -Be 'Fetching apps...'
        }
    }

    It 'Restores button state and hides loading controls when complete' {
        InModuleScope EvergreenUI {
            $button = [PSCustomObject]@{ Name = 'Action'; IsEnabled = $true }
            $panel = [PSCustomObject]@{ Visibility = 'Collapsed' }
            $loadingLabel = [PSCustomObject]@{ Text = 'Idle' }
            $statusLabel = [PSCustomObject]@{ Text = 'Working' }
            $buttonStates = @{}

            Set-LoadingState -ButtonStates $buttonStates -IsLoading $true -Buttons $button -LoadingControls $panel
            $button.IsEnabled = $false
            Set-LoadingState -ButtonStates $buttonStates -IsLoading $false -Buttons $button `
                -LoadingControls $panel -LoadingLabel $loadingLabel -IdleLoadingMessage 'Ready' `
                -StatusLabel $statusLabel

            $button.IsEnabled | Should -BeTrue
            $buttonStates.Count | Should -Be 0
            $panel.Visibility | Should -Be 'Collapsed'
            $loadingLabel.Text | Should -Be 'Ready'
            $statusLabel.Text | Should -BeNullOrEmpty
        }
    }
}