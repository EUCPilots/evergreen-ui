Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchPackageDefinitionsLoad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [switch]$Automatic
    )

    if ($Automatic) {
        if ($State.PackageDefinitionsLoadAttempted -or -not $State.DefinitionsTab.IsSelected -or
            $State.PackagesPanel.Visibility -ne [System.Windows.Visibility]::Visible) {
            return
        }
    }

    $path = [string]$State.IntuneDefinitionsPathBox.Text
    if ([string]::IsNullOrWhiteSpace($path)) {
        $State.PackageDefinitionsLoadPending = $false
        if (-not $Automatic) {
            Write-EwWorkbenchLog -State $State -Message 'Set the Intune definitions folder before loading definitions.' -Level Warning
        }
        return
    }
    if ($Automatic -and $State.PackageDefinitionsStartupDeferred) {
        $State.PackageDefinitionsLoadPending = $true
        return
    }
    if ($null -ne $State.ActiveJobId -or $State.InstallBatchActive) {
        if ($Automatic -and -not $State.PackageDefinitionsLoadPending) {
            $State.PackageDefinitionsLoadPending = $true
            Write-EwWorkbenchLog -State $State -Message 'Definitions load pending. Waiting for the current operation to finish.'
        }
        return
    }

    $State.PackageDefinitionsLoadPending = $false
    $State.PackageDefinitionsLoadAttempted = $true
    $State.PackageDefinitionsJobPath = $path
    try {
        Invoke-EwWorkbenchJob -State $State -Kind 'PackageDefinitions' -Name 'Load Intune package definitions' -ScriptBlock {
            param($DefinitionPath)
            [PSCustomObject]@{
                Items = @(Get-EwDefinition -Path $DefinitionPath)
            }
        } -ArgumentList @($path)
    }
    catch {
        Write-EwWorkbenchLog -State $State -Message "Could not load Intune definitions: $($_.Exception.Message) Reload definitions to retry." -Level Error
    }
}
