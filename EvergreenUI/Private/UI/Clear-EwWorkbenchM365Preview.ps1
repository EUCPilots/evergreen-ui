Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clear-EwWorkbenchM365Preview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State, [Parameter(Mandatory)][string]$Provider)

    if ($State.M365SuppressEvents) { return }
    $view = $State.M365Views[$Provider]
    $view.BuildPlan = $null
    $view.PublishPlan = $null
    $view.PreviewText.Text = 'Inputs changed. Preview the operation again.'
    Invoke-EwWorkbenchM365BusyState -State $State
}
