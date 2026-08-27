#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Register-DownloadFeature' -Tag 'Unit' {
    It 'Starts queued downloads from a delayed callback without resolving New-WpfRunspace by name' {
        $syncHash = InModuleScope EvergreenUI {
            Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

            function Get-MockWpfControl {
                param([hashtable]$Property = @{})

                $control = [PSCustomObject]$Property
                $control | Add-Member -MemberType ScriptMethod -Name add_Click -Value {
                    param($Handler)
                    $this.ClickHandler = $Handler
                } -Force
                $control | Add-Member -MemberType ScriptMethod -Name AddHandler -Value {
                    param($RoutedEvent, $Handler, $HandledEventsToo)
                    [void]$RoutedEvent
                    [void]$Handler
                    [void]$HandledEventsToo
                } -Force
                return $control
            }

            $outputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString('N'))
            $downloadAllButton = Get-MockWpfControl -Property @{ IsEnabled = $true; ClickHandler = $null }
            $queueListView = Get-MockWpfControl -Property @{ ItemsSource = $null; SelectedItem = $null }
            $queueListView | Add-Member -MemberType NoteProperty -Name Items -Value (Get-MockWpfControl) -Force
            $queueListView.Items | Add-Member -MemberType ScriptMethod -Name Refresh -Value {} -Force

            $syncHash = [hashtable]::Synchronized(@{
                    Config                     = [PSCustomObject]@{ OutputPath = $outputPath }
                    DownloadAllButton          = $downloadAllButton
                    DownloadProgressBar        = Get-MockWpfControl -Property @{ Visibility = 'Collapsed'; IsIndeterminate = $false }
                    DownloadQueue              = [System.Collections.Generic.List[PSCustomObject]]::new()
                    DownloadQueueListView      = $queueListView
                    DownloadQueueSortDirection = 'Ascending'
                    DownloadQueueSortProperty  = ''
                    IsRunning                  = $false
                    QueueCountLabel            = Get-MockWpfControl -Property @{ Text = '' }
                    TestRunspaceCreated        = $false
                })
            $syncHash.DownloadQueue.Add([PSCustomObject]@{
                    AppName      = 'TestApp'
                    Version      = '1.0'
                    Architecture = ''
                    Channel      = ''
                    Platform     = ''
                    Uri          = 'https://example.test/test.exe'
                    Status       = 'Pending'
                    Path         = ''
                })
            $syncHash['SetUIConfig'] = {
                param($Config)
                [void]$Config
            }
            $syncHash['WriteUILog'] = {
                param([hashtable]$SyncHash, [string]$Message, [string]$Level = 'Info')
                [void]$SyncHash
                [void]$Message
                [void]$Level
            }

            $controls = @{
                ClearQueueButton         = $null
                OpenDownloadFolderButton = $null
                OutputPathBox            = Get-MockWpfControl -Property @{ Text = $outputPath }
                RemoveQueueItemButton    = $null
            }

            Register-DownloadFeature -SyncHash $syncHash -Controls $controls
            $syncHash['NewWpfRunspace'] = {
                param([hashtable]$SyncHash)
                $SyncHash.TestRunspaceCreated = $true
                throw 'RUNSPACE_CREATED'
            }

            return $syncHash
        }

        try {
            { & $syncHash.DownloadAllButton.ClickHandler } | Should -Throw '*RUNSPACE_CREATED*'
            $syncHash.TestRunspaceCreated | Should -BeTrue
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace([string]$syncHash.Config.OutputPath) -and
                (Test-Path -LiteralPath ([string]$syncHash.Config.OutputPath))) {
                Remove-Item -LiteralPath ([string]$syncHash.Config.OutputPath) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
