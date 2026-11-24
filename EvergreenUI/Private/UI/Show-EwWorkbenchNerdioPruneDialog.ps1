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

    $window = [System.Windows.Window]::new()
    $window.Title = 'Preview Nerdio Shell App version pruning'
    $window.Owner = $Owner
    $window.MinWidth = 560
    $window.MaxWidth = 920
    $window.MaxHeight = 640
    if ($Owner.ActualWidth -gt 0) {
        $window.MaxWidth = [Math]::Max($window.MinWidth, [Math]::Min(920, $Owner.ActualWidth - 64))
    }
    if ($Owner.ActualHeight -gt 0) {
        $window.MaxHeight = [Math]::Max(240, [Math]::Min(640, $Owner.ActualHeight - 64))
    }
    $window.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'CenterOwner'

    $root = [System.Windows.Controls.DockPanel]::new()
    $root.Margin = [System.Windows.Thickness]::new(16)
    $window.Content = $root
    $footer = [System.Windows.Controls.StackPanel]::new()
    $footer.Orientation = 'Horizontal'
    $footer.HorizontalAlignment = 'Right'
    $footer.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($footer, [System.Windows.Controls.Dock]::Bottom)
    $root.Children.Add($footer) | Out-Null
    $cancel = [System.Windows.Controls.Button]::new()
    $cancel.Content = 'Cancel'
    $cancel.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
    $cancel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $cancel.IsCancel = $true
    $footer.Children.Add($cancel) | Out-Null
    $confirm = [System.Windows.Controls.Button]::new()
    $confirm.Content = 'Review selected deletions'
    $confirm.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
    $footer.Children.Add($confirm) | Out-Null

    # The list is the last DockPanel child so it fills the remaining height and scrolls at MaxHeight
    $content = [System.Windows.Controls.DockPanel]::new()
    $root.Children.Add($content) | Out-Null
    $retentionRow = [System.Windows.Controls.StackPanel]::new()
    $retentionRow.Orientation = 'Horizontal'
    $retentionRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    [System.Windows.Controls.DockPanel]::SetDock($retentionRow, [System.Windows.Controls.Dock]::Top)
    $content.Children.Add($retentionRow) | Out-Null
    $retentionLabel = [System.Windows.Controls.TextBlock]::new()
    $retentionLabel.Text = if (@($Plans | Where-Object { $_.PublishedVersion }).Count -gt 0) {
        'Keep newest versions (including the newly published version):'
    } else { 'Keep newest versions:' }
    $retentionLabel.VerticalAlignment = 'Center'
    $retentionRow.Children.Add($retentionLabel) | Out-Null
    $retention = [System.Windows.Controls.TextBox]::new()
    $retention.Text = '1'
    $retention.Width = 64
    $retention.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $retentionRow.Children.Add($retention) | Out-Null
    $help = [System.Windows.Controls.TextBlock]::new()
    $help.Text = 'Select apps explicitly. The preview lists every exact version to retain or delete.'
    $help.TextWrapping = 'Wrap'
    $help.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    [System.Windows.Controls.DockPanel]::SetDock($help, [System.Windows.Controls.Dock]::Top)
    $content.Children.Add($help) | Out-Null
    $scroll = [System.Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $list = [System.Windows.Controls.StackPanel]::new()
    $scroll.Content = $list
    $content.Children.Add($scroll) | Out-Null

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($plan in $Plans) {
        $plan | Add-Member -NotePropertyName Selected -NotePropertyValue $false -Force
        $check = [System.Windows.Controls.CheckBox]::new()
        $check.Tag = $plan
        $check.IsEnabled = [bool]$plan.Eligible -and @($plan.Remove).Count -gt 0
        $check.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.TextWrapping = 'Wrap'
        $check.Content = $label
        $list.Children.Add($check) | Out-Null
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
            [System.Windows.MessageBox]::Show($window, 'Select at least one Shell App with versions to remove.',
                'No Shell Apps selected', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            return
        }
        $details = @($selected | ForEach-Object { "$($_.Name): $($_.Remove -join ', ')" }) -join "`n"
        $answer = [System.Windows.MessageBox]::Show($window,
            "The following exact versions will be deleted:`n`n$details`n`nContinue?",
            'Confirm Nerdio version pruning', [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
            $window.Tag = $selected
            $window.DialogResult = $true
        }
    }.GetNewClosure())

    $accepted = $window.ShowDialog()
    if ($accepted) { return [object[]]$window.Tag }
    return @()
}
