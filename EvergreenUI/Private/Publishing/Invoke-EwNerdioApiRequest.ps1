Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwNerdioApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter()]
        [psobject]$Body
    )

    $parameters = @{
        Uri = $Uri
        Method = $Method
        Headers = @{ Accept = 'application/json'; Authorization = "Bearer $AccessToken" }
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $parameters.Body = ConvertTo-Json -InputObject $Body -Depth 30
        $parameters.ContentType = 'application/json'
    }
    Invoke-RestMethod @parameters
}
