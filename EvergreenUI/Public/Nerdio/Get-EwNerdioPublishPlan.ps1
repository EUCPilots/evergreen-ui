Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwNerdioPublishPlan {
    <#
    .SYNOPSIS
        Prepares a read-only Nerdio publishing comparison.
    .DESCRIPTION
        Resolves Evergreen sources, checks local scripts and records file and
        destination identities for confirmation. Does not download or publish.
    .PARAMETER DefinitionPath
        Root folder containing Shell App definition directories.
    .EXAMPLE
        $plan = Get-EwNerdioPublishPlan -DefinitionPath C:\ShellApps
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires an active Nerdio and Azure connection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath
    )

    $context = Get-EwNerdioSessionContext
    $destination = [PSCustomObject]@{
        SessionId = $context.SessionId
        TenantId = $context.TenantId
        SubscriptionId = $context.SubscriptionId
        NmeHost = $context.NmeHost
        ResourceGroupName = $context.ResourceGroupName
        StorageAccountName = $context.StorageAccountName
        ContainerName = $context.ContainerName
    }
    Assert-EwNerdioDestination -Destination $destination
    $root = (Resolve-Path -LiteralPath $DefinitionPath -ErrorAction Stop).Path
    $definitions = @(Get-EwNerdioDefinition -Path $root)
    $duplicates = @($definitions | Group-Object -Property {
        "$($_.Publisher.Trim())|$($_.AppName.Trim())".ToLowerInvariant()
    } | Where-Object Count -gt 1 | ForEach-Object Name)
    $rows = @(Compare-EwNerdioShellApp -DefinitionPath $root)
    foreach ($row in $rows) {
        $row | Add-Member -NotePropertyMembers @{
            Eligible = $false; Operation = ''; DefinitionHash = ''; SourceURI = ''; Artifact = $null
        }
        if ($row.RowType -ne 'Definition' -or $row.DefinitionValid -ne 'Yes' -or
            $row.MatchStatus -in @('Unsupported source type', 'Duplicate matches', 'Matched (compare unavailable)')) { continue }
        try {
            $key = "$($row.Publisher.Trim())|$($row.AppName.Trim())".ToLowerInvariant()
            if ($key -in $duplicates) { throw 'Multiple local definitions share the same publisher and name.' }
            $before = Get-EwNerdioDefinitionHash -DefinitionPath $row.DefinitionPath
            $definition = Get-EwNerdioPublishContent -DefinitionPath $row.DefinitionPath `
                -AddVersion:([bool]$row.NerdioAppId)
            foreach ($name in 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
                if (-not (Test-Path -LiteralPath (Join-Path -Path $row.DefinitionPath -ChildPath $name) -PathType Leaf)) {
                    throw "Required script '$name' is missing."
                }
            }
            $resolved = Resolve-EwNerdioSource -Source $definition.source
            $sourceVersion = ConvertTo-EwComparableVersion -Version $resolved.Version
            if (-not $sourceVersion.Success -or [string]::IsNullOrWhiteSpace($resolved.URI)) {
                throw 'The Evergreen source did not resolve a comparable version and download URI.'
            }
            if ($before -cne (Get-EwNerdioDefinitionHash -DefinitionPath $row.DefinitionPath)) {
                throw 'Definition files changed during comparison.'
            }
            $row.DefinitionHash = $before
            $row.SourceVersion = [string]$resolved.Version
            $row.SourceURI = [string]$resolved.URI
            $row.Artifact = $resolved.Artifact
            if (-not $row.NerdioAppId) {
                $row.Operation = 'Create'
                $row.Eligible = $true
            }
            else {
                $remoteVersion = ConvertTo-EwComparableVersion -Version $row.NerdioVersion
                if (-not $remoteVersion.Success) { throw 'The remote version cannot be compared.' }
                $row.Eligible = $sourceVersion.Parsed -gt $remoteVersion.Parsed
                $row.Operation = if ($row.Eligible) { 'Add version' } else { '' }
                $row.MatchStatus = if ($row.Eligible) { 'Matched (update available)' } else { 'Matched (No update required)' }
            }
        }
        catch {
            $row.Eligible = $false
            $row.Operation = ''
            $row.MatchStatus = 'Preflight failed'
            $row.Message = $_.Exception.Message -replace 'https?://\S+', '[URL omitted]'
            Write-Verbose -Message "EvergreenUI: Nerdio preflight failed for '$($row.AppName)': $($row.Message)"
        }
    }
    foreach ($row in $rows) {
        $row.Message = $row.Message -replace 'https?://\S+', '[URL omitted]'
    }
    Assert-EwNerdioDestination -Destination $destination
    [PSCustomObject]@{ DefinitionRoot = $root; Destination = $destination; Items = [object[]]$rows }
}
