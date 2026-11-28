Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntuneUpdateRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Definition
    )

    $fail = {
        param([string]$Message)
        [PSCustomObject]@{ Succeeded = $false; Rules = @(); Error = $Message }
    }
    $detectionRules = @(Get-EwObjectPropertyValue -Object $Definition -Name 'DetectionRule' -Default @() | Where-Object { $null -ne $_ })
    $customRules = @(Get-EwObjectPropertyValue -Object $Definition -Name 'CustomRequirementRule' -Default @() | Where-Object { $null -ne $_ })
    $generated = [System.Collections.Generic.List[object]]::new()
    $presence = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $detectionRules) {
        $type = [string](Get-EwObjectPropertyValue -Object $rule -Name 'Type')
        $method = [string](Get-EwObjectPropertyValue -Object $rule -Name 'DetectionMethod')
        $view = [string](Get-EwObjectPropertyValue -Object $rule -Name 'Check32BitOn64System' -Default 'false')
        $path = [string](Get-EwObjectPropertyValue -Object $rule -Name 'Path')
        $keyPath = [string](Get-EwObjectPropertyValue -Object $rule -Name 'KeyPath' -Default $path)
        $file = [string](Get-EwObjectPropertyValue -Object $rule -Name 'FileOrFolder')
        $valueName = [string](Get-EwObjectPropertyValue -Object $rule -Name 'ValueName')
        if ($type -eq 'File' -and -not [string]::IsNullOrWhiteSpace($path) -and
            -not [string]::IsNullOrWhiteSpace($file) -and $method -in @('Version', 'Existence')) {
            $presence.Add([PSCustomObject]@{
                    Type = 'File'; DetectionMethod = 'Existence'; Path = $path; FileOrFolder = $file; Check32BitOn64System = $view
                })
        }
        elseif ($type -eq 'Registry' -and -not [string]::IsNullOrWhiteSpace($keyPath) -and
            -not [string]::IsNullOrWhiteSpace($valueName) -and
            $method -in @('VersionComparison', 'Version', 'StringComparison', 'IntegerComparison', 'Existence')) {
            $presence.Add([PSCustomObject]@{
                    Type = 'Registry'; DetectionMethod = 'Existence'; KeyPath = $keyPath; ValueName = $valueName; Check32BitOn64System = $view
                })
        }
        if ($customRules.Count -gt 0) { continue }
        $operator = [string](Get-EwObjectPropertyValue -Object $rule -Name 'Operator')
        $negated = switch ($operator) {
            'greaterThanOrEqual' { 'lessThan' }
            'greaterThan' { 'lessThanOrEqual' }
            'lessThanOrEqual' { 'greaterThan' }
            'lessThan' { 'greaterThanOrEqual' }
            'equal' { 'notEqual' }
            'notEqual' { 'equal' }
            default { '' }
        }
        if ([string]::IsNullOrWhiteSpace($negated)) {
            Write-Verbose -Message "EvergreenUI: No comparable update requirement for detection type '$type' and operator '$operator'."
            continue
        }
        if ($type -eq 'File' -and $method -eq 'Version') {
            $version = [string](Get-EwObjectPropertyValue -Object $rule -Name 'VersionValue')
            if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($file) -or [string]::IsNullOrWhiteSpace($version)) { continue }
            $generated.Add([PSCustomObject]@{
                    Type = 'File'; DetectionMethod = 'Version'; Path = $path; FileOrFolder = $file
                    Operator = $negated; VersionValue = $version; Check32BitOn64System = $view
                })
        }
        elseif ($type -eq 'Registry' -and $method -in @('VersionComparison', 'Version', 'StringComparison', 'IntegerComparison')) {
            $value = [string](Get-EwObjectPropertyValue -Object $rule -Name 'DetectionValue' -Default (Get-EwObjectPropertyValue -Object $rule -Name 'Value'))
            if ([string]::IsNullOrWhiteSpace($keyPath) -or [string]::IsNullOrWhiteSpace($valueName) -or [string]::IsNullOrWhiteSpace($value)) { continue }
            $generated.Add([PSCustomObject]@{
                    Type = 'Registry'; DetectionMethod = if ($method -eq 'Version') { 'VersionComparison' } else { $method }
                    KeyPath = $keyPath; ValueName = $valueName; Operator = $negated; Value = $value; Check32BitOn64System = $view
                })
        }
    }
    if ($presence.Count -eq 0) {
        return (& $fail 'Update import requires File or Registry application detection with an explicit file or value whose existence can be required. MSI-only and script-only detection cannot establish this safeguard.')
    }
    if ($customRules.Count -eq 0 -and $generated.Count -eq 0) {
        return (& $fail 'Update import requires a comparable File or Registry detection rule, or explicit custom requirements, in addition to application presence.')
    }
    [object[]]$rules = @(if ($customRules.Count -gt 0) { $customRules } else { $generated })
    # Presence is required independently of version comparisons or user-authored requirements.
    $rules += @($presence)
    Write-Verbose -Message "EvergreenUI: Update import requires $($presence.Count) application presence checks and $($rules.Count) total requirements."
    [PSCustomObject]@{ Succeeded = $true; Rules = $rules; Error = '' }
}
