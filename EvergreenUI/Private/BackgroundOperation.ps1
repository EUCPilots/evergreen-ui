#Requires -Version 5.1

function Start-BackgroundOperation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$Operations,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Feature,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationId,

        [Parameter(Mandatory)]
        [System.Management.Automation.PowerShell]$PowerShell,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.Runspace]$Runspace,

        [Parameter()]
        [object]$Timer,

        [Parameter()]
        [scriptblock]$CompletionAction,

        [Parameter()]
        [object]$CallbackState
    )

    $activeOperation = @($Operations.Values | Where-Object {
            $_.Feature -eq $Feature -and $_.Status -in @('Starting', 'Running', 'Cancelling')
        }) | Select-Object -First 1
    if ($null -ne $activeOperation) {
        throw "Feature '$Feature' already has an active background operation ('$($activeOperation.OperationId)')."
    }

    $key = "$Feature::$OperationId"
    if ($Operations.ContainsKey($key)) {
        throw "Background operation '$key' is already registered."
    }
    if (-not $PSCmdlet.ShouldProcess($key, 'Start background operation')) {
        return $null
    }

    $operation = [PSCustomObject]@{
        Key              = $key
        Feature          = $Feature
        OperationId      = $OperationId
        PowerShell       = $PowerShell
        Runspace         = $Runspace
        AsyncResult      = $null
        Timer            = $Timer
        CompletionAction = $CompletionAction
        CallbackState    = $CallbackState
        Status           = 'Starting'
        StartedAt        = Get-Date
    }
    $Operations[$key] = $operation

    try {
        $operation.AsyncResult = $PowerShell.BeginInvoke()
        $operation.Status = 'Running'
        return $operation
    }
    catch {
        $operation.Status = 'Failed'
        [void]$Operations.Remove($key)
        try {
            $PowerShell.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose PowerShell after '$key' startup failure: $($_.Exception.Message)"
        }
        try {
            $Runspace.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose runspace after '$key' startup failure: $($_.Exception.Message)"
        }
        throw
    }
}

function Complete-BackgroundOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$Operations,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    if (-not $Operations.ContainsKey($Key)) {
        return $null
    }

    $operation = $Operations[$Key]
    if ($null -eq $operation.AsyncResult -or -not $operation.AsyncResult.IsCompleted) {
        return [PSCustomObject]@{
            WasCompleted = $false
            Feature      = $operation.Feature
            OperationId  = $operation.OperationId
            Status       = $operation.Status
            Output       = @()
            Error        = $null
        }
    }

    $output = @()
    $operationError = $null
    try {
        $output = @($operation.PowerShell.EndInvoke($operation.AsyncResult))
        $operation.Status = 'Completed'
    }
    catch {
        $operation.Status = 'Failed'
        $operationError = $_
    }

    $result = [PSCustomObject]@{
        WasCompleted = $true
        Feature      = $operation.Feature
        OperationId  = $operation.OperationId
        Status       = $operation.Status
        Output       = $output
        Error        = $operationError
    }

    try {
        if ($null -ne $operation.CompletionAction) {
            & $operation.CompletionAction -Operation $operation -Result $result -State $operation.CallbackState
        }
    }
    finally {
        try {
            $operation.PowerShell.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose PowerShell for '$Key': $($_.Exception.Message)"
        }
        try {
            $operation.Runspace.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose runspace for '$Key': $($_.Exception.Message)"
        }
        [void]$Operations.Remove($Key)
    }

    return $result
}

function Invoke-BackgroundOperationPoll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$Operations
    )

    $results = @()
    foreach ($key in @($Operations.Keys)) {
        $operation = $Operations[$key]
        if ($null -ne $operation.AsyncResult -and $operation.AsyncResult.IsCompleted) {
            $results += Complete-BackgroundOperation -Operations $Operations -Key $key
        }
    }

    return $results
}

function Stop-BackgroundOperation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$Operations,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    if (-not $Operations.ContainsKey($Key)) {
        return $false
    }
    if (-not $PSCmdlet.ShouldProcess($Key, 'Stop background operation')) {
        return $false
    }

    $operation = $Operations[$Key]
    $operation.Status = 'Cancelling'
    try {
        $operation.PowerShell.Stop()
    }
    catch {
        Write-Verbose -Message "EvergreenUI: Failed to stop background operation '$Key': $($_.Exception.Message)"
    }

    if ($null -ne $operation.AsyncResult) {
        try {
            [void]$operation.PowerShell.EndInvoke($operation.AsyncResult)
        }
        catch {
            Write-Verbose -Message "EvergreenUI: EndInvoke after cancelling '$Key' reported: $($_.Exception.Message)"
        }
    }
    $operation.Status = 'Cancelled'

    try {
        if ($null -ne $operation.CompletionAction) {
            $result = [PSCustomObject]@{
                WasCompleted = $true
                Feature      = $operation.Feature
                OperationId  = $operation.OperationId
                Status       = $operation.Status
                Output       = @()
                Error        = $null
            }
            & $operation.CompletionAction -Operation $operation -Result $result -State $operation.CallbackState
        }
    }
    finally {
        try {
            $operation.PowerShell.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose cancelled PowerShell for '$Key': $($_.Exception.Message)"
        }
        try {
            $operation.Runspace.Dispose()
        }
        catch {
            Write-Verbose -Message "EvergreenUI: Failed to dispose cancelled runspace for '$Key': $($_.Exception.Message)"
        }
        [void]$Operations.Remove($Key)
    }

    return $true
}

function Clear-BackgroundOperation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$Operations
    )

    foreach ($key in @($Operations.Keys)) {
        if ($PSCmdlet.ShouldProcess($key, 'Clear background operation')) {
            [void](Stop-BackgroundOperation -Operations $Operations -Key $key -Confirm:$false)
        }
    }
}