Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioShellAppVersion {
    <#
    .SYNOPSIS
        Lists the versions of a Nerdio Manager Shell App.
    .DESCRIPTION
        Returns the version records for a Shell App from the Nerdio Manager API.
    .PARAMETER Id
        Shell App ID.
    .EXAMPLE
        Get-EwNerdioShellAppVersion -Id 42
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    process {
        $context = Get-EwNerdioSessionContext
        $uri = "https://$($context.NmeHost)/api/v1/shell-app/$([uri]::EscapeDataString($Id))/version"
        Write-Verbose -Message "EvergreenUI: Listing versions for Nerdio Shell App '$Id'"
        $response = Invoke-EwNerdioApiRequest -Method GET -Uri $uri -AccessToken $context.AccessToken
        $items = Get-EwFirstPropertyValue -InputObject $response -Name 'items'
        foreach ($item in @($items)) { if ($null -ne $item) { $item } }
    }
}
