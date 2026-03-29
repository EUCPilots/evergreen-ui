#Requires -Version 5.1
<#
.SYNOPSIS
    Reads Microsoft 365 Apps Office Deployment Tool XML configuration files from a directory.

.DESCRIPTION
    Finds all *.xml files in the specified root directory (non-recursive), excluding
    Uninstall-Microsoft365Apps.xml, and parses each for configuration details including
    the PSPackageFactory GUID (Configuration/@ID), channel, products, and architecture.

.PARAMETER DefinitionsRoot
    Path to the directory containing the M365 Apps XML configuration files.

.OUTPUTS
    PSCustomObject[] - one row per XML file (valid or invalid).
#>
function Get-M365AppConfigurations {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionsRoot
    )

    # Product ID to display name mapping
    $productDisplayNames = @{
        'O365ProPlusRetail'    = 'Microsoft 365 Apps for enterprise'
        'O365BusinessRetail'   = 'Microsoft 365 Apps for business'
        'VisioProRetail'       = 'Visio'
        'ProjectProRetail'     = 'Project'
        'AccessRuntimeRetail'  = 'Access Runtime'
    }


    $xmlFiles = @(Get-ChildItem -LiteralPath $DefinitionsRoot -File -Filter '*.xml' -ErrorAction Stop |
        Where-Object { $_.Name -ine 'Uninstall-Microsoft365Apps.xml' })

    $rows = foreach ($file in $xmlFiles) {
        try {
            [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop

            $configId = [string]$xml.Configuration.ID
            $addNode  = $xml.Configuration.Add
            $channel  = [string]$addNode.Channel
            $arch     = [string]$addNode.OfficeClientEdition
            $archText = if ($arch -eq '32') { 'x86' } else { 'x64' }

            # Collect product IDs
            $productNodes = @($addNode.Product)
            $productIds   = ($productNodes | ForEach-Object { [string]$_.ID }) -join ', '

            # Determine primary product for display name
            $displayProducts = foreach ($p in $productNodes) {
                $id = [string]$p.ID
                if ($productDisplayNames.ContainsKey($id)) { $productDisplayNames[$id] } else { $id }
            }
            $displayProductsText = $displayProducts -join ', '

            # VDI / Desktop
            $sclProp = $xml.Configuration.Property | Where-Object { $_.Name -eq 'SharedComputerLicensing' } |
                Select-Object -First 1
            $isVdi   = [string]$sclProp.Value -eq '1'
            $envText = if ($isVdi) { 'VDI' } else { 'Desktop' }

            # Compose full display name: "Products: Environment, Architecture"
            # Channel is a placeholder in the XML (#Channel) and comes from the user's
            # dropdown selection at packaging time, so it is excluded from the display name.
            $displayName = if ($displayProductsText) {
                "$displayProductsText`: $envText, $archText"
            } else {
                $file.BaseName
            }

            # Validate GUID
            $guid   = [System.Guid]::Empty
            $status = if ([string]::IsNullOrWhiteSpace($configId)) {
                'No ID'
            } elseif (-not [System.Guid]::TryParse($configId, [ref]$guid)) {
                'Invalid ID'
            } else {
                'Valid'
            }

            $description = [string]$xml.Configuration.Info.Description

            [PSCustomObject]@{
                FileName         = $file.Name
                FilePath         = $file.FullName
                DisplayName      = $displayName
                Channel          = $channel
                Architecture     = $archText
                Products         = $productIds
                IsVdi            = $isVdi
                Description      = $description
                ConfigId         = $configId
                EvergreenVersion = ''
                Status           = $status
            }
        }
        catch {
            [PSCustomObject]@{
                FileName         = $file.Name
                FilePath         = $file.FullName
                DisplayName      = $file.BaseName
                Channel          = ''
                Architecture     = ''
                Products         = ''
                IsVdi            = $false
                Description      = ''
                ConfigId         = ''
                EvergreenVersion = ''
                Status           = 'Invalid XML'
            }
        }
    }

    return @($rows)
}
