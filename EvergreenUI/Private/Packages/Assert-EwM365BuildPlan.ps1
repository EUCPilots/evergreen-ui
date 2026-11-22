Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-EwM365BuildPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Plan)

    $names = @(
        'ConfigurationPath', 'ConfigurationRoot', 'ConfigurationId', 'ConfigurationHash',
        'UninstallHash', 'ShellHash', 'AppJsonTemplatePath', 'TemplateHash',
        'Provider', 'Channel', 'CompanyName', 'ImportFor', 'TenantId', 'SessionIdentity',
        'OfficeVersion', 'OfficeURI', 'ToolVersion', 'ToolURI'
    )
    foreach ($name in $names) {
        if ($null -eq $Plan.PSObject.Properties[$name]) {
            throw 'The Microsoft 365 build preview is incomplete. Preview again.'
        }
    }
    $current = Get-EwM365BuildPlan -ConfigurationPath $Plan.ConfigurationPath `
        -ConfigurationRoot $Plan.ConfigurationRoot -Provider $Plan.Provider -Channel $Plan.Channel `
        -CompanyName $Plan.CompanyName -ImportFor $Plan.ImportFor -TenantId $Plan.TenantId `
        -AppJsonTemplatePath $Plan.AppJsonTemplatePath
    foreach ($name in $names) {
        if ([string]$Plan.$name -cne [string]$current.$name) {
            throw "The confirmed Microsoft 365 build input '$name' changed. Preview and confirm again."
        }
    }
}
