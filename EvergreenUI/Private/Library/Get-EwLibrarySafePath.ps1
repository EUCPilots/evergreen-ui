Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwLibrarySafePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if ($rootItem -isnot [IO.DirectoryInfo]) { throw "Library root is not a filesystem directory: $Root" }
    $rootPath = [IO.Path]::TrimEndingDirectorySeparator($rootItem.FullName)
    $fullPath = [IO.Path]::GetFullPath($Path, $rootPath)
    $relativePath = [IO.Path]::GetRelativePath($rootPath, $fullPath)
    if ($relativePath -eq '..' -or $relativePath.StartsWith('..\') -or
        [IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains(':')) {
        throw "Library path is outside '$rootPath': $Path"
    }
    # Check ancestors too: a library itself can be reached through a junction.
    $currentPath = $fullPath
    while (-not [string]::IsNullOrEmpty($currentPath)) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Library path traverses a reparse point: $currentPath"
            }
        }
        $currentPath = [IO.Path]::GetDirectoryName($currentPath)
    }
    return $fullPath
}
