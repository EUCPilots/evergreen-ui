#Requires -Version 5.1

function Set-LoadingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ButtonStates,

        [Parameter(Mandatory = $true)]
        [bool]$IsLoading,

        [object[]]$Buttons = @(),

        [object[]]$LoadingControls = @(),

        [object]$LoadingLabel,

        [string]$LoadingMessage = '',

        [string]$IdleLoadingMessage = '',

        [object]$StatusLabel,

        [string]$LoadingStatusMessage = 'Working...',

        [string]$IdleStatusMessage = '',

        [bool]$ClearStatusOnIdle = $true
    )

    foreach ($button in @($Buttons)) {
        if ($null -eq $button) {
            continue
        }

        $buttonName = [string]$button.Name
        if ($IsLoading) {
            $ButtonStates[$buttonName] = [bool]$button.IsEnabled
            $button.IsEnabled = $false
        }
        elseif ($ButtonStates.ContainsKey($buttonName)) {
            $button.IsEnabled = [bool]$ButtonStates[$buttonName]
        }
    }

    if (-not $IsLoading) {
        $ButtonStates.Clear()
    }

    foreach ($control in @($LoadingControls)) {
        if ($null -ne $control) {
            $control.Visibility = if ($IsLoading) { 'Visible' } else { 'Collapsed' }
        }
    }

    if ($null -ne $LoadingLabel) {
        if ($IsLoading -and -not [string]::IsNullOrWhiteSpace($LoadingMessage)) {
            $LoadingLabel.Text = $LoadingMessage
        }
        elseif (-not $IsLoading -and -not [string]::IsNullOrWhiteSpace($IdleLoadingMessage)) {
            $LoadingLabel.Text = $IdleLoadingMessage
        }
    }

    if ($null -ne $StatusLabel -and ($IsLoading -or $ClearStatusOnIdle)) {
        $StatusLabel.Text = if ($IsLoading) {
            if ([string]::IsNullOrWhiteSpace($LoadingMessage)) { $LoadingStatusMessage } else { $LoadingMessage }
        }
        else {
            $IdleStatusMessage
        }
    }
}