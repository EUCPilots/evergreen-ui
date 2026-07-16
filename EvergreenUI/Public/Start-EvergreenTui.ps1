function Start-EvergreenTui {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if (-not $PSCmdlet.ShouldProcess('Terminal session', 'Start Evergreen TUI')) {
        return
    }

    Test-EvergreenModule | Out-Null

    $terminalGuiRoot = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Resources\TerminalGui'
    $terminalGuiAssemblyPath = Join-Path -Path $terminalGuiRoot -ChildPath 'Terminal.Gui.dll'
    $nStackAssemblyPath = Join-Path -Path $terminalGuiRoot -ChildPath 'NStack.dll'
    $systemManagementAssemblyPath = Join-Path -Path $terminalGuiRoot -ChildPath 'System.Management.dll'

    foreach ($requiredAssemblyPath in @($terminalGuiAssemblyPath, $nStackAssemblyPath, $systemManagementAssemblyPath)) {
        if (-not (Test-Path -LiteralPath $requiredAssemblyPath -PathType Leaf)) {
            throw "Bundled TUI dependency not found: $requiredAssemblyPath"
        }
    }

    foreach ($assemblyPath in @($nStackAssemblyPath, $systemManagementAssemblyPath, $terminalGuiAssemblyPath)) {
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($assemblyPath)
        $isLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $assemblyName } |
        Select-Object -First 1
        if ($null -ne $isLoaded) {
            continue
        }

        [void][System.Reflection.Assembly]::LoadFrom($assemblyPath)
    }

    if (-not ('Terminal.Gui.Application' -as [type])) {
        throw 'Bundled Terminal.Gui assembly loaded, but required type Terminal.Gui.Application was not found.'
    }

    $state = [ordered]@{
        Apps = @()
    }

    $convertResultsToText = {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [object[]]$Rows
        )

        if ($Rows.Count -eq 0) {
            return 'No versions returned for the selected application.'
        }

        $propertyNames = @($Rows[0].PSObject.Properties.Name)
        if ($propertyNames.Count -eq 0) {
            return 'No displayable properties were returned for the selected application.'
        }

        $orderedColumns = [System.Collections.Generic.List[string]]::new()
        if ($propertyNames -contains 'Version') {
            $orderedColumns.Add('Version')
        }

        foreach ($name in ($propertyNames | Sort-Object)) {
            if ($name -in @('Version', 'URI')) {
                continue
            }
            $orderedColumns.Add([string]$name)
        }

        if ($propertyNames -contains 'URI') {
            $orderedColumns.Add('URI')
        }

        $selectedRows = $Rows | Select-Object -Property @($orderedColumns)
        return ($selectedRows | Format-Table -AutoSize | Out-String -Width 4096).TrimEnd()
    }

    [Terminal.Gui.Application]::Init()

    try {
        # Set explicit color schemes to avoid null/default driver attributes in some hosts.
        $baseScheme = [Terminal.Gui.ColorScheme]::new()
        $baseScheme.Normal = [Terminal.Gui.Attribute]::Make(
            [Terminal.Gui.Color]::Black,
            [Terminal.Gui.Color]::Green
        )
        $baseScheme.Focus = [Terminal.Gui.Attribute]::Make(
            [Terminal.Gui.Color]::Black,
            [Terminal.Gui.Color]::Green
        )
        $baseScheme.HotNormal = [Terminal.Gui.Attribute]::Make(
            [Terminal.Gui.Color]::Black,
            [Terminal.Gui.Color]::Green
        )
        $baseScheme.HotFocus = [Terminal.Gui.Attribute]::Make(
            [Terminal.Gui.Color]::Black,
            [Terminal.Gui.Color]::Green
        )
        $baseScheme.Disabled = [Terminal.Gui.Attribute]::Make(
            [Terminal.Gui.Color]::Black,
            [Terminal.Gui.Color]::Green
        )

        [Terminal.Gui.Colors]::Base = $baseScheme
        [Terminal.Gui.Colors]::TopLevel = $baseScheme
        [Terminal.Gui.Colors]::Dialog = $baseScheme
        [Terminal.Gui.Colors]::Menu = $baseScheme
        [Terminal.Gui.Colors]::Error = $baseScheme

        $top = [Terminal.Gui.Application]::Top

        $leftPane = [Terminal.Gui.View]::new()
        $leftPane.X = 0
        $leftPane.Y = 0
        $leftPane.Width = 60
        $leftPane.Height = [Terminal.Gui.Dim]::Fill()

        $rightPane = [Terminal.Gui.View]::new()
        $rightPane.X = [Terminal.Gui.Pos]::Right($leftPane)
        $rightPane.Y = 0
        $rightPane.Width = [Terminal.Gui.Dim]::Fill()
        $rightPane.Height = [Terminal.Gui.Dim]::Fill()

        $appsTitleLabel = [Terminal.Gui.Label]::new('Applications')
        $appsTitleLabel.X = 0
        $appsTitleLabel.Y = 0
        $appsTitleLabel.Width = [Terminal.Gui.Dim]::Fill()

        $resultsTitleLabel = [Terminal.Gui.Label]::new('Versions')
        $resultsTitleLabel.X = 0
        $resultsTitleLabel.Y = 0
        $resultsTitleLabel.Width = [Terminal.Gui.Dim]::Fill()

        $appsListView = [Terminal.Gui.ListView]::new()
        $appsListView.X = 0
        $appsListView.Y = 3
        $appsListView.Width = [Terminal.Gui.Dim]::Fill()
        $appsListView.Height = [Terminal.Gui.Dim]::Fill(3)

        $refreshButton = [Terminal.Gui.Button]::new('Refresh')
        $refreshButton.X = 0
        $refreshButton.Y = 1

        $quitButton = [Terminal.Gui.Button]::new('Quit')
        $quitButton.X = [Terminal.Gui.Pos]::Right($refreshButton)
        $quitButton.Y = 1

        $statusLabel = [Terminal.Gui.Label]::new('Ready.')
        $statusLabel.X = 0
        $statusLabel.Y = 1
        $statusLabel.Width = [Terminal.Gui.Dim]::Fill()

        $resultsView = [Terminal.Gui.TextView]::new()
        $resultsView.X = 0
        $resultsView.Y = 2
        $resultsView.Width = [Terminal.Gui.Dim]::Fill()
        $resultsView.Height = [Terminal.Gui.Dim]::Fill()
        $resultsView.ReadOnly = $true
        $resultsView.WordWrap = $false
        $resultsView.Text = 'Select an application from the left and choose Load Selected.'

        $leftPane.Add($appsTitleLabel)
        $leftPane.Add($refreshButton)
        $leftPane.Add($quitButton)
        $leftPane.Add($appsListView)

        $rightPane.Add($resultsTitleLabel)
        $rightPane.Add($statusLabel)
        $rightPane.Add($resultsView)

        $top.Add($leftPane)
        $top.Add($rightPane)

        $refreshCatalog = {
            Write-Verbose -Message 'Evergreen TUI: Refreshing app list from Find-EvergreenApp.'

            try {
                $rawApps = @(Find-EvergreenApp -ErrorAction Stop)
                $state.Apps = @(
                    $rawApps |
                    ForEach-Object {
                        [PSCustomObject]@{
                            Name         = [string]$_.Name
                            FriendlyName = if ($_.PSObject.Properties.Name -contains 'Application' -and -not [string]::IsNullOrWhiteSpace([string]$_.Application)) {
                                [string]$_.Application
                            }
                            else {
                                [string]$_.Name
                            }
                        }
                    } |
                    Sort-Object -Property FriendlyName, Name
                )

                $listSource = [System.Collections.Generic.List[string]]::new()
                foreach ($app in $state.Apps) {
                    $listSource.Add([string]$app.FriendlyName)
                }

                $appsListView.SetSource($listSource)

                if ($state.Apps.Count -gt 0) {
                    $appsListView.SelectedItem = 0
                    $statusLabel.Text = "Loaded $($state.Apps.Count) applications. Press Enter to fetch versions."
                }
                else {
                    $statusLabel.Text = 'No applications were returned by Find-EvergreenApp.'
                    $resultsView.Text = 'No applications are currently available.'
                }
            }
            catch {
                $statusLabel.Text = 'Failed to refresh application list. See verbose output for details.'
                $resultsView.Text = ([string]$_.Exception.Message)
                Write-Verbose -Message "Evergreen TUI: Find-EvergreenApp failed. $($_.Exception.Message)"
            }
        }

        $loadSelectedApp = {
            if ($state.Apps.Count -eq 0) {
                $statusLabel.Text = 'No applications loaded. Choose Refresh first.'
                return
            }

            $selectedIndex = [int]$appsListView.SelectedItem
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $state.Apps.Count) {
                $statusLabel.Text = 'Select an application in the left pane first.'
                return
            }

            $selectedApp = $state.Apps[$selectedIndex]
            $statusLabel.Text = "Loading versions for $($selectedApp.Name)..."
            [Terminal.Gui.Application]::Refresh()

            Write-Verbose -Message "Evergreen TUI: Running Get-EvergreenApp -Name '$($selectedApp.Name)'."

            try {
                $rows = @(Get-EvergreenApp -Name $selectedApp.Name -ErrorAction Stop)
                $resultsView.Text = (& $convertResultsToText -Rows $rows)
                $statusLabel.Text = "Loaded $($rows.Count) rows for $($selectedApp.Name)."
            }
            catch {
                $resultsView.Text = ([string]$_.Exception.Message)
                $statusLabel.Text = "Get-EvergreenApp failed for $($selectedApp.Name). See verbose output for details."
                Write-Verbose -Message "Evergreen TUI: Get-EvergreenApp failed for '$($selectedApp.Name)'. $($_.Exception.Message)"
            }
        }

        $refreshButton.add_Clicked({ & $refreshCatalog })
        $appsListView.add_OpenSelectedItem({ & $loadSelectedApp })
        $quitButton.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })

        & $refreshCatalog

        [Terminal.Gui.Application]::Run()
    }
    finally {
        [Terminal.Gui.Application]::Shutdown()
    }
}
