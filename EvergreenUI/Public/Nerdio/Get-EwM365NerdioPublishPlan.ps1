Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwM365NerdioPublishPlan {
    <#
    .SYNOPSIS
        Previews a Microsoft 365 Nerdio publishing target.
    .DESCRIPTION
        Verifies the full Nerdio and Azure destination, selected Shell App,
        existing versions, and the Microsoft 365 build preview without writes.
        A matching version requires an explicit attestation because the remote
        configuration cannot be compared.
    .PARAMETER BuildPlan
        Nerdio preview from Get-EwM365BuildPlan.
    .PARAMETER Operation
        Create a Shell App or add a version to an existing one.
    .PARAMETER Name
        New Shell App name; defaults to the configuration display name.
    .PARAMETER ShellAppId
        Explicitly selected existing Shell App ID for Add version.
    .PARAMETER SameVersionAttested
        Confirms the configuration changed when the Office version already exists.
    .EXAMPLE
        Get-EwM365NerdioPublishPlan -BuildPlan $buildPlan -Operation Create
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Rechecks reduce drift but do not lock the provider destination.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][psobject]$BuildPlan,
        [Parameter(Mandatory)][ValidateSet('Create', 'Add version')][string]$Operation,
        [string]$Name,
        [string]$ShellAppId,
        [switch]$SameVersionAttested
    )

    if ($BuildPlan.Provider -ne 'Nerdio') { throw 'The build preview must target Nerdio.' }
    Assert-EwM365BuildPlan -Plan $BuildPlan
    if ($Operation -eq 'Add version' -and [string]::IsNullOrWhiteSpace($ShellAppId)) {
        throw 'Select an existing Nerdio Shell App before adding a version.'
    }
    if ($Operation -eq 'Create' -and -not [string]::IsNullOrWhiteSpace($ShellAppId)) {
        throw 'A Shell App ID cannot be supplied when creating a new app.'
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = (Read-EwM365Configuration -Path $BuildPlan.ConfigurationPath).DisplayName
    }
    $Name = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'The Shell App name cannot be empty.' }
    $context = Get-EwNerdioSessionContext
    if ($context.PSObject.Properties['ApiOnly'] -and $context.ApiOnly) {
        throw 'A full Nerdio connection with Azure storage is required for publishing.'
    }
    Assert-EwNerdioWriteAllowed -Context $context -ShellAppId $ShellAppId
    $destination = [PSCustomObject]@{
        SessionId = $context.SessionId; TenantId = $context.TenantId; SubscriptionId = $context.SubscriptionId
        NmeHost = $context.NmeHost; ResourceGroupName = $context.ResourceGroupName
        StorageAccountName = $context.StorageAccountName; ContainerName = $context.ContainerName
    }
    $target = Get-EwM365NerdioTarget -Destination $destination -Operation $Operation `
        -Name $Name -ShellAppId $ShellAppId
    $plan = [PSCustomObject]@{
        BuildPlan = $BuildPlan; Destination = $destination; Operation = $Operation
        Name = $Name; ShellAppId = [string]$ShellAppId; Target = $target
        SameVersionAttested = [bool]$SameVersionAttested
    }
    Assert-EwM365NerdioPublishPlan -Plan $plan
    return $plan
}
