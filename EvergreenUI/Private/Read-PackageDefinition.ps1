#Requires -Version 5.1
<#!
.SYNOPSIS
    Loads and validates the baseline structure of an App.json package definition.

.PARAMETER Path
    Full path to the App.json file.

.OUTPUTS
    PSCustomObject with Succeeded, Definition, and Error properties.
!#>
function Read-PackageDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fail = {
        param([string]$Message)
        return [PSCustomObject]@{
            Succeeded  = $false
            Definition = $null
            Error      = $Message
        }
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (& $fail 'Package definition path is empty.')
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (& $fail "Package definition file was not found: $Path")
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $parsedDefinitions = @(ConvertFrom-Json -InputObject $json -ErrorAction Stop)
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Failed to parse package definition '$Path': $($_.Exception.Message)"
        return (& $fail "Failed to parse package definition '$Path': $($_.Exception.Message)")
    }

    if ($parsedDefinitions.Count -ne 1 -or $parsedDefinitions[0] -is [System.Array] -or
        $parsedDefinitions[0] -isnot [PSCustomObject]) {
        return (& $fail "Package definition '$Path' must contain a single JSON object.")
    }
    $definition = $parsedDefinitions[0]

    $requiredSections = @('Application', 'Information', 'PackageInformation')
    foreach ($section in $requiredSections) {
        $property = $definition.PSObject.Properties[$section]
        if ($null -eq $property -or $null -eq $property.Value -or $property.Value -isnot [PSCustomObject]) {
            return (& $fail "Package definition '$Path' is missing the required '$section' object.")
        }
    }

    return [PSCustomObject]@{
        Succeeded  = $true
        Definition = $definition
        Error      = ''
    }
}