Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-EwWorkbenchNerdioReviewDialog {
    [CmdletBinding()]
    [OutputType('System.Windows.MessageBoxResult')]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Owner,
        [Parameter(Mandatory)][psobject]$Result
    )

    $message = "Nerdio host: $($Result.NmeHost)`nApp: $($Result.Name)`nApp ID: $($Result.AppId)`nJob ID: $($Result.JobId)`n`n" +
        'Inspect this operation in Nerdio. Choose Yes only if it completed successfully, No only if it failed without completing, or Cancel if it is still unresolved. A success is verified by refreshing Nerdio before it can be pruned.'
    $dialog = New-EwWorkbenchConfirmationDialog -Owner $Owner -Title 'Review Nerdio outcome' `
        -Message $message -DefaultYes $false -Buttons YesNoCancel
    $null = $dialog.ShowDialog()
    return [System.Windows.MessageBoxResult]$dialog.Tag
}
