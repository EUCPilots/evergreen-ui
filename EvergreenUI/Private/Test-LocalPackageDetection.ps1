#Requires -Version 5.1
<#!
.SYNOPSIS
    Evaluates App.json DetectionRule entries on the local machine.

.DESCRIPTION
    Supports File, Registry, and MSI rule types and returns whether all rules
    pass, with the best available detected version.

.PARAMETER DefinitionObject
    Parsed App.json definition object.

.OUTPUTS
    PSCustomObject with:
        Succeeded       : bool
        Installed       : bool
        DetectedVersion : string
        Status          : string
        RuleCount       : int
        RulePassCount   : int
        Error           : string
!#>
function Test-LocalPackageDetection {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$DefinitionObject
    )

    $result = [PSCustomObject]@{
        Succeeded       = $false
        Installed       = $false
        DetectedVersion = ''
        Status          = ''
        RuleCount       = 0
        RulePassCount   = 0
        Error           = ''
    }

    if ($null -eq $DefinitionObject) {
        $result.Error = 'Definition object is null.'
        $result.Status = 'Detection failed'
        return $result
    }

    $rules = @($DefinitionObject.DetectionRule)
    if ($rules.Count -eq 0) {
        $result.Succeeded = $true
        $result.Status = 'No detection rules'
        return $result
    }

    $compareValues = {
        param(
            [string]$Operator,
            [string]$Left,
            [string]$Right
        )

        $op = if ([string]::IsNullOrWhiteSpace($Operator)) { 'equal' } else { $Operator.Trim() }

        $leftVersion = $null
        $rightVersion = $null
        $leftIsVersion = [version]::TryParse(($Left -replace '[^0-9\.]', '').Trim('.'), [ref]$leftVersion)
        $rightIsVersion = [version]::TryParse(($Right -replace '[^0-9\.]', '').Trim('.'), [ref]$rightVersion)

        if ($leftIsVersion -and $rightIsVersion) {
            switch -Regex ($op.ToLowerInvariant()) {
                '^equal$|^eq$' { return $leftVersion -eq $rightVersion }
                '^notequal$|^ne$' { return $leftVersion -ne $rightVersion }
                '^greaterthan$|^gt$' { return $leftVersion -gt $rightVersion }
                '^greaterthanorequal$|^greaterthanorequals$|^ge$' { return $leftVersion -ge $rightVersion }
                '^lessthan$|^lt$' { return $leftVersion -lt $rightVersion }
                '^lessthanorequal$|^lessthanorequals$|^le$' { return $leftVersion -le $rightVersion }
                default { return $leftVersion -eq $rightVersion }
            }
        }

        switch -Regex ($op.ToLowerInvariant()) {
            '^equal$|^eq$' { return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase) }
            '^notequal$|^ne$' { return -not [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase) }
            '^contains$' { return ([string]$Left).IndexOf([string]$Right, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
            default { return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase) }
        }
    }

    $resolveRegistryPath = {
        param(
            [string]$RawPath,
            [bool]$Check32BitOn64System
        )

        if ([string]::IsNullOrWhiteSpace($RawPath)) {
            return ''
        }

        $normalized = $RawPath.Trim()
        if ($normalized -match '^HKEY_LOCAL_MACHINE' -or $normalized -match '^HKLM') {
            $normalized = $normalized -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^HKLM', 'HKLM:'
        }
        elseif ($normalized -match '^HKEY_CURRENT_USER' -or $normalized -match '^HKCU') {
            $normalized = $normalized -replace '^HKEY_CURRENT_USER', 'HKCU:' -replace '^HKCU', 'HKCU:'
        }

        if ($Check32BitOn64System -and $normalized -like 'HKLM:*' -and $normalized -notmatch 'WOW6432Node') {
            $normalized = $normalized -replace '^HKLM:\Software', 'HKLM:\Software\WOW6432Node'
        }

        return $normalized
    }

    $detectedVersion = ''
    $ruleCount = 0
    $rulePassCount = 0

    try {
        foreach ($rule in $rules) {
            if ($null -eq $rule) { continue }
            $ruleCount++

            $ruleType = [string]$rule.Type
            $rulePassed = $false

            switch ($ruleType) {
                'File' {
                    $basePath = [string]$rule.Path
                    $fileOrFolder = [string]$rule.FileOrFolder
                    $targetPath = if ([string]::IsNullOrWhiteSpace($fileOrFolder)) {
                        $basePath
                    }
                    else {
                        Join-Path -Path $basePath -ChildPath $fileOrFolder
                    }

                    if (-not [string]::IsNullOrWhiteSpace($targetPath) -and (Test-Path -LiteralPath $targetPath)) {
                        $method = [string]$rule.DetectionMethod
                        if ($method -eq 'Version') {
                            $fileInfo = Get-Item -LiteralPath $targetPath -ErrorAction SilentlyContinue
                            $currentVersion = if ($null -ne $fileInfo -and $null -ne $fileInfo.VersionInfo) {
                                [string]$fileInfo.VersionInfo.FileVersion
                            }
                            else {
                                ''
                            }

                            if (-not [string]::IsNullOrWhiteSpace($currentVersion)) {
                                $detectedVersion = $currentVersion
                            }

                            $rulePassed = & $compareValues -Operator ([string]$rule.Operator) -Left $currentVersion -Right ([string]$rule.VersionValue)
                        }
                        else {
                            $rulePassed = $true
                        }
                    }
                }
                'Registry' {
                    $registryPath = & $resolveRegistryPath -RawPath ([string]$rule.KeyPath) -Check32BitOn64System ([string]$rule.Check32BitOn64System -ieq 'true')
                    if (-not [string]::IsNullOrWhiteSpace($registryPath) -and (Test-Path -LiteralPath $registryPath)) {
                        $method = [string]$rule.DetectionMethod
                        if ($method -eq 'Existence') {
                            $rulePassed = $true
                        }
                        else {
                            $valueName = [string]$rule.ValueName
                            $item = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
                            $currentValue = if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace($valueName)) {
                                [string]$item.$valueName
                            }
                            else {
                                ''
                            }

                            if ($method -eq 'Version' -and -not [string]::IsNullOrWhiteSpace($currentValue)) {
                                $detectedVersion = $currentValue
                            }

                            $expectedValue = if ($method -eq 'Version') { [string]$rule.DetectionValue } else { [string]$rule.DetectionValue }
                            $rulePassed = & $compareValues -Operator ([string]$rule.Operator) -Left $currentValue -Right $expectedValue
                        }
                    }
                }
                'MSI' {
                    $productCode = [string]$rule.ProductCode
                    if (-not [string]::IsNullOrWhiteSpace($productCode)) {
                        $normalizedCode = $productCode.Trim('{}').ToUpperInvariant()
                        $uninstallKeys = @(
                            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
                            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                        )

                        $matchedVersion = ''
                        foreach ($keyRoot in $uninstallKeys) {
                            if (-not (Test-Path -LiteralPath $keyRoot)) { continue }

                            $candidates = @(Get-ChildItem -LiteralPath $keyRoot -ErrorAction SilentlyContinue)
                            foreach ($candidate in $candidates) {
                                $leaf = [string]$candidate.PSChildName
                                if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                                if ($leaf.Trim('{}').ToUpperInvariant() -ne $normalizedCode) { continue }

                                $entry = Get-ItemProperty -LiteralPath $candidate.PSPath -ErrorAction SilentlyContinue
                                if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.DisplayVersion)) {
                                    $matchedVersion = [string]$entry.DisplayVersion
                                }
                                else {
                                    $matchedVersion = 'Installed'
                                }
                                break
                            }

                            if (-not [string]::IsNullOrWhiteSpace($matchedVersion)) {
                                break
                            }
                        }

                        if (-not [string]::IsNullOrWhiteSpace($matchedVersion)) {
                            if ($matchedVersion -ne 'Installed') {
                                $detectedVersion = $matchedVersion
                            }

                            $expectedVersion = [string]$rule.ProductVersion
                            if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
                                $rulePassed = $true
                            }
                            else {
                                $rulePassed = & $compareValues -Operator ([string]$rule.ProductVersionOperator) -Left $matchedVersion -Right $expectedVersion
                            }
                        }
                    }
                }
                default {
                    $rulePassed = $false
                }
            }

            if ($rulePassed) {
                $rulePassCount++
            }
        }

        $result.RuleCount = $ruleCount
        $result.RulePassCount = $rulePassCount
        $result.Succeeded = $true
        $result.Installed = ($ruleCount -gt 0 -and $rulePassCount -eq $ruleCount)
        $result.DetectedVersion = $detectedVersion
        if ($result.Installed) {
            $result.Status = if ([string]::IsNullOrWhiteSpace($detectedVersion)) { 'Installed' } else { "Installed ($detectedVersion)" }
        }
        else {
            $result.Status = 'Not installed'
        }
    }
    catch {
        $result.Succeeded = $false
        $result.Error = $_.Exception.Message
        $result.Status = 'Detection failed'
    }

    return $result
}
