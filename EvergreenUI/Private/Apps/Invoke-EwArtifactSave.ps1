Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwArtifactSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Artifact,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Force,
        [switch]$VerifyChecksum
    )

    $saveParameters = @{
        Path = $Path
        ErrorAction = 'Stop'
    }
    if ($Force) {
        $saveParameters.Force = $true
    }
    if ($VerifyChecksum) {
        $saveParameters.VerifyChecksum = $true
    }
    $Artifact | Save-EvergreenApp @saveParameters
}
