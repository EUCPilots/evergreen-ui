Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-EwWorkbenchLibraryRemoval {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][psobject[]]$Row,
        [Parameter(Mandatory)][bool]$EntireApplication
    )

    $dialog = New-EwWorkbenchLibraryRemovalDialog -Owner $Window -Path $Path -Name $Name -Row $Row -EntireApplication $EntireApplication
    return $dialog.ShowDialog() -eq $true
}
