Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Compare-EwDetectionValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Left,

        [Parameter(Mandatory)]
        [string]$Right,

        [Parameter()]
        [string]$Operator = 'equal',

        [Parameter()]
        [ValidateSet('Version', 'Integer', 'String', 'Boolean')]
        [string]$Method = 'Version'
    )

    $operatorName = $Operator.Trim().ToLowerInvariant()
    $normalizedOperator = switch -Regex ($operatorName) {
        '^(equal|eq)$' { 'eq'; break }
        '^(notequal|ne)$' { 'ne'; break }
        '^(greaterthan|gt)$' { 'gt'; break }
        '^(greaterthanorequal|greaterthanorequals|ge)$' { 'ge'; break }
        '^(lessthan|lt)$' { 'lt'; break }
        '^(lessthanorequal|lessthanorequals|le)$' { 'le'; break }
        '^contains$' { 'contains'; break }
        default { 'eq' }
    }

    if ($Method -eq 'Version') {
        $leftVersion = $null
        $rightVersion = $null
        $leftText = ($Left -replace '[^0-9\.]', '').Trim('.')
        $rightText = ($Right -replace '[^0-9\.]', '').Trim('.')
        if ([version]::TryParse($leftText, [ref]$leftVersion) -and
            [version]::TryParse($rightText, [ref]$rightVersion)) {
            $comparison = $leftVersion.CompareTo($rightVersion)
            switch ($normalizedOperator) {
                'eq' { return $comparison -eq 0 }
                'ne' { return $comparison -ne 0 }
                'gt' { return $comparison -gt 0 }
                'ge' { return $comparison -ge 0 }
                'lt' { return $comparison -lt 0 }
                'le' { return $comparison -le 0 }
                default { return $false }
            }
        }
    }
    elseif ($Method -eq 'Integer') {
        $leftNumber = 0L
        $rightNumber = 0L
        if ([long]::TryParse($Left, [ref]$leftNumber) -and [long]::TryParse($Right, [ref]$rightNumber)) {
            $comparison = $leftNumber.CompareTo($rightNumber)
            switch ($normalizedOperator) {
                'eq' { return $comparison -eq 0 }
                'ne' { return $comparison -ne 0 }
                'gt' { return $comparison -gt 0 }
                'ge' { return $comparison -ge 0 }
                'lt' { return $comparison -lt 0 }
                'le' { return $comparison -le 0 }
                default { return $false }
            }
        }
    }
    elseif ($Method -eq 'Boolean') {
        $leftBoolean = $false
        $rightBoolean = $false
        $leftValid = [bool]::TryParse($Left, [ref]$leftBoolean)
        $rightValid = [bool]::TryParse($Right, [ref]$rightBoolean)
        if ($leftValid -and $rightValid) {
            return if ($normalizedOperator -eq 'ne') { $leftBoolean -ne $rightBoolean } else { $leftBoolean -eq $rightBoolean }
        }
    }

    switch ($normalizedOperator) {
        'ne' { return -not [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase) }
        'contains' { return $Left.IndexOf($Right, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
        default { return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase) }
    }
}
