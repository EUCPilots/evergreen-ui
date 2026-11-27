Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EwDetection {
    <#
    .SYNOPSIS
        Evaluates the local detection rules in an App.json definition.
    .DESCRIPTION
        Supports File, Registry, and MSI detection rules. All configured rules
        must pass for the package to be considered installed.
    .PARAMETER DefinitionPath
        Path to an App.json definition file.
    .PARAMETER DefinitionObject
        Parsed App.json definition object.
    .EXAMPLE
        Test-EwDetection -DefinitionPath .\Definitions\Example\App.json
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Registry and MSI rules require Windows.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionPath,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNull()]
        [psobject]$DefinitionObject
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $DefinitionPath -PathType Leaf)) {
            throw "Definition file was not found: $DefinitionPath"
        }
        $DefinitionObject = Get-Content -LiteralPath $DefinitionPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }

    $result = [PSCustomObject]@{
        Succeeded       = $false
        Installed       = $false
        DetectedVersion = ''
        Status          = ''
        RuleCount       = 0
        RulePassCount   = 0
        Error           = ''
    }
    $rules = @(Get-EwObjectPropertyValue -Object $DefinitionObject -Name DetectionRule -Default @() |
        Where-Object { $null -ne $_ })
    if ($rules.Count -eq 0) {
        $result.Succeeded = $true
        $result.Status = 'No detection rules'
        return $result
    }

    try {
        foreach ($rule in $rules) {
            $result.RuleCount++
            $ruleType = [string]$rule.Type
            $method = [string]$rule.DetectionMethod
            $passed = $false
            $currentValue = ''
            $expectedValue = ''

            switch ($ruleType.ToLowerInvariant()) {
                'file' {
                    $basePath = [string](Get-EwObjectPropertyValue -Object $rule -Name Path -Default '')
                    $relativePath = [string](Get-EwObjectPropertyValue -Object $rule -Name FileOrFolder -Default '')
                    $check32Bit = [string](Get-EwObjectPropertyValue -Object $rule -Name Check32BitOn64System -Default 'false') -ieq 'true'
                    $basePath = Resolve-EwDetectionFilePath -Path $basePath -Check32BitOn64System:$check32Bit
                    $targetPath = if ([string]::IsNullOrWhiteSpace($relativePath)) {
                        $basePath
                    }
                    else {
                        Join-Path -Path $basePath -ChildPath $relativePath
                    }
                    if (-not [string]::IsNullOrWhiteSpace($targetPath) -and
                        (Test-Path -LiteralPath $targetPath)) {
                        if ($method -ieq 'Version') {
                            $file = Get-Item -LiteralPath $targetPath -ErrorAction Stop
                            $currentValue = [string]$file.VersionInfo.FileVersion
                            $expectedValue = [string](Get-EwObjectPropertyValue -Object $rule -Name VersionValue -Default '')
                            $passed = Compare-EwDetectionValue -Left $currentValue -Right $expectedValue `
                                -Operator ([string](Get-EwObjectPropertyValue -Object $rule -Name Operator -Default 'equal')) -Method Version
                        }
                        else {
                            $passed = $true
                        }
                    }
                }
                'registry' {
                    $registryPath = [string](Get-EwObjectPropertyValue -Object $rule -Name KeyPath -Default '')
                    if ([string]::IsNullOrWhiteSpace($registryPath)) {
                        $registryPath = [string](Get-EwObjectPropertyValue -Object $rule -Name Path -Default '')
                    }
                    if (-not [string]::IsNullOrWhiteSpace($registryPath)) {
                        $valueName = [string](Get-EwObjectPropertyValue -Object $rule -Name ValueName -Default '')
                        $check32Bit = [string](Get-EwObjectPropertyValue -Object $rule -Name Check32BitOn64System -Default 'false') -ieq 'true'
                        $registryItem = Get-EwDetectionRegistryValue -Path $registryPath -ValueName $valueName -Check32BitOn64System:$check32Bit
                        if ($registryItem.KeyExists -and $method -ieq 'Existence' -and [string]::IsNullOrWhiteSpace($valueName)) {
                            $passed = $true
                        }
                        elseif ($registryItem.KeyExists -and $registryItem.ValueExists) {
                            $currentValue = [string]$registryItem.Value
                            $expectedValue = if ($null -ne $rule.PSObject.Properties['DetectionValue'] -and
                                -not [string]::IsNullOrWhiteSpace([string]$rule.DetectionValue)) {
                                [string](Get-EwObjectPropertyValue -Object $rule -Name DetectionValue -Default '')
                            }
                            else {
                                [string](Get-EwObjectPropertyValue -Object $rule -Name Value -Default '')
                            }
                            $comparisonMethod = switch -Regex ($method) {
                                '^VersionComparison$' { 'Version' }
                                '^IntegerComparison$' { 'Integer' }
                                '^BooleanComparison$' { 'Boolean' }
                                default { 'String' }
                            }
                            if ($comparisonMethod -eq 'String' -and [string]::IsNullOrWhiteSpace($method)) {
                                $comparisonMethod = 'Version'
                            }
                            if ($method -ieq 'Existence') {
                                $passed = $true
                            }
                            else {
                                $passed = Compare-EwDetectionValue -Left $currentValue -Right $expectedValue `
                                    -Operator ([string](Get-EwObjectPropertyValue -Object $rule -Name Operator -Default 'equal')) -Method $comparisonMethod
                            }
                            if ($comparisonMethod -eq 'Version') {
                                $result.DetectedVersion = $currentValue
                            }
                        }
                    }
                }
                'msi' {
                    $productCode = ([string](Get-EwObjectPropertyValue -Object $rule -Name ProductCode -Default '')).Trim('{}').ToUpperInvariant()
                    if (-not [string]::IsNullOrWhiteSpace($productCode)) {
                        foreach ($root in @(
                                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
                                'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                            )) {
                            if (-not (Test-Path -LiteralPath $root)) {
                                continue
                            }
                            foreach ($candidate in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
                                if ([string]$candidate.PSChildName -replace '[{}]', '' -ieq $productCode) {
                                    $installedProduct = Get-ItemProperty -LiteralPath $candidate.PSPath -ErrorAction Stop
                                    $currentValue = [string]$installedProduct.DisplayVersion
                                    $expectedValue = [string](Get-EwObjectPropertyValue -Object $rule -Name ProductVersion -Default '')
                                    if ([string]::IsNullOrWhiteSpace($expectedValue)) {
                                        $passed = $true
                                    }
                                    else {
                                        $passed = Compare-EwDetectionValue -Left $currentValue -Right $expectedValue `
                                            -Operator ([string](Get-EwObjectPropertyValue -Object $rule -Name ProductVersionOperator -Default 'equal')) -Method Version
                                    }
                                    $result.DetectedVersion = $currentValue
                                    break
                                }
                            }
                            if ($passed) {
                                break
                            }
                        }
                    }
                }
                default {
                    Write-Verbose -Message "EvergreenUI: Unsupported detection rule type '$ruleType'."
                }
            }

            if ($passed) {
                $result.RulePassCount++
            }
        }
        $result.Succeeded = $true
        $result.Installed = $result.RuleCount -gt 0 -and $result.RulePassCount -eq $result.RuleCount
        $result.Status = if ($result.Installed) {
            if ([string]::IsNullOrWhiteSpace($result.DetectedVersion)) { 'Installed' } else { "Installed ($($result.DetectedVersion))" }
        }
        else {
            'Not installed'
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        $result.Status = 'Detection failed'
    }
    return $result
}
