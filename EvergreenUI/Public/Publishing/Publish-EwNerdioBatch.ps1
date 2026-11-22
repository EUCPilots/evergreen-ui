Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-EwNerdioBatch {
    <#
    .SYNOPSIS
        Publishes confirmed Nerdio plan selections sequentially.
    .DESCRIPTION
        Rechecks files, sources and destinations before writes. Continues
        definite item failures only while access remains available. Stops on
        pending or unknown outcomes and retains partial identifiers.
    .PARAMETER Plan
        Read-only snapshot from Get-EwNerdioPublishPlan.
    .PARAMETER Selection
        Selected eligible items from that snapshot.
    .PARAMETER WorkingPath
        Root folder for downloaded installers.
    .PARAMETER CancellationToken
        Token checked between items, never used to interrupt a provider write.
    .EXAMPLE
        Publish-EwNerdioBatch -Plan $plan -Selection $selected -WorkingPath C:\Packages
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Does not delete, roll back or automatically retry provider writes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Plan,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Selection,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingPath,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $targets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Selection) {
        $target = if ($item.NerdioAppId) { "id:$($item.NerdioAppId)" } else { "name:$($item.Publisher)|$($item.AppName)" }
        if (-not $item.Eligible -or $item.Operation -notin @('Create', 'Add version') -or
            -not $paths.Add([string]$item.DefinitionPath) -or -not $targets.Add($target)) {
            throw 'Selections must be eligible unique definitions with distinct target apps.'
        }
    }
    if (-not $PSCmdlet.ShouldProcess("$($Selection.Count) Shell Apps at $($Plan.Destination.NmeHost)", 'Download and publish Nerdio batch')) { return }
    $stopReason = ''
    $number = 0
    foreach ($item in $Selection) {
        $number++
        $result = [PSCustomObject]@{
            Name = $item.AppName; DefinitionPath = $item.DefinitionPath; Version = $item.SourceVersion
            Operation = $item.Operation; Succeeded = $false; Status = 'Failed'
            AppId = ''; JobId = ''; BlobName = ''; Error = ''
        }
        if ($CancellationToken.IsCancellationRequested) {
            $result.Status = 'Cancelled'; $result.Error = 'Not started: cancellation requested.'
            $result
            continue
        }
        if ($stopReason) {
            $result.Status = 'Not started'; $result.Error = $stopReason
            $result
            continue
        }
        Write-Progress -Activity 'Publishing Nerdio Shell Apps' -Status "$number of $($Selection.Count): $($item.AppName)" `
            -PercentComplete ([int](100 * ($number - 1) / $Selection.Count))
        $snapshot = [PSCustomObject]@{ DefinitionRoot = $Plan.DefinitionRoot; Destination = $Plan.Destination; Item = $item }
        try {
            try { Assert-EwNerdioDestination -Destination $Plan.Destination }
            catch { $stopReason = 'The confirmed Nerdio or Azure connection is unavailable.'; throw }
            try { Assert-EwNerdioPublishSnapshot -Snapshot $snapshot }
            catch { $result.Status = 'Skipped'; throw }
            $folder = Join-Path -Path $WorkingPath -ChildPath "Nerdio\$([guid]::NewGuid())"
            $null = New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop
            Write-Verbose -Message "EvergreenUI: Downloading confirmed Nerdio artifact for '$($item.AppName)'"
            $saved = @(Invoke-EwArtifactSave -Artifact $item.Artifact -Path $folder)
            $file = [string]($saved | ForEach-Object {
                Get-EwFirstPropertyValue -InputObject $_ -Name 'FullName', 'Path'
            } | Select-Object -First 1)
            if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'The confirmed artifact download did not produce a file.' }
            $parameters = @{
                DefinitionPath = $item.DefinitionPath; PackagePath = $file; Version = $item.SourceVersion
                Snapshot = $snapshot; Confirm = $false
            }
            if ($item.Operation -eq 'Add version') { $parameters.ShellAppId = $item.NerdioAppId }
            $published = Publish-EwNerdioApp @parameters
            foreach ($name in 'Succeeded', 'Status', 'AppId', 'JobId', 'BlobName', 'Error') { $result.$name = $published.$name }
            if ($result.Status -in @('Pending', 'Unknown')) {
                $stopReason = 'A provider outcome needs review. Remaining items were not started.'
            }
            elseif (-not $result.Succeeded) {
                throw $result.Error
            }
        }
        catch {
            $result.Error = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
            Write-Verbose -Message "EvergreenUI: Nerdio '$($item.AppName)' $($result.Status): $($result.Error)"
            if (-not $stopReason) {
                try {
                    Assert-EwNerdioDestination -Destination $Plan.Destination
                    $null = Get-EwNerdioShellApp
                    $null = Get-EwAzureStorageContainer -ResourceGroupName $Plan.Destination.ResourceGroupName `
                        -StorageAccountName $Plan.Destination.StorageAccountName
                }
                catch {
                    $message = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
                    Write-Verbose -Message "EvergreenUI: Could not verify Nerdio/Azure access after an item failure: $message"
                    $stopReason = 'Provider access could not be verified. Remaining items were not started.'
                }
            }
        }
        $result
    }
    Write-Progress -Activity 'Publishing Nerdio Shell Apps' -Completed
}
