#Requires -Version 5.1

BeforeAll {
    Add-Type -AssemblyName PresentationFramework

    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Set-ListViewSort' -Tag 'Unit' {
    It 'Sorts an ascending source by the requested property' {
        InModuleScope EvergreenUI {
            $listView = [System.Windows.Controls.ListView]::new()
            $listView.ItemsSource = @(
                [PSCustomObject]@{ Name = 'Bravo' }
                [PSCustomObject]@{ Name = 'Alpha' }
            )

            Set-ListViewSort -ListView $listView -Property 'Name' -Direction 'Ascending' | Should -BeTrue
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
            @($view)[0].Name | Should -Be 'Alpha'
            $view.SortDescriptions[0].PropertyName | Should -Be 'Name'
            $view.SortDescriptions[0].Direction |
                Should -Be ([System.ComponentModel.ListSortDirection]::Ascending)
        }
    }

    It 'Sorts a descending source by the requested property' {
        InModuleScope EvergreenUI {
            $listView = [System.Windows.Controls.ListView]::new()
            $listView.ItemsSource = @(
                [PSCustomObject]@{ Name = 'Alpha' }
                [PSCustomObject]@{ Name = 'Bravo' }
            )

            Set-ListViewSort -ListView $listView -Property 'Name' -Direction 'Descending' | Should -BeTrue
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
            $view.SortDescriptions[0].Direction |
                Should -Be ([System.ComponentModel.ListSortDirection]::Descending)
        }
    }

    It 'Does nothing for an empty source' {
        InModuleScope EvergreenUI {
            $listView = [System.Windows.Controls.ListView]::new()
            $listView.ItemsSource = @()

            Set-ListViewSort -ListView $listView -Property 'Name' | Should -BeFalse
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
            $view.SortDescriptions | Should -HaveCount 0
        }
    }

    It 'Does nothing when the property is missing' {
        InModuleScope EvergreenUI {
            $listView = [System.Windows.Controls.ListView]::new()
            $listView.ItemsSource = @([PSCustomObject]@{ Name = 'Alpha' })

            Set-ListViewSort -ListView $listView -Property 'Missing' | Should -BeFalse
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listView.ItemsSource)
            $view.SortDescriptions | Should -HaveCount 0
        }
    }

    It 'Does nothing when the property is blank' {
        InModuleScope EvergreenUI {
            $listView = [System.Windows.Controls.ListView]::new()
            $listView.ItemsSource = @([PSCustomObject]@{ Name = 'Alpha' })

            Set-ListViewSort -ListView $listView -Property '' | Should -BeFalse
        }
    }
}