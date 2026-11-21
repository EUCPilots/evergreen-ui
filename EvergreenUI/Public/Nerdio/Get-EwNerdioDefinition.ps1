Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioDefinition {
    <#
    .SYNOPSIS
        Reads Nerdio Manager Shell App definitions.
    .DESCRIPTION
        Searches a folder recursively for Definition.json files and returns
        each definition's publisher, name, source, and validation status.
    .PARAMETER Path
        Folder containing Shell App definition folders.
    .EXAMPLE
        Get-EwNerdioDefinition -Path C:\Packages\ShellApps
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        DefinitionPath is the folder containing Definition.json. DefinitionValid
        is Yes, No (missing JSON properties), or No (invalid JSON).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Nerdio definition folder '$Path' was not found."
    }
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Filter 'Definition.json' -ErrorAction Stop)
    Write-Verbose -Message "EvergreenUI: Found $($files.Count) Nerdio definitions under '$Path'"

    $rows = foreach ($file in $files) {
        $publisher = ''
        $appName = [string]$file.Directory.Name
        $valid = 'No (invalid JSON)'
        $sourceType = ''
        $sourceApp = ''
        $sourceFilter = ''
        $definition = $null
        try {
            $definition = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $publisherValue = Get-EwFirstPropertyValue -InputObject $definition -Name 'publisher', 'vendor', 'manufacturer'
            $nameValue = Get-EwFirstPropertyValue -InputObject $definition -Name 'name', 'displayName', 'appName', 'title'
            if ($null -ne $publisherValue) {
                $publisher = ([string]$publisherValue).Trim()
            }
            if ($null -ne $nameValue) {
                $appName = ([string]$nameValue).Trim()
            }
            $valid = if ($null -ne $publisherValue -and $null -ne $nameValue) { 'Yes' } else { 'No (missing JSON properties)' }
            $source = Get-EwFirstPropertyValue -InputObject $definition -Name 'source'
            if ($null -ne $source) {
                $sourceType = [string](Get-EwFirstPropertyValue -InputObject $source -Name 'type')
                $sourceApp = [string](Get-EwFirstPropertyValue -InputObject $source -Name 'app')
                $sourceFilter = [string](Get-EwFirstPropertyValue -InputObject $source -Name 'filter')
            }
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Nerdio definition '$($file.FullName)' is invalid: $($_.Exception.Message)"
        }
        [PSCustomObject]@{
            DefinitionPath = $file.DirectoryName
            Publisher = $publisher
            AppName = $appName
            DefinitionValid = $valid
            SourceType = $sourceType
            SourceApp = $sourceApp
            SourceFilter = $sourceFilter
            DefinitionObject = $definition
        }
    }
    @($rows) | Sort-Object -Property DefinitionPath, Publisher, AppName
}
