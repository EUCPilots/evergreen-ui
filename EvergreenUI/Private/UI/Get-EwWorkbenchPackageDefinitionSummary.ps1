Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwWorkbenchPackageDefinitionSummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowNull()]
        [object]$Definition
    )

    if ($null -eq $Definition) {
        return [PSCustomObject]@{ Label = ''; Value = 'Select a definition to view its details.'; IsFilter = $false }
    }

    $fields = @(
        @{ Label = 'Application'; Path = @('Name') }
        @{ Label = 'Publisher'; Path = @('Publisher') }
        @{ Label = 'Version'; Path = @('Version') }
        @{ Label = 'Architecture'; Path = @('DefinitionObject', 'Application', 'Architecture') }
        @{ Label = 'Description'; Path = @('DefinitionObject', 'Information', 'Description') }
        @{ Label = 'Evergreen filter'; Path = @('DefinitionObject', 'Application', 'Filter') }
        @{ Label = 'Setup type'; Path = @('DefinitionObject', 'PackageInformation', 'SetupType') }
        @{ Label = 'Setup file'; Path = @('DefinitionObject', 'PackageInformation', 'SetupFile') }
        @{ Label = 'Status'; Path = @('Status') }
        @{ Label = 'Definition path'; Path = @('DefinitionPath') }
        @{ Label = 'Error'; Path = @('Error') }
    )
    foreach ($field in $fields) {
        $value = $Definition
        foreach ($name in $field.Path) {
            if ($null -eq $value) {
                break
            }
            $property = $value.PSObject.Properties[$name]
            $value = if ($null -ne $property) { $property.Value } else { $null }
        }
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            [PSCustomObject]@{
                Label = $field.Label
                Value = [string]$value
                IsFilter = $field.Label -eq 'Evergreen filter'
            }
        }
    }
}
