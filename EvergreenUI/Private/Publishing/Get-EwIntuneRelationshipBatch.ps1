Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwIntuneRelationshipBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$App
    )

    $pending = [System.Collections.Generic.Queue[object]]::new()
    $targets = @{}
    foreach ($item in $App) {
        $id = [string]$item.IntuneAppId
        $targets[$id] = [System.Collections.Generic.List[string]]::new()
        $pending.Enqueue([PSCustomObject]@{
            AppId = $id
            Url = "/deviceAppManagement/mobileApps/$id/relationships"
        })
    }
    $completed = 0
    while ($pending.Count -gt 0) {
        $pages = @(
            for ($index = 0; $index -lt 20 -and $pending.Count -gt 0; $index++) {
                $pending.Dequeue()
            }
        )
        $requests = @(for ($index = 0; $index -lt $pages.Count; $index++) {
            @{ id = [string]$index; method = 'GET'; url = $pages[$index].Url }
        })
        $retry = $requests
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Write-Verbose -Message "EvergreenUI: Reading $($retry.Count) Intune relationship pages in one batch (attempt $attempt)."
            $body = ConvertTo-Json -InputObject @{ requests = @($retry) } -Depth 5 -Compress
            $batch = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/beta/$batch' -Body $body -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
            $failed = [System.Collections.Generic.List[object]]::new()
            $wait = 0
            foreach ($request in $retry) {
                $responses = @(Get-EwObjectPropertyValue -Object $batch -Name 'responses' -Default @() | Where-Object { [string]$_.id -eq $request.id })
                $page = $pages[[int]$request.id]
                if ($responses.Count -ne 1) { throw "Intune relationship batch returned no unique response for '$($page.AppId)'." }
                $response = $responses[0]
                $status = [int]$response.status
                if ($status -ne 200) {
                    $errorObject = Get-EwObjectPropertyValue -Object (Get-EwObjectPropertyValue -Object $response -Name 'body') -Name 'error'
                    $message = [string](Get-EwObjectPropertyValue -Object $errorObject -Name 'message' -Default 'No error detail returned')
                    if ($status -notin @(429, 503, 504) -or $attempt -eq 3) {
                        throw "Intune relationships for '$($page.AppId)' failed (HTTP $status, attempt $attempt): $message"
                    }
                    $headers = Get-EwObjectPropertyValue -Object $response -Name 'headers'
                    $delay = [string](Get-EwObjectPropertyValue -Object $headers -Name 'Retry-After' -Default '2')
                    $seconds = 0
                    if (-not [int]::TryParse($delay, [ref]$seconds) -or $seconds -lt 0) { $seconds = 2 }
                    if ($seconds -gt 30) { throw "Intune relationships were throttled. Retry comparison after $seconds seconds." }
                    $wait = [Math]::Max($wait, $seconds)
                    $failed.Add($request)
                    Write-Verbose -Message "EvergreenUI: Intune relationship attempt $attempt failed for '$($page.AppId)' (HTTP $status): $message"
                    continue
                }
                $responseBody = $response.body
                if ($null -eq $responseBody -or $null -eq $responseBody.PSObject.Properties['value']) {
                    throw "Intune relationships for '$($page.AppId)' returned an invalid page."
                }
                foreach ($relationship in @($responseBody.value)) {
                    if ([string](Get-EwObjectPropertyValue -Object $relationship -Name '@odata.type') -eq '#microsoft.graph.mobileAppSupersedence' -and
                        [string](Get-EwObjectPropertyValue -Object $relationship -Name 'targetType') -eq 'parent') {
                        $target = [string](Get-EwObjectPropertyValue -Object $relationship -Name 'targetId')
                        if ($target) { $targets[$page.AppId].Add($target) }
                    }
                }
                $nextLink = [string](Get-EwObjectPropertyValue -Object $responseBody -Name '@odata.nextLink')
                if ($nextLink) {
                    if ($nextLink.StartsWith('https://graph.microsoft.com/beta/', [StringComparison]::OrdinalIgnoreCase)) {
                        $nextLink = $nextLink.Substring('https://graph.microsoft.com/beta'.Length)
                    }
                    elseif (-not $nextLink.StartsWith('/deviceAppManagement/', [StringComparison]::OrdinalIgnoreCase)) {
                        throw "Intune relationships returned an unexpected next-page URL for '$($page.AppId)'."
                    }
                    $pending.Enqueue([PSCustomObject]@{ AppId = $page.AppId; Url = $nextLink })
                }
                else { $completed++ }
            }
            if ($failed.Count -eq 0) { break }
            $retry = @($failed)
            Start-Sleep -Seconds $wait
        }
        Write-Progress -Activity 'Reading Intune supersedence relationships' -Status "$completed of $($App.Count) apps" -PercentComplete ([int](100 * $completed / [Math]::Max(1, $App.Count)))
    }
    Write-Progress -Activity 'Reading Intune supersedence relationships' -Completed
    $targets
}
