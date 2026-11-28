Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365Configuration {
    <#
    .SYNOPSIS
        Lists Microsoft 365 Apps configuration files.
    .DESCRIPTION
        Reads Office Deployment Tool XML files in the top level of a folder,
        excluding Uninstall-Microsoft365Apps.xml, and returns their products,
        architecture, and configuration identifier. Display names combine
        products, Outlook exclusions, Desktop or VDI licensing, channel and
        architecture. Summary contains a readable translation of the products,
        included and excluded apps, languages, licensing, and install
        behaviour. Files that cannot be read are returned with an Invalid
        XML status and no Summary.
    .PARAMETER Path
        Folder containing the configuration files.
    .EXAMPLE
        Get-EwM365Configuration -Path C:\Packages\M365
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Status is Valid, No ID, Invalid ID, or Invalid XML. Pass FilePath to
        New-EwPackage -M365ConfigurationPath.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Microsoft 365 configuration folder '$Path' was not found."
    }
    $files = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.xml' -ErrorAction Stop |
            Where-Object { $_.Name -ine 'Uninstall-Microsoft365Apps.xml' } |
            Sort-Object -Property Name)
    Write-Verbose -Message "EvergreenUI: Found $($files.Count) Microsoft 365 configuration files in '$Path'"

    foreach ($file in $files) {
        try {
            $configuration = Read-EwM365Configuration -Path $file.FullName
            $guid = [guid]::Empty
            $status = if ([string]::IsNullOrWhiteSpace($configuration.ConfigId)) {
                'No ID'
            }
            elseif (-not [guid]::TryParse($configuration.ConfigId, [ref]$guid) -or $guid -eq [guid]::Empty) {
                'Invalid ID'
            }
            else {
                'Valid'
            }
            [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                DisplayName = $configuration.DisplayName
                Channel = $configuration.Channel
                Architecture = $configuration.Architecture
                Products = $configuration.Products
                ExcludedProducts = $configuration.ExcludedProducts
                IsVdi = $configuration.IsVdi
                Description = $configuration.Description
                ConfigId = $configuration.ConfigId
                Status = $status
                Summary = $configuration.Summary
            }
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Microsoft 365 configuration '$($file.Name)' is invalid: $($_.Exception.Message)"
            [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                DisplayName = $file.BaseName
                Channel = ''
                Architecture = ''
                Products = ''
                ExcludedProducts = ''
                IsVdi = $false
                Description = ''
                ConfigId = ''
                Status = 'Invalid XML'
                Summary = $null
            }
        }
    }
}
