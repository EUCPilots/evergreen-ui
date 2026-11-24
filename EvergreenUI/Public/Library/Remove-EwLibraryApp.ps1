Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-EwLibraryApp {
    <#
    .SYNOPSIS
        Removes an application or selected artifact rows from a local library.
    .DESCRIPTION
        Independently updates Evergreen library manifests and removes only recorded
        installer files inside the application folder. Files referenced by retained
        entries, unrecorded files, and the library root are preserved. Stops at the
        first failure and returns explicit partial results without retrying.
    .PARAMETER Path
        Initialized local library path. Defaults to the configured LibraryPath.
    .PARAMETER Name
        Application name from the library manifest.
    .PARAMETER Index
        Zero-based app manifest row indexes to remove. Omit to remove the application
        from the library, including its recorded artifacts and manifest.
    .PARAMETER ExpectedManifestHash
        App manifest SHA256 captured with Get-EwLibrary. Rejects stale selections.
    .PARAMETER ExpectedLibraryHash
        Library manifest SHA256 captured with Get-EwLibrary.
    .EXAMPLE
        Remove-EwLibraryApp -Path C:\Library -Name MicrosoftEdge -WhatIf
    .EXAMPLE
        $app = Get-EwLibrary -Path C:\Library | Where-Object Name -EQ MicrosoftEdge
        Remove-EwLibraryApp -Path C:\Library -Name $app.Name -Index 0, 2 -ExpectedManifestHash $app.ManifestHash -ExpectedLibraryHash $app.LibraryHash
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Supports WhatIf and Confirm. Removal does not call Evergreen.
        Indexes identify individual artifacts, not every artifact sharing a version.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [int[]]$Index,

        [Parameter()]
        [string]$ExpectedManifestHash,

        [Parameter()]
        [string]$ExpectedLibraryHash
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = [string](Get-EwSetting).LibraryPath }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Library path is not configured.' }
    if ($Name -in @('.', '..') -or $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Name.TrimEnd(' ', '.') -ne $Name) {
        throw "Invalid application folder name: '$Name'"
    }
    $Path = Get-EwLibrarySafePath -Root $Path -Path '.'
    $library = Get-EwLibraryFileSnapshot -Root $Path -Path 'EvergreenLibrary.json'
    if ($null -eq $library.Data.PSObject.Properties['Applications']) {
        throw 'Library manifest has no Applications property.'
    }
    $applications = @($library.Data.Applications | Where-Object { $_.Name -eq $Name })
    if ($applications.Count -ne 1) { throw "Expected exactly one application named '$Name' in the library." }
    $Name = [string]$applications[0].Name
    $manifest = Get-EwLibraryFileSnapshot -Root $Path -Path "$Name\$Name.json"
    if (($ExpectedManifestHash -and $ExpectedManifestHash -cne $manifest.Hash) -or
        ($ExpectedLibraryHash -and $ExpectedLibraryHash -cne $library.Hash)) {
        throw 'Library manifests changed. Reload the library and confirm a new selection.'
    }
    $entries = @($manifest.Data)
    $entireApplication = -not $PSBoundParameters.ContainsKey('Index')
    [int[]]$indexes = if ($entireApplication) {
        @(for ($i = 0; $i -lt $entries.Count; $i++) { $i })
    }
    else {
        @($Index | Sort-Object -Unique)
    }
    foreach ($rowIndex in $indexes) {
        if ($rowIndex -lt 0 -or $rowIndex -ge $entries.Count) { throw "Invalid library artifact index: $rowIndex" }
    }
    $action = if ($entireApplication) { 'Remove application and its recorded installers' } else { "Remove $($indexes.Count) selected artifact(s)" }
    if ($PSCmdlet.ShouldProcess("$Name in $Path", $action)) {
        Invoke-EwLibraryRemoval -Path $Path -Name $Name -Index $indexes -EntireApplication $entireApplication -Library $library -Manifest $manifest
    }
}
