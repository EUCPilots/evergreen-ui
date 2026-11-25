Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchInstallArchitecture {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Window,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [psobject]$Review,

        [Parameter()]
        [switch]$Changed
    )

    $compatibility = $Review.Compatibility
    $requirement = if ([string]::IsNullOrWhiteSpace($compatibility.RequirementArchitecture)) {
        'Missing'
    }
    else { [string]$compatibility.RequirementArchitecture }
    $artifact = if ([string]::IsNullOrWhiteSpace($compatibility.ArtifactArchitecture)) {
        'Unknown'
    }
    else { [string]$compatibility.ArtifactArchitecture }
    $warnings = @(
        if ($Changed) { 'The reviewed Definition or Artifact metadata changed. Review the new inputs.' }
        $compatibility.Warnings
    )
    $message = "Application: $Name`nWindows architecture: $($compatibility.OperatingSystemArchitecture)" +
        "`nDefinition requirement: $requirement`nArtifact architecture: $artifact" +
        "`nVersion: $($Review.Latest.Version)`nArtifact URI: $($Review.Latest.URI)" +
        "`n`n$($warnings -join "`n")`n`nInstall this application?"
    $answer = [System.Windows.MessageBox]::Show(
        $Window,
        $message,
        'Confirm installation architecture',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No
    )
    return $answer -eq [System.Windows.MessageBoxResult]::Yes
}
