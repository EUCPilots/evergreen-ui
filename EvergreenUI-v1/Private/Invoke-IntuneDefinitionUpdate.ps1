#Requires -Version 5.1
<#
.SYNOPSIS
    Updates App.json and Source\Install.json definition files with the latest
    version resolved via each definition's Application.Filter expression.

.DESCRIPTION
    For each valid definition row (DefinitionValid -eq 'Yes'), invokes
    Get-IntunePackageLatestVersion to resolve the current latest version and
    download URI from Evergreen. When a newer version or different filename is
    found the following fields are written back to disk:

    App.json:
      - PackageInformation.Version
      - PackageInformation.SetupFile  (filename derived from resolved URI)
      - DetectionRule[*].VersionValue  (File / Version detection rules)
      - DetectionRule[*].Value         (Registry / VersionComparison detection rules)

    Source\Install.json (when present alongside App.json):
      - PackageInformation.Version
      - PackageInformation.SetupFile

    Definitions whose resolved version and derived filename match what is already
    stored are skipped (no file writes). All file operations are best-effort; a
    failure on one definition does not abort processing of the remaining rows.

.PARAMETER DefinitionRows
    Array of definition row objects as stored in $syncHash.IntuneDefinitionRows.
    Each row must have DefinitionValid, DefinitionPath, Name, and DefinitionObject.

.PARAMETER SyncHash
    Synchronized hashtable shared with the UI thread. Used by Write-UILog for
    thread-safe log output.

.OUTPUTS
    Array of PSCustomObject with:
        Name           : string  - display name of the definition
        DefinitionPath : string  - full path to App.json
        OldVersion     : string  - version before update
        NewVersion     : string  - version after update (same as OldVersion when NoUpdateNeeded)
        NewSetupFile   : string  - SetupFile value written (empty when NoUpdateNeeded or failed)
        Succeeded      : bool
        NoUpdateNeeded : bool    - true when version and filename were already current
        Error          : string  - populated on failure
