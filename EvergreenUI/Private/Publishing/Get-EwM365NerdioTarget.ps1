Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365NerdioTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Destination,
        [Parameter(Mandatory)][ValidateSet('Create', 'Add version')][string]$Operation,
        [Parameter(Mandatory)][string]$Name,
        [string]$ShellAppId
    )

    Assert-EwNerdioDestination -Destination $Destination
    $containers = @(Get-EwAzureStorageContainer -ResourceGroupName $Destination.ResourceGroupName `
            -StorageAccountName $Destination.StorageAccountName)
    if (@($containers | Where-Object { $_ -ieq $Destination.ContainerName }).Count -ne 1) {
        throw 'The confirmed Azure storage container could not be verified.'
    }
    $apps = @(Get-EwNerdioShellApp)
    foreach ($app in $apps) {
        if ([string]::IsNullOrWhiteSpace([string]$app.Id) -or [string]::IsNullOrWhiteSpace([string]$app.Name)) {
            throw 'A Nerdio Shell App has no verifiable ID or name. Review the destination before publishing.'
        }
    }
    if ($Operation -eq 'Create') {
        if (@($apps | Where-Object { $_.Name.Trim() -ieq $Name.Trim() }).Count -ne 0) {
            throw "A Nerdio Shell App named '$Name' already exists. Select an existing app instead."
        }
        Assert-EwNerdioDestination -Destination $Destination
        return [PSCustomObject]@{ Id = ''; Name = $Name; Publisher = ''; Versions = @() }
    }
    $matchedApps = @($apps | Where-Object { [string]$_.Id -ieq $ShellAppId })
    if ($matchedApps.Count -ne 1) { throw 'The selected Nerdio Shell App could not be uniquely verified.' }
    $app = $matchedApps[0]
    $versions = @(
        foreach ($version in @(Get-EwNerdioShellAppVersion -Id $ShellAppId)) {
            $value = [string](Get-EwFirstPropertyValue -InputObject $version -Name 'version', 'displayVersion', 'name')
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw 'A Nerdio Shell App version cannot be verified.'
            }
            $value
        }
    ) | Sort-Object
    Assert-EwNerdioDestination -Destination $Destination
    [PSCustomObject]@{
        Id = [string]$app.Id
        Name = [string]$app.Name
        Publisher = [string]$app.Publisher
        Versions = [string[]]@($versions)
    }
}
