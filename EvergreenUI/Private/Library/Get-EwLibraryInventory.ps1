Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwLibraryInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $library = Get-EwLibraryFileSnapshot -Root $Path -Path 'EvergreenLibrary.json'
    if ($null -eq $library.Data.PSObject.Properties['Applications']) {
        throw "Library manifest has no Applications property: $($library.Path)"
    }
    $inventory = @(
        foreach ($application in @($library.Data.Applications)) {
            $name = [string]$application.Name
            if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.', '..') -or
                $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $name.TrimEnd(' ', '.') -ne $name) {
                throw "Invalid application folder name in library manifest: '$name'"
            }
            $manifestPath = Get-EwLibrarySafePath -Root $Path -Path "$name\$name.json"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                Write-Warning -Message "EvergreenUI: Application manifest was not found: $manifestPath. Update the library to restore it."
                continue
            }
            $manifest = Get-EwLibraryFileSnapshot -Root $Path -Path $manifestPath
            [PSCustomObject]@{
                ApplicationName = $name
                ApplicationPath = [IO.Path]::GetDirectoryName($manifest.Path)
                Versions = @($manifest.Data)
                ManifestHash = $manifest.Hash
                LibraryHash = $library.Hash
            }
        }
    )
    if ((Get-EwLibraryFileSnapshot -Root $Path -Path 'EvergreenLibrary.json').Hash -ne $library.Hash) {
        throw 'Library changed while loading inventory. Reload the library.'
    }
    Write-Verbose -Message "EvergreenUI: Read $($inventory.Count) library applications from $Path"
    [PSCustomObject]@{ Library = $library.Data; Inventory = $inventory }
}
