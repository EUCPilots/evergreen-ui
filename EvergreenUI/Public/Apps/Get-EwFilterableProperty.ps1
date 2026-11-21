Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwFilterableProperty {
    <#
    .SYNOPSIS
        Describes artifact properties suitable for filtering.
    .DESCRIPTION
        Derives unique values and a suggested control type from artifact objects.
        Display-only metadata such as version, URI, dates, and checksums is
        excluded. If Type is absent but URI exists, a file-extension filter is
        included as _DerivedType.
    .PARAMETER Artifact
        One or more objects returned by Get-EwApp -Name.
    .EXAMPLE
        Get-EwApp -Name MicrosoftEdge | Get-EwFilterableProperty
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        ControlType is descriptive metadata; this cmdlet does not load WPF.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [object[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [psobject[]]$Artifact
    )

    begin {
        $artifacts = [System.Collections.Generic.List[psobject]]::new()
    }
    process {
        foreach ($item in $Artifact) {
            if ($null -ne $item) {
                $artifacts.Add($item)
            }
        }
    }
    end {
        if ($artifacts.Count -eq 0) {
            return
        }

        $displayOnly = @(
            'Version', 'URI', 'Date', 'Expiry', 'Build', 'Filename',
            'Sha', 'Sha1', 'Sha256', 'Sha512', 'Hash', 'Md5', 'InternalVersion',
            'Checksum', 'Size', 'JavaVersion'
        )
        $friendlyNames = @{
            Architecture = 'Architecture'
            Type = 'File type'
            Channel = 'Channel'
            Ring = 'Ring / Channel'
            Release = 'Release'
            Language = 'Language'
            Platform = 'Platform'
            Track = 'Track'
            Product = 'Product variant'
        }
        $properties = @($artifacts[0].PSObject.Properties.Name | Where-Object { $_ -notin $displayOnly -and $_ -notlike '*Date*' })
        $result = foreach ($propertyName in $properties) {
            $values = @(
                foreach ($item in $artifacts) {
                    $value = $item.PSObject.Properties[$propertyName].Value
                    if ($null -ne $value) {
                        [string]$value
                    }
                }
            )
            $values = @($values | Sort-Object -Unique)
            [PSCustomObject]@{
                Name = $propertyName
                DisplayName = if ($friendlyNames.ContainsKey($propertyName)) { $friendlyNames[$propertyName] } else { $propertyName }
                UniqueValues = [string[]]$values
                Count = $values.Count
                ControlType = if ($propertyName -eq 'Language') { 'ComboBox' } elseif ($values.Count -le 6) { 'CheckBoxStrip' } elseif ($values.Count -le 20) { 'MultiListBox' } else { 'TextBox' }
                IsSynthetic = $false
            }
        }

        $hasType = $artifacts[0].PSObject.Properties.Name -contains 'Type'
        $hasUri = $artifacts[0].PSObject.Properties.Name -contains 'URI'
        if (-not $hasType -and $hasUri) {
            $types = @(
                foreach ($item in $artifacts) {
                    $extension = [System.IO.Path]::GetExtension([string]$item.URI).TrimStart('.').ToLowerInvariant()
                    if ($extension) {
                        $extension
                    }
                }
            )
            $types = @($types | Sort-Object -Unique)
            if ($types.Count -gt 0) {
                $result = @($result) + [PSCustomObject]@{
                    Name = '_DerivedType'
                    DisplayName = 'File type (derived)'
                    UniqueValues = [string[]]$types
                    Count = $types.Count
                    ControlType = if ($types.Count -le 6) { 'CheckBoxStrip' } else { 'MultiListBox' }
                    IsSynthetic = $true
                }
            }
        }
        return @($result)
    }
}
