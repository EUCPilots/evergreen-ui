Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchNerdioPruneDialog {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Owner,

        [Parameter(Mandatory)]
        [object[]]$Plans
    )

    $moduleRoot = Split-Path -Path $script:ewModulePath -Parent
    $xamlPath = Join-Path -Path $moduleRoot -ChildPath 'Resources\NerdioPruneDialog.xaml'
    Write-Verbose -Message "EvergreenUI: Loading Nerdio pruning dialog from $xamlPath"
    $reader = [System.Xml.XmlReader]::Create($xamlPath)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if ($window -isnot [System.Windows.Window]) {
        throw "Nerdio pruning XAML did not create a WPF Window: $xamlPath"
    }
    $window.Owner = $Owner
    $window.ThemeMode = $Owner.ThemeMode
    $window.FontFamily = $Owner.FontFamily
    $window.FontSize = [Math]::Max(14, $Owner.FontSize)
    if ($Owner.ActualWidth -gt 0) {
        $window.MaxWidth = [Math]::Max($window.MinWidth, [Math]::Min(920, $Owner.ActualWidth - 64))
    }
    if ($Owner.ActualHeight -gt 0) {
        $window.MaxHeight = [Math]::Max(240, [Math]::Min(640, $Owner.ActualHeight - 64))
    }
    Initialize-EwWorkbenchWindowAppearance -Window $window

    $retentionLabel = $window.FindName('NerdioPruneRetentionText')
    $retentionLabel.Text = if (@($Plans | Where-Object { $_.PublishedVersion }).Count -gt 0) {
        'Keep newest versions (including the newly published version):'
    } else { 'Keep newest versions:' }
    $retention = $window.FindName('NerdioPruneRetentionBox')
    $help = $window.FindName('NerdioPruneHelpText')
    $list = $window.FindName('NerdioPrunePlansPanel')
    $confirm = $window.FindName('ReviewNerdioPruneButton')
    $newConfirmationDialog = Get-Command -Name New-EwWorkbenchConfirmationDialog -CommandType Function -ErrorAction Stop
    $confirmAction = Get-Command -Name Confirm-EwWorkbenchAction -CommandType Function -ErrorAction Stop

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($plan in $Plans) {
        $plan | Add-Member -NotePropertyName Selected -NotePropertyValue $false -Force
        $check = [System.Windows.Controls.CheckBox]::new()
        $check.Tag = $plan
        $check.IsEnabled = [bool]$plan.Eligible -and @($plan.Remove).Count -gt 0
        $check.HorizontalContentAlignment = 'Stretch'
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.TextWrapping = 'Wrap'
        $check.Content = $label
        $card = [System.Windows.Controls.Border]::new()
        $card.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'NerdioPruneCardStyle')
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $card.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
        $card.Child = $check
        $list.Children.Add($card) | Out-Null
        $rows.Add([PSCustomObject]@{ Plan = $plan; CheckBox = $check })
    }

    $updatePreview = {
        $count = 0
        if (-not [int]::TryParse($retention.Text, [ref]$count) -or $count -lt 1) {
            $help.Text = 'Enter a whole number of at least one.'
            $confirm.IsEnabled = $false
            return
        }
        $confirm.IsEnabled = $true
        foreach ($row in $rows) {
            $plan = $row.Plan
            $plan.KeepVersions = $count
            if ($plan.Eligible) {
                $ordered = @($plan.VersionDetails | Sort-Object -Property SortKey, Name -Descending)
                $keepCount = [Math]::Min($count, $ordered.Count)
                $plan.Keep = [string[]]@($ordered | Select-Object -First $keepCount | ForEach-Object Name)
                $plan.Remove = [string[]]@($ordered | Select-Object -Skip $keepCount | ForEach-Object Name)
                $plan.Message = if ($plan.Remove.Count -eq 0) { 'No versions need removal.' } else { '' }
            }
            $check = $row.CheckBox
            $check.IsEnabled = [bool]$plan.Eligible -and @($plan.Remove).Count -gt 0
            $check.Content.Text = if ($plan.Eligible) {
                $published = if ($plan.PublishedVersion) { "; published: $($plan.PublishedVersion)" } else { '' }
                "$($plan.Name) ($($plan.Id))$published; keep: $($plan.Keep -join ', '); delete: $($plan.Remove -join ', ')"
            }
            else {
                "$($plan.Name) ($($plan.Id)); skipped: $($plan.Message)"
            }
        }
    }.GetNewClosure()
    $retention.Add_TextChanged({ & $updatePreview }.GetNewClosure())
    & $updatePreview

    $window.Tag = @()
    $confirm.Add_Click({
        $selected = @($rows | Where-Object {
                $_.CheckBox.IsChecked -eq $true -and $_.CheckBox.IsEnabled
            } | ForEach-Object Plan)
        if ($selected.Count -eq 0) {
            $notice = & $newConfirmationDialog -Owner $window -Title 'No Shell Apps selected' `
                -Message 'Select at least one Shell App with versions to remove.' -DefaultYes $true -Buttons OK
            $null = $notice.ShowDialog()
            return
        }
        $details = @($selected | ForEach-Object { "$($_.Name): $($_.Remove -join ', ')" }) -join "`n"
        $approved = & $confirmAction -Window $window -Title 'Confirm Nerdio version pruning' `
            -Message "The following exact versions will be deleted:`n`n$details`n`nContinue?" -DefaultYes $false
        if ($approved) {
            $window.Tag = $selected
            $window.DialogResult = $true
        }
    }.GetNewClosure())

    $accepted = $window.ShowDialog()
    if ($accepted) { return [object[]]$window.Tag }
    return @()
}
