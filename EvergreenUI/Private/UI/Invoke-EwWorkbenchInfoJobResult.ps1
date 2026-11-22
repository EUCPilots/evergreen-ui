Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchInfoJobResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Download', 'Library', 'About')][string]$Kind,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Request,
        [AllowEmptyCollection()][object[]]$Output = @(),
        [AllowEmptyString()][string]$ErrorMessage = ''
    )

    if ($Kind -eq 'About') {
        $State.RefreshAboutDependenciesButton.IsEnabled = $true
        if ([string]::IsNullOrWhiteSpace($ErrorMessage) -and $Output.Count -eq 0) {
            $ErrorMessage = 'No dependency information was returned.'
        }
        if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
            $hasResults = $null -ne $State.AboutDependenciesListView.ItemsSource -and
                @($State.AboutDependenciesListView.ItemsSource).Count -gt 0
            $suffix = if ($hasResults) { ' Previous results are stale.' } else { '' }
            $message = "Dependency refresh failed: $ErrorMessage.$suffix"
            $State.AboutDependencyStatusLabel.Text = $message
            Write-EwWorkbenchLog -State $State -Message $message -Level Error -PreserveStatus
            return
        }

        $rows = @(
            foreach ($dependency in $Output) {
                $loaded = @(
                    $Request.LoadedModules |
                        Where-Object { $_.Name -eq $dependency.Name -and -not [string]::IsNullOrWhiteSpace($_.Version) } |
                        Select-Object -ExpandProperty Version -Unique |
                        Sort-Object
                )
                [PSCustomObject]@{
                    Name = [string]$dependency.Name
                    Type = if ($dependency.Required) { 'Required' } else { 'Optional' }
                    InstalledVersion = if ($dependency.InstalledVersion) { [string]$dependency.InstalledVersion } else { 'Not installed' }
                    LoadedVersions = if ($loaded.Count -gt 0) { $loaded -join ', ' } else { 'Not loaded' }
                    MinimumVersion = if ($dependency.MinimumVersion) { [string]$dependency.MinimumVersion } else { '-' }
                    Status = [string]$dependency.Status
                    Purpose = [string]$dependency.Purpose
                }
            }
        )
        $State.AboutDependenciesListView.ItemsSource = [object[]]$rows
        $State.AboutDependencyStatusLabel.Text = "Local dependency status refreshed ($($rows.Count) modules)."
        Write-Verbose -Message "EvergreenUI: Refreshed status for $($rows.Count) dependencies"
        return
    }

    $button = $State["Open${Kind}FolderButton"]
    $status = $State["${Kind}FolderStatusLabel"]
    $button.IsEnabled = $false
    if ([string]::IsNullOrWhiteSpace($ErrorMessage) -and $Output.Count -ne 1) {
        $ErrorMessage = 'The folder check did not return a result.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $status.Text = "Could not check the folder: $ErrorMessage"
        Write-EwWorkbenchLog -State $State -Message $status.Text -Level Error -PreserveStatus
        return
    }

    $result = $Output[0]
    if (-not $result.Available) {
        $status.Text = [string]$result.Error
        if ($Request.OpenAfterCheck) {
            Write-EwWorkbenchLog -State $State -Message "Could not open the folder: $($result.Error)" `
                -Level Warning -PreserveStatus
        }
        return
    }
    $button.IsEnabled = $true
    $status.Text = 'Folder is available.'
    if ($Request.OpenAfterCheck) {
        try {
            Write-Verbose -Message "EvergreenUI: Opening folder '$($result.ResolvedPath)'"
            $path = [string]$result.ResolvedPath
            # Preserve trailing backslashes when Windows parses the closing quote.
            $trailingBackslashes = $path.Length - $path.TrimEnd([char]'\').Length
            $argument = '"{0}{1}"' -f $path, ('\' * $trailingBackslashes)
            Start-Process -FilePath 'explorer.exe' -ArgumentList $argument -ErrorAction Stop
            $status.Text = 'Folder opened.'
            Write-Verbose -Message 'EvergreenUI: Opened folder'
        }
        catch {
            $button.IsEnabled = $false
            $status.Text = "Could not open the folder: $($_.Exception.Message)"
            Write-EwWorkbenchLog -State $State -Message $status.Text -Level Error -PreserveStatus
        }
    }
}
