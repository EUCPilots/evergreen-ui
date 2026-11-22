Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchFolderCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][ValidateSet('Download', 'Library')][string]$Kind,
        [switch]$OpenAfterCheck
    )

    $slot = $State.InfoJobs[$Kind]
    $pathBox = $State["Settings${Kind}PathBox"]
    $button = $State["Open${Kind}FolderButton"]
    $status = $State["${Kind}FolderStatusLabel"]
    $path = [string]$pathBox.Text
    $button.IsEnabled = $false
    if ([string]::IsNullOrWhiteSpace($path)) {
        $slot.Generation = [int]$slot.Generation + 1
        $slot.Pending = $null
        Invoke-EwWorkbenchInfoJobCleanup -State $State -Kind $Kind
        $status.Text = "No $($Kind.ToLowerInvariant()) folder is configured."
        return
    }

    try {
        $basePath = [string](Get-Location -PSProvider FileSystem -ErrorAction Stop).ProviderPath
        $status.Text = 'Checking folder availability...'
        $request = @{
            Name = "Check $($Kind.ToLowerInvariant()) folder"
            Path = $path
            OpenAfterCheck = [bool]$OpenAfterCheck
            ArgumentList = @($path, $basePath)
            ScriptBlock = {
                param($Path, $BasePath)

                try {
                    $candidate = $Path
                    foreach ($prefix in 'Microsoft.PowerShell.Core\FileSystem::', 'FileSystem::') {
                        if ($candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $candidate = $candidate.Substring($prefix.Length)
                            break
                        }
                    }
                    $resolved = [System.IO.Path]::GetFullPath($candidate, $BasePath)
                    Write-Verbose -Message "EvergreenUI: Checking folder '$resolved'"
                    $method = [System.IO.Directory].GetMethod('Exists', [type[]]@([string]))
                    $argument = [System.Linq.Expressions.Expression]::Constant($resolved, [string])
                    $body = [System.Linq.Expressions.Expression]::Call(
                        $method, [System.Linq.Expressions.Expression[]]@($argument)
                    )
                    $probe = [System.Linq.Expressions.Expression]::Lambda[System.Func[bool]](
                        $body, [System.Linq.Expressions.ParameterExpression[]]@()
                    ).Compile()
                    $task = [System.Threading.Tasks.Task]::Run[bool]($probe)
                    while (-not $task.IsCompleted) {
                        Start-Sleep -Milliseconds 100
                    }
                    $available = $task.GetAwaiter().GetResult()
                    Write-Verbose -Message "EvergreenUI: Folder availability is '$available'"
                    [PSCustomObject]@{
                        Available = $available
                        ResolvedPath = $resolved
                        Error = if ($available) { '' } else { 'The folder does not exist or is unavailable.' }
                    }
                }
                catch {
                    [PSCustomObject]@{
                        Available = $false
                        ResolvedPath = ''
                        Error = $_.Exception.Message
                    }
                }
            }
        }
        Invoke-EwWorkbenchInfoJob -State $State -Kind $Kind -Request $request
    }
    catch {
        $message = "Could not check the folder: $($_.Exception.Message)"
        $slot.Generation = [int]$slot.Generation + 1
        $slot.Pending = $null
        Invoke-EwWorkbenchInfoJobCleanup -State $State -Kind $Kind
        $status.Text = $message
        Write-EwWorkbenchLog -State $State -Message $message -Level Error -PreserveStatus
    }
}
