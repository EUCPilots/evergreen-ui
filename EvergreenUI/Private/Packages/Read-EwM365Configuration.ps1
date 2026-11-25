Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-EwM365Configuration {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $displayNames = @{
        O365ProPlusRetail = 'Microsoft 365 Apps for enterprise'
        O365BusinessRetail = 'Microsoft 365 Apps for business'
        VisioProRetail = 'Visio'
        ProjectProRetail = 'Project'
        AccessRuntimeRetail = 'Access Runtime'
    }
    $addNode = $xml.SelectSingleNode('/Configuration/Add')
    if ($null -eq $addNode) {
        throw "The Office Deployment Tool configuration '$Path' has no Configuration.Add element."
    }
    $products = @($addNode.SelectNodes('Product'))
    $productIds = @($products | ForEach-Object { $_.GetAttribute('ID') })
    $displayProducts = @($productIds | ForEach-Object {
        if ($displayNames.ContainsKey($_)) { $displayNames[$_] } else { $_ }
    })
    $architecture = if ($addNode.GetAttribute('OfficeClientEdition') -eq '32') { 'x86' } else { 'x64' }
    $productText = $displayProducts -join ', '
    $displayName = if ([string]::IsNullOrWhiteSpace($productText)) {
        [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }
    else {
        "$productText`: $architecture"
    }
    $excluded = foreach ($product in $products) {
        foreach ($exclude in @($product.SelectNodes('ExcludeApp'))) {
            if (-not [string]::IsNullOrWhiteSpace($exclude.GetAttribute('ID'))) {
                $exclude.GetAttribute('ID')
            }
        }
    }
    $sharedLicensing = $xml.SelectSingleNode("/Configuration/Property[@Name='SharedComputerLicensing']")
    $isVdi = $false
    if ($null -ne $sharedLicensing) {
        $isVdi = $sharedLicensing.GetAttribute('Value') -eq '1'
    }
    $descriptionNode = $xml.SelectSingleNode('/Configuration/Info/Description')

    [PSCustomObject]@{
        ConfigId = $xml.Configuration.GetAttribute('ID')
        Channel = $addNode.GetAttribute('Channel')
        DisplayName = $displayName
        Architecture = $architecture
        Products = $productIds -join ', '
        ExcludedProducts = @($excluded) -join ', '
        IsVdi = $isVdi
        Description = if ($null -ne $descriptionNode) { $descriptionNode.InnerText } else { '' }
    }
}
