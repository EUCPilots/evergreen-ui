Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EwArtifactFilter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Artifact,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Filter
    )

    foreach ($key in $Filter.Keys) {
        $property = $Artifact.PSObject.Properties[$key]
        if ($key -eq '_DerivedType') {
            $property = $Artifact.PSObject.Properties['URI']
            if ($null -eq $property) {
                return $false
            }
            $actualValues = @([System.IO.Path]::GetExtension([string]$property.Value).TrimStart('.').ToLowerInvariant())
        }
        elseif ($null -eq $property) {
            return $false
        }
        else {
            $actualValues = @($property.Value | ForEach-Object { [string]$_ })
        }

        $expectedValues = @($Filter[$key] | ForEach-Object { [string]$_ })
        if (-not (@($actualValues | Where-Object { $_ -in $expectedValues }).Count -gt 0)) {
            return $false
        }
    }
    return $true
}
