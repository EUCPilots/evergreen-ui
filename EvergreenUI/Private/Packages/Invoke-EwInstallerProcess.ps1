Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwInstallerProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter()]
        [string]$ScriptPath,

        [Parameter()]
        [string]$Command
    )

    if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
        $process = Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $ScriptPath
        ) -WorkingDirectory $WorkingDirectory -Wait -PassThru -ErrorAction Stop
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Command)) {
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $Command) `
            -WorkingDirectory $WorkingDirectory -Wait -PassThru -ErrorAction Stop
    }
    else {
        throw 'No installer script or command was provided.'
    }
    [PSCustomObject]@{ ExitCode = [int]$process.ExitCode }
}
