Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-EwM365ChannelName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Channel
    )

    if ([string]::IsNullOrWhiteSpace($Channel) -or $Channel.StartsWith('#')) {
        return 'Set at build time'
    }
    $names = @{
        Current = 'Current Channel'
        CurrentPreview = 'Current Channel (Preview)'
        BetaChannel = 'Beta Channel'
        MonthlyEnterprise = 'Monthly Enterprise Channel'
        SemiAnnual = 'Semi-Annual Enterprise Channel'
        SemiAnnualPreview = 'Semi-Annual Enterprise Channel (Preview)'
        PerpetualVL2019 = 'Office LTSC 2019 (volume licensed)'
        PerpetualVL2021 = 'Office LTSC 2021 (volume licensed)'
        PerpetualVL2024 = 'Office LTSC 2024 (volume licensed)'
    }
    if ($names.ContainsKey($Channel)) { return $names[$Channel] }
    return $Channel
}
