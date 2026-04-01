#Requires -Version 5.1
<#!
.SYNOPSIS
    Loads App.json package definitions for the local Install workflow.

.DESCRIPTION
    Recursively searches the provided root path for App.json files and returns
    normalized row objects with validation metadata used by the Install panel.

.PARAMETER DefinitionsRoot
    Root directory containing one or more application folders with App.json.

.OUTPUTS
    PSCustomObject with:
        Succeeded : bool
        Rows      : object[]
        Error     : string
!#>
function Get-InstallPackageDefinitions {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionsRoot
    )

    $result = [PSCustomObject]@{
        Succeeded = $false
        Rows      = @()
        Error     = ''
    }

    if ([string]::IsNullOrWhiteSpace($DefinitionsRoot)) {
        $result.Error = 'Definitions root path is empty.'
        return $result
    }

    if (-not (Test-Path -LiteralPath $DefinitionsRoot -PathType Container)) {
        $result.Error = "Definitions root path was not found: $DefinitionsRoot"
        return $result
    }

    $definitionFiles = @()
    try {
        $definitionFiles = @(Get-ChildItem -LiteralPath $DefinitionsRoot -Recurse -File -ErrorAction Stop |
                Where-Object { $_.Name -ieq 'App.json' })
        Write-Verbose -Message "EvergreenUI: Found $($definitionFiles.Count) App.json definition file(s) under '$DefinitionsRoot'."
    }
    catch {
        $result.Error = "Failed to enumerate App.json files: $($_.Exception.Message)"
        return $result
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($definitionFile in $definitionFiles) {
        $definitionObject = $null
        $name = [string](Split-Path -Path $definitionFile.DirectoryName -Leaf)
        $publisher = '-'
        $version = '-'
        $guidText = ''
        $status = 'Invalid JSON'

        try {
            $definitionObject = Get-Content -LiteralPath $definitionFile.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $definitionObject.Information) {
                if (-not [string]::IsNullOrWhiteSpace([string]$definitionObject.Information.DisplayName)) {
                    $name = ([string]$definitionObject.Information.DisplayName).Trim()
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$definitionObject.Information.Publisher)) {
                    $publisher = ([string]$definitionObject.Information.Publisher).Trim()
                }
                $guidText = ([string]$definitionObject.Information.PSPackageFactoryGuid).Trim()
            }

            if ($null -ne $definitionObject.PackageInformation -and
                -not [string]::IsNullOrWhiteSpace([string]$definitionObject.PackageInformation.Version)) {
                $version = ([string]$definitionObject.PackageInformation.Version).Trim()
            }

            if ([string]::IsNullOrWhiteSpace($guidText)) {
                $status = 'Missing PSPackageFactoryGuid'
            }
            else {
                try {
                    [void][guid]$guidText
                    $status = 'Yes'
                }
                catch {
                    $status = 'Invalid PSPackageFactoryGuid'
                }
            }
        }
        catch {
            $status = 'Invalid JSON'
            Write-Verbose -Message "EvergreenUI: Failed to parse '$($definitionFile.FullName)': $($_.Exception.Message)"
        }

        $rows.Add([PSCustomObject]@{
                DefinitionId         = [string]$definitionFile.FullName
                DefinitionPath       = [string]$definitionFile.FullName
                Name                 = $name
                Publisher            = $publisher
                Version              = $version
                Status               = if ($status -eq 'Yes') { 'Valid' } else { $status }
                DefinitionValid      = $status
                PSPackageFactoryGuid = $guidText
                DefinitionObject     = $definitionObject
            })
    }

    $result.Succeeded = $true
    $result.Rows = @($rows | Sort-Object -Property Publisher, Name, DefinitionPath)
    return $result
}
