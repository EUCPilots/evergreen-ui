#Requires -Version 5.1
<#
.SYNOPSIS
    Derives a filesystem-safe folder name from a definition file path.

.DESCRIPTION
    Takes the immediate parent directory name of the given path and replaces any
    character that is not a word character, hyphen, or dot with an underscore.
    Leading/trailing underscores are trimmed.

    Used by packaging functions (Invoke-IntunePackageBuild,
    Invoke-LocalPackageInstall, Invoke-M365AppPackageBuild) to produce a
    consistent working-directory name under the shared WorkingPath root.

.PARAMETER DefinitionPath
    Full path to an App.json definition file (or any file whose parent directory
    name should be sanitised).

.OUTPUTS
    string — sanitised folder name safe for use as a directory name.

.EXAMPLE
    Get-SafeFolderName -DefinitionPath 'C:\Definitions\Microsoft Teams\App.json'
    # Returns: "Microsoft_Teams"
#>
function Get-SafeFolderName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath
    )

    $rawName = [System.IO.Path]::GetFileName(
        [System.IO.Path]::GetDirectoryName($DefinitionPath)
    )

    return [System.Text.RegularExpressions.Regex]::Replace(
        $rawName, '[^\w\-\.]', '_'
    ).Trim('_')
}
