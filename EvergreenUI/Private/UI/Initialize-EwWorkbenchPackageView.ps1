Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EwWorkbenchPackageView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $State.PackageDefinitions = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $State.PackageDefinitionsListView.ItemsSource = $State.PackageDefinitions
    $State.PackageDefinitionsLoadAttempted = $false
    $State.PackageDefinitionsLoadPending = $false
    $State.PackageDefinitionsJobPath = ''
    $State.LoadPackageDefinitionsButton.IsEnabled = -not [string]::IsNullOrWhiteSpace([string]$State.IntuneDefinitionsPathBox.Text)
    $State.UpdatePackageDefinitionsButton.IsEnabled = $false

    $State.PackageDefinitionsListView.Add_SelectionChanged({
        $details = @(& $State.ModuleInvoker -Name 'Get-EwWorkbenchPackageDefinitionSummary' -Parameters @{
            Definition = $State.PackageDefinitionsListView.SelectedItem
        })
        $paragraph = [System.Windows.Documents.Paragraph]::new()
        $paragraph.Margin = [System.Windows.Thickness]::new(0)
        foreach ($detail in $details) {
            if ($paragraph.Inlines.Count -gt 0) {
                $paragraph.Inlines.Add([System.Windows.Documents.Run]::new("`r`n`r`n"))
            }
            if (-not [string]::IsNullOrWhiteSpace($detail.Label)) {
                $paragraph.Inlines.Add([System.Windows.Documents.Run]::new("$($detail.Label):`r`n"))
            }
            $value = [System.Windows.Documents.Run]::new($detail.Value)
            if ($detail.IsFilter) {
                $value.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
            }
            $paragraph.Inlines.Add($value)
        }
        $State.PackageDefinitionDetailsText.Document.Blocks.Clear()
        $State.PackageDefinitionDetailsText.Document.Blocks.Add($paragraph)
    }.GetNewClosure())

    $State.IntuneDefinitionsPathBox.Add_TextChanged({
        $State.PackageDefinitions.Clear()
        $State.PackageDefinitionsCountLabel.Text = 'Definitions need refresh'
        $State.UpdatePackageDefinitionsButton.IsEnabled = $false
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallStale' -Parameters @{ State = $State }
        $State.LoadPackageDefinitionsButton.IsEnabled =
            -not [string]::IsNullOrWhiteSpace([string]$State.IntuneDefinitionsPathBox.Text) -and
            $null -eq $State.ActiveJobId
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchInstallRefresh' -Parameters @{ State = $State }
    }.GetNewClosure())

    $State.IntuneDefinitionsPathBox.Add_LostKeyboardFocus({
        if ($args[1].NewFocus -in @(
                $State.BrowseIntuneDefinitionsButton,
                $State.SaveIntuneDefinitionsPathButton,
                $State.LoadPackageDefinitionsButton
            )) {
            return
        }
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchPackageDefinitionsLoad' -Parameters @{ State = $State; Automatic = $true }
    }.GetNewClosure())
    $State.PackagesTabControl.Add_SelectionChanged({
        if ($args[1].Source -eq $State.PackagesTabControl -and $State.DefinitionsTab.IsSelected) {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchPackageDefinitionsLoad' -Parameters @{ State = $State; Automatic = $true }
        }
    }.GetNewClosure())

    $State.BrowseIntuneDefinitionsButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select the Intune package definitions folder'
        if (-not [string]::IsNullOrWhiteSpace($State.IntuneDefinitionsPathBox.Text) -and
            (Test-Path -LiteralPath $State.IntuneDefinitionsPathBox.Text -PathType Container)) {
            $dialog.InitialDirectory = $State.IntuneDefinitionsPathBox.Text
        }
        if ($dialog.ShowDialog($State.Window)) {
            $State.IntuneDefinitionsPathBox.Text = $dialog.FolderName
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchPackageDefinitionsLoad' -Parameters @{ State = $State; Automatic = $true }
        }
    }.GetNewClosure())

    $State.SaveIntuneDefinitionsPathButton.Add_Click({
        $path = [string]$State.IntuneDefinitionsPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{
                Name = 'IntuneDefinitionsPath'
                Value = $path
            }
            $State.Settings.IntuneDefinitionsPath = $path
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = 'Intune definitions folder saved.'
            }
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchPackageDefinitionsLoad' -Parameters @{ State = $State; Automatic = $true }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not save Intune definitions folder: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.LoadPackageDefinitionsButton.Add_Click({
        & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchPackageDefinitionsLoad' -Parameters @{ State = $State }
    }.GetNewClosure())

    $State.UpdatePackageDefinitionsButton.Add_Click({
        $path = [string]$State.IntuneDefinitionsPathBox.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = 'Set the Intune definitions folder before updating definitions.'
                Level = 'Warning'
            }
            return
        }
        try {
            & $State.ModuleInvoker -Name 'Invoke-EwWorkbenchJob' -Parameters @{
                State = $State
                Kind = 'DefinitionUpdate'
                Name = 'Update Intune package definitions'
                ScriptBlock = {
                    param($DefinitionPath)
                    $definitions = @(Get-EwDefinition -Path $DefinitionPath)
                    $results = foreach ($definition in $definitions | Where-Object Status -eq 'Valid') {
                        try {
                            $result = Update-EwDefinition -DefinitionPath $definition.DefinitionPath -Confirm:$false
                            foreach ($item in @($result)) {
                                [PSCustomObject]@{
                                    Name = $definition.Name
                                    DefinitionPath = $definition.DefinitionPath
                                    Succeeded = [bool]$item.Succeeded
                                    NoUpdateNeeded = [bool]$item.NoUpdateNeeded
                                    OldVersion = [string]$item.OldVersion
                                    NewVersion = [string]$item.NewVersion
                                    Error = [string]$item.Error
                                }
                            }
                        }
                        catch {
                            [PSCustomObject]@{
                                Name = $definition.Name
                                DefinitionPath = $definition.DefinitionPath
                                Succeeded = $false
                                NoUpdateNeeded = $false
                                OldVersion = [string]$definition.Version
                                NewVersion = [string]$definition.Version
                                Error = $_.Exception.Message
                            }
                        }
                    }
                    [PSCustomObject]@{
                        Items = @(Get-EwDefinition -Path $DefinitionPath)
                        Results = @($results)
                    }
                }
                ArgumentList = @($path)
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not update Intune definitions: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())

    $State.BrowsePackageOutputPathButton.Add_Click({
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select the Intune package output folder'
        if (-not [string]::IsNullOrWhiteSpace($State.PackageOutputPathBox.Text) -and
            (Test-Path -LiteralPath $State.PackageOutputPathBox.Text -PathType Container)) {
            $dialog.InitialDirectory = $State.PackageOutputPathBox.Text
        }
        if ($dialog.ShowDialog($State.Window)) {
            $State.PackageOutputPathBox.Text = $dialog.FolderName
        }
    }.GetNewClosure())

    $State.SavePackageOutputPathButton.Add_Click({
        $path = [string]$State.PackageOutputPathBox.Text
        try {
            & $State.ModuleInvoker -Name 'Set-EwSetting' -Parameters @{
                Name = 'PackageOutputPath'
                Value = $path
            }
            $State.Settings.PackageOutputPath = $path
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = 'Package output folder saved.'
            }
        }
        catch {
            & $State.ModuleInvoker -Name 'Write-EwWorkbenchLog' -Parameters @{
                State = $State
                Message = "Could not save package output folder: $($_.Exception.Message)"
                Level = 'Error'
            }
        }
    }.GetNewClosure())
}
