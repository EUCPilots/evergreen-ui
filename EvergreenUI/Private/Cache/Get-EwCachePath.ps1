Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwCachePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$CachePath
    )

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        }
        $CachePath = Join-Path -Path $localAppData -ChildPath 'EvergreenWorkbench\Cache'
    }
    $provider = $null
    $drive = $null
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CachePath, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') {
        throw 'CachePath must be a file system directory.'
    }
    $path = [System.IO.Path]::GetFullPath($path)
    $root = [System.IO.Path]::GetPathRoot($path)
    $canonical = $root
    foreach ($segment in $path.Substring($root.Length).Split(
        [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
        [System.StringSplitOptions]::RemoveEmptyEntries
    )) {
        $canonical = [System.IO.Path]::Combine($canonical, $segment)
        $directory = [System.IO.DirectoryInfo]::new($canonical)
        if ($null -ne $directory.LinkTarget) {
            $target = $directory.ResolveLinkTarget($true)
            if ($null -eq $target) {
                throw "Cache directory link could not be resolved: '$canonical'."
            }
            $canonical = $target.FullName
        }
    }
    $path = $canonical
    $root = [System.IO.Path]::GetPathRoot($path)
    if ($path.Length -gt $root.Length) {
        $path = $path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $path
}
