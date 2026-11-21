Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-EwSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $path = Get-EwSettingsPath
    $directory = Split-Path -Path $path -Parent
    Write-Verbose -Message "EvergreenUI: Writing settings to $path"
    New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $temporaryPath = Join-Path -Path $directory -ChildPath ('.settings-{0}.tmp' -f [guid]::NewGuid())
    try {
        $json = ConvertTo-Json -InputObject $Settings -Depth 20 -ErrorAction Stop
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
    }
    Write-Verbose -Message "EvergreenUI: Settings saved to $path"
}
