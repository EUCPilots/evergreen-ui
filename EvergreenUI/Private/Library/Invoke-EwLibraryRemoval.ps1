Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwLibraryRemoval {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Index,
        [Parameter(Mandatory)][bool]$EntireApplication,
        [Parameter(Mandatory)][psobject]$Library,
        [Parameter(Mandatory)][psobject]$Manifest
    )

    $removedFiles = [Collections.Generic.List[string]]::new()
    $preservedFiles = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[string]]::new()
    $rowFiles = [Collections.Generic.Dictionary[int, object]]::new()
    $locks = [Collections.Generic.List[IO.FileStream]]::new()
    $manifestUpdated = $false
    $applicationRemoved = $false
    $failedFile = ''
    $getItemResults = {
        foreach ($rowIndex in $Index) {
            $paths = if ($rowFiles.ContainsKey($rowIndex)) { @($rowFiles[$rowIndex]) } else { @() }
            $status = if ($manifestUpdated) { 'Removed' }
                elseif ($failedFile -and $failedFile -in $paths) { 'Failed; entry retained' }
                elseif (@($paths | Where-Object { $_ -in $removedFiles }).Count -gt 0) { 'Files removed; entry retained' }
                else { 'Unattempted; entry retained' }
            $entry = @($Manifest.Data)[$rowIndex]
            [PSCustomObject]@{
                Index = $rowIndex
                Version = if ($null -ne $entry -and $null -ne $entry.PSObject.Properties['Version']) { [string]$entry.Version } else { '' }
                Status = $status
            }
        }
    }
    $fail = {
        param([string]$Message)
        Write-Warning -Message "EvergreenUI: Library removal stopped: $Message"
        [PSCustomObject]@{
            Succeeded = $false; Name = $Name; Path = $Path; Error = $Message
            ManifestUpdated = $manifestUpdated; ApplicationRemoved = $applicationRemoved
            RemovedCount = if ($manifestUpdated) { $Index.Count } else { 0 }
            RemovedFiles = $removedFiles.ToArray(); PreservedFiles = $preservedFiles.ToArray()
            FailedFile = $failedFile
            UnattemptedFiles = @($files | Where-Object { $_ -notin $removedFiles -and $_ -ne $failedFile })
            Items = @(& $getItemResults)
        }
    }

    try {
        Write-Verbose -Message "EvergreenUI: Planning library removal for $Name at $Path (entire application: $EntireApplication)"
        $appPath = Get-EwLibrarySafePath -Root $Path -Path $Name
        $entries = @($Manifest.Data)
        $retained = @(for ($i = 0; $i -lt $entries.Count; $i++) { if ($i -notin $Index) { $entries[$i] } })
        $references = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $snapshots = [Collections.Generic.List[object]]::new()
        $snapshots.Add($Library)
        $snapshots.Add($Manifest)
        $retainedSources = [Collections.Generic.List[object]]::new()
        $retainedSources.Add([PSCustomObject]@{ Root = $appPath; Entries = $retained })
        foreach ($app in @($Library.Data.Applications)) {
            if ($app.Name -ceq $Name) { continue }
            $otherRoot = Get-EwLibrarySafePath -Root $Path -Path ([string]$app.Name)
            $other = Get-EwLibraryFileSnapshot -Root $Path -Path (Join-Path -Path $otherRoot -ChildPath "$($app.Name).json")
            $snapshots.Add($other)
            $retainedSources.Add([PSCustomObject]@{ Root = $otherRoot; Entries = @($other.Data) })
        }
        foreach ($source in $retainedSources) {
            foreach ($entry in $source.Entries) {
                if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['Path']) { continue }
                foreach ($recorded in @($entry.Path)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$recorded)) {
                        $null = $references.Add([IO.Path]::GetFullPath([string]$recorded, $source.Root))
                    }
                }
                if ($references.Contains($Manifest.Path) -or ($EntireApplication -and $references.Contains($Library.Path))) {
                    throw 'A manifest is also recorded as a retained installer. Removal cannot safely change that shared file.'
                }
            }
        }
        $uniqueFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($rowIndex in $Index) {
            $entry = $entries[$rowIndex]
            $rowFiles[$rowIndex] = [Collections.Generic.List[string]]::new()
            if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['Path']) { continue }
            foreach ($recorded in @($entry.Path)) {
                if ([string]::IsNullOrWhiteSpace([string]$recorded)) { continue }
                $filePath = Get-EwLibrarySafePath -Root $appPath -Path ([string]$recorded)
                if ($filePath -eq $Manifest.Path -or $filePath -eq $appPath) {
                    throw "Installer path targets application metadata or its folder: $filePath"
                }
                if ($references.Contains($filePath)) {
                    $preservedFiles.Add($filePath)
                    Write-Verbose -Message "EvergreenUI: Preserving installer referenced by retained inventory: $filePath"
                }
                else {
                    $rowFiles[$rowIndex].Add($filePath)
                    if (-not $uniqueFiles.Add($filePath)) { continue }
                    if (Test-Path -LiteralPath $filePath) {
                        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Recorded installer is not a file: $filePath" }
                        $files.Add($filePath)
                    }
                    else {
                        Write-Verbose -Message "EvergreenUI: Recorded installer is already absent: $filePath"
                    }
                }
            }
        }
        # Deny manifest edits during file deletion, including changes to shared-file references.
        foreach ($snapshot in $snapshots) {
            $null = Get-EwLibrarySafePath -Root $Path -Path $snapshot.Path
            $locks.Add([IO.File]::Open($snapshot.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read))
            if ((Get-EwLibraryFileSnapshot -Root $Path -Path $snapshot.Path).Hash -cne $snapshot.Hash) {
                throw 'Library manifests changed. Reload the library and confirm a new selection.'
            }
        }
        foreach ($filePath in $files) {
            $failedFile = $filePath
            $null = Get-EwLibrarySafePath -Root $appPath -Path $filePath
            Write-Verbose -Message "EvergreenUI: Removing recorded library installer $filePath"
            Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop
            $removedFiles.Add($filePath)
            $failedFile = ''
        }
        $locks[1].Dispose()
        if ((Get-EwLibraryFileSnapshot -Root $Path -Path $Manifest.Path).Hash -cne $Manifest.Hash) {
            throw 'App manifest changed before the inventory write. Review the partial file removal and reload the library.'
        }
        Write-EwJsonFile -Path $Manifest.Path -InputObject $retained
        $manifestUpdated = $true
        Write-Verbose -Message "EvergreenUI: Removed $($Index.Count) artifact entries from $($Manifest.Path)"
        if ($EntireApplication) {
            $Library.Data.Applications = @($Library.Data.Applications | Where-Object { $_.Name -cne $Name })
            $locks[0].Dispose()
            if ((Get-EwLibraryFileSnapshot -Root $Path -Path $Library.Path).Hash -cne $Library.Hash) {
                throw 'Library manifest changed before unregistering the application. Reload the library.'
            }
            Write-EwJsonFile -Path $Library.Path -InputObject $Library.Data
            $applicationRemoved = $true
            Remove-Item -LiteralPath $Manifest.Path -Force -ErrorAction Stop
        }
        # Only prune empty directories belonging to the recorded files, never recurse.
        $folders = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($filePath in $removedFiles) {
            $folder = [IO.Path]::GetDirectoryName($filePath)
            while ($folder -and -not [string]::Equals($folder, $appPath, [StringComparison]::OrdinalIgnoreCase)) {
                $null = $folders.Add($folder)
                $folder = [IO.Path]::GetDirectoryName($folder)
            }
        }
        if ($EntireApplication) { $null = $folders.Add($appPath) }
        foreach ($folder in $folders | Sort-Object -Property Length -Descending) {
            $null = Get-EwLibrarySafePath -Root $appPath -Path $folder
            if (@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop).Count -eq 0) {
                Remove-Item -LiteralPath $folder -ErrorAction Stop
            }
        }
        Write-Verbose -Message "EvergreenUI: Library removal completed for $Name; removed $($removedFiles.Count) files"
        [PSCustomObject]@{
            Succeeded = $true; Name = $Name; Path = $Path; Error = ''
            ManifestUpdated = $manifestUpdated; ApplicationRemoved = $applicationRemoved
            RemovedCount = $Index.Count; RemovedFiles = $removedFiles.ToArray()
            PreservedFiles = $preservedFiles.ToArray(); FailedFile = ''; UnattemptedFiles = @()
            Items = @(& $getItemResults)
        }
    }
    catch {
        & $fail -Message $_.Exception.Message
    }
    finally {
        foreach ($stream in $locks) { $stream.Dispose() }
    }
}
