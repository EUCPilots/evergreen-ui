Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-EwNerdioShellAppVersion {
    <#
    .SYNOPSIS
        Removes old versions of a Nerdio Manager Shell App.
    .DESCRIPTION
        Keeps the newest versions of a Shell App and deletes the older ones.
        Versions are ordered by their numeric version; names that cannot be
        parsed are treated as the newest and are kept.
    .PARAMETER Id
        Shell App ID.
    .PARAMETER KeepVersions
        Number of the newest versions to keep.
    .EXAMPLE
        Remove-EwNerdioShellAppVersion -Id 42 -KeepVersions 3 -WhatIf
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires Connect-EwNerdio.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$KeepVersions
    )

    process {
        $context = Get-EwNerdioSessionContext
        $names = @(Get-EwNerdioShellAppVersion -Id $Id | ForEach-Object {
                [string](Get-EwFirstPropertyValue -InputObject $_ -Name 'name', 'version')
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $sorted = @($names | Sort-Object -Property @{ Expression = { ConvertTo-EwNerdioVersionSortKey -Name $_ } }, @{ Expression = { $_ } })
        $removeCount = [Math]::Max(0, $sorted.Count - $KeepVersions)
        $candidates = @(if ($removeCount -gt 0) { $sorted[0..($removeCount - 1)] })
        Write-Verbose -Message "EvergreenUI: Shell App '$Id' has $($sorted.Count) versions; $removeCount selected for removal"

        $removed = [System.Collections.Generic.List[string]]::new()
        $failed = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $candidates) {
            if (-not $PSCmdlet.ShouldProcess("Shell App $Id version $name", 'Remove')) {
                continue
            }
            $uri = "https://$($context.NmeHost)/api/v1/shell-app/$([uri]::EscapeDataString($Id))/version/$([uri]::EscapeDataString($name))"
            try {
                $response = Invoke-EwNerdioApiRequest -Method DELETE -Uri $uri -AccessToken $context.AccessToken
                $job = Get-EwFirstPropertyValue -InputObject $response -Name 'job'
                $status = [string](Get-EwFirstPropertyValue -InputObject $job -Name 'status')
                if ($status -in @('Completed', 'Pending')) {
                    $removed.Add($name)
                    Write-Verbose -Message "EvergreenUI: Removed Shell App '$Id' version '$name' (status: $status)"
                }
                else {
                    $failed.Add($name)
                    Write-Verbose -Message "EvergreenUI: Removing Shell App '$Id' version '$name' returned status '$status'"
                }
            }
            catch {
                $failed.Add($name)
                Write-Verbose -Message "EvergreenUI: Removing Shell App '$Id' version '$name' failed: $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            Id = $Id
            TotalVersions = $sorted.Count
            KeepVersions = $KeepVersions
            RequestedRemovals = $candidates.Count
            RemovedCount = $removed.Count
            RemovedVersions = $removed.ToArray()
            FailedCount = $failed.Count
            FailedVersions = $failed.ToArray()
        }
    }
}
