Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwDefinition {
    <#
    .SYNOPSIS
        Reads and validates Evergreen Workbench App.json definitions.
    .DESCRIPTION
        Searches a file or directory for App.json definition files and returns
        each definition with display metadata and validation status.
    .PARAMETER Path
        App.json file or directory containing package definitions.
    .PARAMETER Recurse
        Searches subdirectories when Path is a directory. Enabled by default.
    .EXAMPLE
        Get-EwDefinition -Path .\Definitions
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Definitions are validated using the v1 PSPackageFactory GUID requirement.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Definition path was not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        $search = @{
            LiteralPath = $item.FullName
            File = $true
            Filter = 'App.json'
            Recurse = $true
            ErrorAction = 'Stop'
        }
        $files = @(Get-ChildItem @search)
    }
    elseif ($item.Name -ieq 'App.json') {
        $files = @($item)
    }
    else {
        throw "Definition file must be named App.json: $Path"
    }

    foreach ($file in $files) {
        $definition = $null
        $name = [string]$file.Directory.Name
        $publisher = ''
        $version = ''
        $guidText = ''
        $status = 'Invalid JSON'
        $errorMessage = ''
        try {
            $definition = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $definition.Information) {
                if (-not [string]::IsNullOrWhiteSpace([string]$definition.Information.DisplayName)) {
                    $name = [string]$definition.Information.DisplayName
                }
                $publisher = [string]$definition.Information.Publisher
                $guidText = [string]$definition.Information.PSPackageFactoryGuid
            }
            if ($null -ne $definition.PackageInformation) {
                $version = [string]$definition.PackageInformation.Version
            }

            $parsedGuid = [guid]::Empty
            if ([string]::IsNullOrWhiteSpace($guidText)) {
                $status = 'Missing PSPackageFactoryGuid'
            }
            elseif (-not [guid]::TryParse($guidText, [ref]$parsedGuid)) {
                $status = 'Invalid PSPackageFactoryGuid'
            }
            else {
                $status = 'Valid'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Verbose -Message "EvergreenUI: Failed to read definition '$($file.FullName)': $errorMessage"
        }

        [PSCustomObject]@{
            DefinitionPath       = $file.FullName
            Name                 = $name
            Publisher            = $publisher
            Version              = $version
            Status               = $status
            DefinitionValid      = if ($status -eq 'Valid') { 'Yes' } else { $status }
            PSPackageFactoryGuid = $guidText
            DefinitionObject     = $definition
            Error                = $errorMessage
        }
    }
}
