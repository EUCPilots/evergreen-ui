Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Open-EwWorkbenchFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "Folder path '$Path' is not a fully qualified path."
    }
    if (-not [IO.Directory]::Exists($Path)) {
        throw "Folder '$Path' does not exist."
    }
    Write-Verbose -Message "EvergreenUI: Opening folder '$Path' in File Explorer"
    # Preserve trailing backslashes when Windows parses the closing quote.
    $trailingBackslashes = $Path.Length - $Path.TrimEnd([char]'\').Length
    $argument = '"{0}{1}"' -f $Path, ('\' * $trailingBackslashes)
    Start-Process -FilePath 'explorer.exe' -ArgumentList $argument -ErrorAction Stop
    Write-Verbose -Message 'EvergreenUI: Opened folder in File Explorer'
}
