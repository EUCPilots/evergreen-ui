Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-EwWorkbenchAboutRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    try {
        $loaded = @(
            Get-Module -All -ErrorAction Stop | ForEach-Object {
                [PSCustomObject]@{ Name = [string]$_.Name; Version = [string]$_.Version }
            }
        )
        $root = Split-Path -Path $script:ewModulePath -Parent
        $dependencyScript = Join-Path -Path $root -ChildPath 'Public\Dependencies\Get-EwDependency.ps1'
        $State.AboutDependencyStatusLabel.Text = 'Refreshing local dependency status...'
        $State.RefreshAboutDependenciesButton.IsEnabled = $false
        $request = @{
            Name = 'Refresh dependency status'
            LoadedModules = $loaded
            ArgumentList = @($dependencyScript)
            ScriptBlock = {
                param($DependencyScript)

                # Module discovery can block in unmanaged I/O, so keep it outside the stoppable Job worker.
                $scanner = [powershell]::Create()
                try {
                    $scan = {
                        param($Path)
                        . $Path
                        Get-EwDependency
                    }
                    $null = $scanner.AddScript($scan.ToString()).AddArgument($DependencyScript)
                    $scannerExpression = [System.Linq.Expressions.Expression]::Constant($scanner, [powershell])
                    $invoke = [powershell].GetMethods() | Where-Object {
                        $_.Name -eq 'Invoke' -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 0
                    } | Select-Object -First 1
                    $dispose = [powershell].GetMethod('Dispose', [type[]]@())
                    $body = [System.Linq.Expressions.Expression]::TryFinally(
                        [System.Linq.Expressions.Expression]::Call(
                            $scannerExpression, $invoke, [System.Linq.Expressions.Expression[]]@()
                        ),
                        [System.Linq.Expressions.Expression]::Call(
                            $scannerExpression, $dispose, [System.Linq.Expressions.Expression[]]@()
                        )
                    )
                    $runScan = [System.Linq.Expressions.Expression]::Lambda[
                        System.Func[System.Collections.ObjectModel.Collection[psobject]]
                    ]($body, [System.Linq.Expressions.ParameterExpression[]]@()).Compile()
                    $task = [System.Threading.Tasks.Task]::Run[
                        System.Collections.ObjectModel.Collection[psobject]
                    ]($runScan)
                }
                catch {
                    $scanner.Dispose()
                    throw
                }
                while (-not $task.IsCompleted) {
                    Start-Sleep -Milliseconds 100
                }
                $task.GetAwaiter().GetResult()
            }
        }
        Invoke-EwWorkbenchInfoJob -State $State -Kind 'About' -Request $request
    }
    catch {
        $slot = $State.InfoJobs.About
        $slot.Generation = [int]$slot.Generation + 1
        $slot.Pending = $null
        $request = @{ LoadedModules = @() }
        Invoke-EwWorkbenchInfoJobResult -State $State -Kind 'About' -Request $request `
            -ErrorMessage $_.Exception.Message
    }
}