#>
function Invoke-IntuneDefinitionUpdate {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$DefinitionRows,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $DefinitionRows) {
        $name           = [string]$row.Name
        $definitionPath = [string]$row.DefinitionPath
        $oldVersion     = [string]$row.Version

        $resultBase = [PSCustomObject]@{
            Name           = $name
            DefinitionPath = $definitionPath
            OldVersion     = $oldVersion
            NewVersion     = $oldVersion
            NewSetupFile   = ''
            Succeeded      = $false
            NoUpdateNeeded = $false
            Error          = ''
        }

        if ([string]$row.DefinitionValid -ne 'Yes') {
            $resultBase.Error = 'Skipped: definition is not valid.'
            $results.Add($resultBase)
            continue
        }

        if ($null -eq $row.DefinitionObject) {
            $resultBase.Error = 'Skipped: definition object is null.'
            $results.Add($resultBase)
            continue
        }

        Write-Verbose "EvergreenUI: resolving latest version for '$name'..."
        Write-UILog -SyncHash $SyncHash -Message "Intune update: resolving '$name'..." -Level Info

        $latestResult = $null
        try {
            $latestResult = Get-IntunePackageLatestVersion -DefinitionObject $row.DefinitionObject -ErrorAction Stop
        }
        catch {
            $resultBase.Error = "Get-IntunePackageLatestVersion threw: $($_.Exception.Message)"
            Write-UILog -SyncHash $SyncHash -Message "Intune update: failed to resolve '$name' - $($_.Exception.Message)" -Level Warning
            $results.Add($resultBase)
            continue
        }

        if (-not $latestResult.Succeeded) {
            $resultBase.Error = $latestResult.Error
            Write-UILog -SyncHash $SyncHash -Message "Intune update: failed to resolve '$name' - $($latestResult.Error)" -Level Warning
            $results.Add($resultBase)
            continue
        }

        $newVersion = [string]$latestResult.Version

        # Derive new SetupFile from URI; fall back to existing value when URI is empty
        $newSetupFile = ''
        if (-not [string]::IsNullOrWhiteSpace($latestResult.URI)) {
            $rawFileName = [System.IO.Path]::GetFileName($latestResult.URI)
            if (-not [string]::IsNullOrWhiteSpace($rawFileName)) {
                $newSetupFile = [System.Uri]::UnescapeDataString($rawFileName)
            }
        }

        $currentSetupFile = ''
        if ($null -ne $row.DefinitionObject.PackageInformation) {
            $currentSetupFile = [string]$row.DefinitionObject.PackageInformation.SetupFile
        }

        if ([string]::IsNullOrWhiteSpace($newSetupFile)) {
            $newSetupFile = $currentSetupFile
        }

        # Skip if nothing changed
        if ($newVersion -eq $oldVersion -and $newSetupFile -eq $currentSetupFile) {
            $resultBase.Succeeded      = $true
            $resultBase.NoUpdateNeeded = $true
            $resultBase.NewVersion     = $newVersion
            Write-UILog -SyncHash $SyncHash -Message "Intune update: '$name' is already current ($oldVersion)." -Level Info
            $results.Add($resultBase)
            continue
        }

        # Update App.json
        try {
            $appJson = Get-Content -LiteralPath $definitionPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            $appJson.PackageInformation.Version   = $newVersion
            $appJson.PackageInformation.SetupFile = $newSetupFile

            # Update version values embedded in detection rules
            if ($null -ne $appJson.DetectionRule) {
                foreach ($rule in $appJson.DetectionRule) {
                    if ($null -eq $rule) {
                        continue
                    }
                    $ruleType   = [string]$rule.Type
                    $ruleMethod = [string]$rule.DetectionMethod
                    if ($ruleType -ieq 'File' -and $ruleMethod -ieq 'Version') {
                        $rule.VersionValue = $newVersion
                    }
                    elseif ($ruleType -ieq 'Registry' -and $ruleMethod -ieq 'VersionComparison') {
                        $rule.Value = $newVersion
                    }
                }
            }

            $appJson | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $definitionPath -Encoding UTF8 -ErrorAction Stop

            Write-UILog -SyncHash $SyncHash -Message "Intune update: '$name' App.json updated $oldVersion -> $newVersion (SetupFile: $newSetupFile)." -Level Info
        }
        catch {
            $resultBase.Error = "Failed to update App.json: $($_.Exception.Message)"
            Write-UILog -SyncHash $SyncHash -Message "Intune update: '$name' App.json write failed - $($_.Exception.Message)" -Level Error
            $results.Add($resultBase)
            continue
        }

        # Update Source\Install.json when present
        $installJsonPath = Join-Path -Path (Split-Path -Path $definitionPath -Parent) -ChildPath 'Source'
        $installJsonPath = Join-Path -Path $installJsonPath -ChildPath 'Install.json'
        if (Test-Path -LiteralPath $installJsonPath -PathType Leaf) {
            try {
                $installJson = Get-Content -LiteralPath $installJsonPath -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop

                if ($null -ne $installJson.PackageInformation) {
                    $installJson.PackageInformation.Version   = $newVersion
                    $installJson.PackageInformation.SetupFile = $newSetupFile
                }

                $installJson | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath $installJsonPath -Encoding UTF8 -ErrorAction Stop

                Write-UILog -SyncHash $SyncHash -Message "Intune update: '$name' Install.json updated." -Level Info
            }
            catch {
                # best-effort - Install.json failure must not mark the definition update as failed
                Write-UILog -SyncHash $SyncHash -Message "Intune update: '$name' Install.json write failed (non-fatal) - $($_.Exception.Message)" -Level Warning
                Write-Verbose "EvergreenUI: Install.json update failed for '$name': $($_.Exception.Message)"
            }
        }

        $resultBase.Succeeded    = $true
        $resultBase.NewVersion   = $newVersion
        $resultBase.NewSetupFile = $newSetupFile
        $results.Add($resultBase)
    }

    return $results.ToArray()
}
