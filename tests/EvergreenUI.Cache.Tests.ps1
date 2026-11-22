#Requires -Version 7.6

BeforeAll {
    # Load the root directly so Evergreen's dependency initializer cannot use
    # the network. Every vendor-query seam used by these tests is replaced.
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psm1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    $cacheTestRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath ('.cache-tests-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $cacheTestRoot -ItemType Directory -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $cacheTestRoot -Recurse -Force -ErrorAction Stop
}

Describe 'Workbench cache path' {
    It 'resolves the unchanged default and canonical explicit paths without creating directories' {
        InModuleScope EvergreenUI -Parameters @{ Root = $cacheTestRoot } {
            $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
            if (-not $local) {
                $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
            }
            Get-EwCachePath | Should -Be (Join-Path -Path $local -ChildPath 'EvergreenWorkbench\Cache')
            $path = Join-Path -Path $Root -ChildPath 'absent'
            Get-EwCachePath -CachePath "$path\..\absent\" | Should -Be $path
            Test-Path -LiteralPath $path | Should -BeFalse
            $target = Join-Path -Path $Root -ChildPath 'target'
            $junction = Join-Path -Path $Root -ChildPath 'junction'
            $null = New-Item -Path $target -ItemType Directory -ErrorAction Stop
            $null = New-Item -Path $junction -ItemType Junction -Target $target -ErrorAction Stop
            Get-EwCachePath -CachePath "$junction\missing" | Should -Be "$target\missing"
        }
    }
}

Describe 'Workbench cache invalidation' {
    BeforeEach {
        $caseRoot = Join-Path -Path $cacheTestRoot -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $caseRoot -ItemType Directory -ErrorAction Stop
        $script:cache = Join-Path -Path $caseRoot -ChildPath 'custom'
        $defaultCache = Join-Path -Path $caseRoot -ChildPath 'default'
        $catalogEpoch = Join-Path -Path $caseRoot -ChildPath 'catalog-cache-epoch.json'
        $definition = Join-Path -Path $caseRoot -ChildPath 'App.json'
        @{ Application = @{ Filter = 'Get-EvergreenApp -Name "Example"' } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $definition -ErrorAction Stop
        InModuleScope EvergreenUI -Parameters @{ Default = $defaultCache; Catalog = $catalogEpoch } {
            $script:testDefaultCache = $Default
            $script:testCatalogEpoch = $Catalog
            $script:ewAppCatalogCache = @{ RetrievedAt = $null; Items = @() }
            Mock Get-EwCatalogEpochPath { $script:testCatalogEpoch }
            Mock Get-EwCachePath {
                if ([string]::IsNullOrWhiteSpace($CachePath)) { return $script:testDefaultCache }
                return [System.IO.Path]::GetFullPath($CachePath).TrimEnd('\')
            }
            Mock Get-EwSetting { [PSCustomObject]@{ FavouriteApps = @() } }
            Mock Invoke-EwDefinitionQuery { [PSCustomObject]@{ Version = '1.0'; URI = 'https://example.test/setup.exe' } }
        }
    }

    It 'clears default and explicit payloads only and preserves unrelated data and coordination records' {
        InModuleScope EvergreenUI -Parameters @{ Default = $defaultCache; Cache = $cache; Definition = $definition } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $unrelated = Join-Path -Path $Default -ChildPath 'settings.json'
            Set-Content -LiteralPath $unrelated -Value 'keep' -ErrorAction Stop
            $customPayload = Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json'
            $result = Clear-EwCache -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.CatalogInvalidated | Should -BeTrue
            $result.DefinitionCacheInvalidated | Should -BeTrue
            $result.DefinitionCacheRemoved | Should -BeTrue
            $result.RemovedEntryCount | Should -Be 1
            $result.RemovedFiles | Should -Be @(Join-Path -Path $Default -ChildPath 'definition-artifact-cache.json')
            $unrelated | Should -Exist
            $customPayload | Should -Exist
            $epochFile = Join-Path -Path $Default -ChildPath 'definition-cache-epoch.json'
            $epochFile | Should -Exist
            $oldEpoch = Get-Content -LiteralPath $epochFile -Raw
            $result = Clear-EwCache -CachePath $Cache -Confirm:$false
            $result.RemovedFiles | Should -Be @($customPayload)
            Get-Content -LiteralPath $epochFile -Raw | Should -Be $oldEpoch
            (Join-Path -Path $Cache -ChildPath 'definition-cache-epoch.json') | Should -Exist
        }
    }

    It 'WhatIf does not write payloads, markers, or directories or invalidate memory' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Catalog = $catalogEpoch } {
            Mock Invoke-EwAppCatalogQuery { [PSCustomObject]@{ Name = 'Original' } }
            Clear-EwCache -CachePath $Cache -WhatIf | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Cache | Should -BeFalse
            Test-Path -LiteralPath $Catalog | Should -BeFalse
            $null = Get-EwApp
            $before = Get-Content -LiteralPath $Catalog -Raw
            Clear-EwCache -CachePath $Cache -WhatIf | Should -BeNullOrEmpty
            Get-Content -LiteralPath $Catalog -Raw | Should -Be $before
            (Get-EwApp).Name | Should -Be 'Original'
            Should -Invoke Invoke-EwAppCatalogQuery -Exactly 1
        }
    }

    It 'reports payload deletion failure separately after successful invalidation and refuses stale legacy data' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $payload = Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json'
            $handle = [System.IO.File]::Open($payload, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $result = Clear-EwCache -CachePath $Cache -Confirm:$false
                $result.Succeeded | Should -BeFalse
                $result.CatalogInvalidated | Should -BeTrue
                $result.DefinitionCacheInvalidated | Should -BeTrue
                $result.DefinitionCacheRemoved | Should -BeFalse
                $result.RemovedFiles.Count | Should -Be 0
                $result.Changed | Should -BeTrue
                $result.Errors.Count | Should -Be 1
                $result.Error | Should -Match 'payload deletion failed'
                $next = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
                $next.IsFromCache | Should -BeFalse
                Should -Invoke Invoke-EwDefinitionQuery -Exactly 2
            }
            finally { $handle.Dispose() }
        }
    }

    It 'reports catalog invalidation failure while still clearing the targeted definition cache' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            Mock Invoke-EwCatalogCache { throw 'catalog denied' } -ParameterFilter { $Action -eq 'Clear' }
            $result = Clear-EwCache -CachePath $Cache -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.CatalogInvalidated | Should -BeFalse
            $result.DefinitionCacheInvalidated | Should -BeTrue
            $result.DefinitionCacheRemoved | Should -BeTrue
            $result.RemovedEntryCount | Should -Be 1
            $result.Errors | Should -HaveCount 1
        }
    }

    It 'reports definition invalidation failure independently from successful payload deletion' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $epochFile = Join-Path -Path $Cache -ChildPath 'definition-cache-epoch.json'
            Remove-Item -LiteralPath $epochFile -ErrorAction Stop
            $null = New-Item -Path $epochFile -ItemType Directory -ErrorAction Stop
            $result = Clear-EwCache -CachePath $Cache -Confirm:$false
            $result.Succeeded | Should -BeFalse
            $result.CatalogInvalidated | Should -BeTrue
            $result.DefinitionCacheInvalidated | Should -BeFalse
            $result.DefinitionCacheRemoved | Should -BeTrue
            $result.RemovedEntryCount | Should -Be 1
            $result.Error | Should -Match 'Definition invalidation failed'
            @(Get-ChildItem -LiteralPath $epochFile -Force) | Should -HaveCount 0
        }
    }

    It 'does not recache an in-flight definition or catalog result after clear' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $script:inFlightCache = $Cache
            Mock Invoke-EwDefinitionQuery {
                $null = Clear-EwCache -CachePath $script:inFlightCache -Confirm:$false
                [PSCustomObject]@{ Version = '1.0'; URI = 'https://example.test/setup.exe' }
            }
            $result = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $result.Succeeded | Should -BeTrue
            Test-Path -LiteralPath $result.CacheFile | Should -BeFalse
            Mock Invoke-EwAppCatalogQuery {
                $null = Clear-EwCache -CachePath $script:inFlightCache -Confirm:$false
                [PSCustomObject]@{ Name = 'Original' }
            }
            (Get-EwApp).Name | Should -Be 'Original'
            $script:ewAppCatalogCache.RetrievedAt | Should -BeNullOrEmpty
        }
    }

    It 'NoCache skips every coordinated definition cache read and write' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $null = Clear-EwCache -CachePath $Cache -Confirm:$false
            $epochFile = Join-Path -Path $Cache -ChildPath 'definition-cache-epoch.json'
            $epoch = Get-Content -LiteralPath $epochFile -Raw
            Mock Invoke-EwDefinitionCache { throw 'NoCache must not access store' }
            (Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache -NoCache).Succeeded | Should -BeTrue
            Should -Invoke Invoke-EwDefinitionCache -Exactly 0
            Get-Content -LiteralPath $epochFile -Raw | Should -Be $epoch
            Test-Path -LiteralPath (Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json') | Should -BeFalse
        }
    }

    It 'missing or corrupt coordination records cannot resurrect invalidated payloads or stale writers' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition; Catalog = $catalogEpoch } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $epochFile = Join-Path -Path $Cache -ChildPath 'definition-cache-epoch.json'
            $old = Invoke-EwDefinitionCache -Action Read -CachePath $Cache
            $null = Clear-EwCache -CachePath $Cache -Confirm:$false
            Remove-Item -LiteralPath $epochFile -ErrorAction Stop
            $next = Invoke-EwDefinitionCache -Action Read -CachePath $Cache
            $next.Epoch | Should -Not -Be $old.Epoch
            Invoke-EwDefinitionCache -Action Write -CachePath $Cache -Epoch $old.Epoch -Entry $old.Entries[0]
            Test-Path -LiteralPath (Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json') | Should -BeFalse
            Write-EwJsonFile -Path (Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json') -InputObject $old.Entries
            (Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache).IsFromCache | Should -BeFalse
            Set-Content -LiteralPath $epochFile -Value 'corrupt' -ErrorAction Stop
            $payload = Get-Content -LiteralPath (Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json') -Raw
            (Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache).IsFromCache | Should -BeFalse
            Get-Content -LiteralPath (Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json') -Raw | Should -Be $payload
            Get-Content -LiteralPath $epochFile | Should -Be 'corrupt'
            Mock Invoke-EwAppCatalogQuery { [PSCustomObject]@{ Name = 'Live' } }
            $null = Get-EwApp
            $oldCatalogEpoch = $script:ewAppCatalogCache.Epoch
            Remove-Item -LiteralPath $Catalog -ErrorAction Stop
            $null = Get-EwApp
            $script:ewAppCatalogCache.Epoch | Should -Not -Be $oldCatalogEpoch
            Set-Content -LiteralPath $Catalog -Value 'corrupt' -ErrorAction Stop
            (Get-EwApp).Name | Should -Be 'Live'
            Should -Invoke Invoke-EwAppCatalogQuery -Exactly 3
        }
    }

    It 'merges concurrent same-key writes without dropping unrelated definition entries' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition } {
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
        }
        $ready = [System.Threading.CountdownEvent]::new(6)
        $resume = [System.Threading.ManualResetEventSlim]::new($false)
        $workers = [System.Collections.Generic.List[object]]::new()
        try {
            foreach ($index in @(0, 1, 0, 1, 2, 3)) {
                $path = Join-Path -Path $caseRoot -ChildPath "App$index.json"
                Copy-Item -LiteralPath $definition -Destination $path -Force -ErrorAction Stop
                $worker = [PowerShell]::Create()
                $null = $worker.AddScript({
                    param($Module, $Cache, $Definition, $Ready, $Resume)
                    Import-Module -Name $Module -ErrorAction Stop
                    & (Get-Module -Name EvergreenUI) {
                        param($ReadyEvent, $ResumeEvent)
                        $script:readyEvent = $ReadyEvent
                        $script:resumeEvent = $ResumeEvent
                        function script:Invoke-EwDefinitionQuery {
                            $null = $script:readyEvent.Signal()
                            if (-not $script:resumeEvent.Wait(15000)) { throw 'Resume timed out' }
                            [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.exe' }
                        }
                    } $Ready $Resume
                    Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
                }).AddArgument($modulePath).AddArgument($cache).AddArgument($path).AddArgument($ready).AddArgument($resume)
                $workers.Add(@{ Worker = $worker; Handle = $worker.BeginInvoke() })
            }
            $ready.Wait(15000) | Should -BeTrue
            $resume.Set()
            foreach ($item in $workers) {
                $item.Worker.EndInvoke($item.Handle).Succeeded | Should -BeTrue
                $item.Worker.Streams.Error | Should -HaveCount 0
            }
            $entries = @(Get-Content -LiteralPath (Join-Path -Path $cache -ChildPath 'definition-artifact-cache.json') -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop)
            $entries | Should -HaveCount 5
            @($entries.DefinitionPath | Select-Object -Unique) | Should -HaveCount 5
            @($entries | Where-Object { $_.DefinitionPath -eq $definition }) | Should -HaveCount 1
        }
        finally {
            $resume.Set()
            foreach ($item in $workers) { $item.Worker.Dispose() }
            $ready.Dispose()
            $resume.Dispose()
        }
    }

    It 'Update refreshes Evergreen and resets only the local catalog without touching persistent caches or generations' {
        InModuleScope EvergreenUI -Parameters @{ Cache = $cache; Definition = $definition; Catalog = $catalogEpoch } {
            $null = Clear-EwCache -CachePath $Cache -Confirm:$false
            $null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
            $epochFile = Join-Path -Path $Cache -ChildPath 'definition-cache-epoch.json'
            $payload = Join-Path -Path $Cache -ChildPath 'definition-artifact-cache.json'
            $before = @($Catalog, $epochFile, $payload | ForEach-Object { Get-Content -LiteralPath $_ -Raw })
            Mock Invoke-EwAppCatalogQuery { [PSCustomObject]@{ Name = 'Original' } }
            Mock Invoke-EwEvergreenUpdate {}
            $null = Get-EwApp
            $result = Update-EwEvergreen -Confirm:$false
            $result.Succeeded | Should -BeTrue
            $result.PSObject.Properties.Name | Should -Be @('Succeeded', 'Error')
            $script:ewAppCatalogCache.RetrievedAt | Should -BeNullOrEmpty
            $script:ewAppCatalogCache.Items.Count | Should -Be 0
            @($Catalog, $epochFile, $payload | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) | Should -Be $before
            (Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache).IsFromCache | Should -BeTrue
            $null = Get-EwApp
            Should -Invoke Invoke-EwAppCatalogQuery -Exactly 2
            Should -Invoke Invoke-EwEvergreenUpdate -Exactly 1
        }
    }

    It 'invalidates a cached catalog in a distinct runspace module instance' {
        $worker = [PowerShell]::Create()
        try {
            $null = $worker.AddScript({
                param($Module, $Catalog)
                Import-Module -Name $Module -ErrorAction Stop
                & (Get-Module -Name EvergreenUI) {
                    param($CatalogPath)
                    $script:testEpoch = $CatalogPath
                    $script:queryCount = 0
                    function script:Get-EwCatalogEpochPath { $script:testEpoch }
                    function script:Get-EwSetting { [PSCustomObject]@{ FavouriteApps = @() } }
                    function script:Invoke-EwAppCatalogQuery {
                        $script:queryCount++
                        [PSCustomObject]@{ Name = "Query$script:queryCount" }
                    }
                } $Catalog
                (Get-EwApp).Name
                (Get-EwApp).Name
            }).AddArgument($modulePath).AddArgument($catalogEpoch)
            @($worker.Invoke()) | Should -Be @('Query1', 'Query1')
            $worker.Streams.Error | Should -HaveCount 0
            InModuleScope EvergreenUI -Parameters @{ Cache = $cache } {
                (Clear-EwCache -CachePath $Cache -Confirm:$false).Succeeded | Should -BeTrue
            }
            $worker.Commands.Clear()
            $null = $worker.AddScript({ (Get-EwApp).Name })
            @($worker.Invoke()) | Should -Be @('Query2')
        }
        finally { $worker.Dispose() }
    }

    It 'coordinates invalidation with a separate pwsh process sharing catalogs and definition caches' {
        $ready = Join-Path -Path $caseRoot -ChildPath 'ready'
        $resume = Join-Path -Path $caseRoot -ChildPath 'resume'
        $lookupReady = Join-Path -Path $caseRoot -ChildPath 'lookup-ready'
        $lookupResume = Join-Path -Path $caseRoot -ChildPath 'lookup-resume'
        $output = Join-Path -Path $caseRoot -ChildPath 'result.json'
        $workerFile = Join-Path -Path $caseRoot -ChildPath 'worker.ps1'
        @'
param($Module, $Catalog, $Cache, $Definition, $Ready, $Resume, $Output, $LookupReady, $LookupResume)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module -Name $Module -ErrorAction Stop
& (Get-Module -Name EvergreenUI) {
    param($CatalogPath, $ReadyPath, $ResumePath)
    $script:testEpoch = $CatalogPath
    $script:lookupReady = $ReadyPath
    $script:lookupResume = $ResumePath
    $script:lookupCount = 0
    $script:queryCount = 0
    function script:Get-EwCatalogEpochPath { $script:testEpoch }
    function script:Get-EwSetting { [PSCustomObject]@{ FavouriteApps = @() } }
    function script:Invoke-EwAppCatalogQuery {
        $script:queryCount++
        [PSCustomObject]@{ Name = "Query$script:queryCount" }
    }
    function script:Invoke-EwDefinitionQuery {
        $script:lookupCount++
        if ($script:lookupCount -eq 2) {
            [System.IO.File]::WriteAllText($script:lookupReady, 'ready')
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (-not (Test-Path -LiteralPath $script:lookupResume)) {
                if ([DateTime]::UtcNow -gt $deadline) { throw 'Lookup resume timed out' }
                Start-Sleep -Milliseconds 25
            }
        }
        [PSCustomObject]@{ Version = '1.0'; URI = 'https://example.test/setup.exe' }
    }
} $Catalog $LookupReady $LookupResume
$first = (Get-EwApp).Name
$null = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
[System.IO.File]::WriteAllText($Ready, 'ready')
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while (-not (Test-Path -LiteralPath $Resume)) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Resume timed out' }
    Start-Sleep -Milliseconds 25
}
$second = (Get-EwApp).Name
$artifact = Resolve-EwArtifact -DefinitionPath $Definition -CachePath $Cache
@{ First = $first; Second = $second; FromCache = $artifact.IsFromCache } |
    ConvertTo-Json | Set-Content -LiteralPath $Output -ErrorAction Stop
'@ | Set-Content -LiteralPath $workerFile -ErrorAction Stop
        $arguments = @('-NoProfile', '-NonInteractive', '-File', $workerFile, $modulePath, $catalogEpoch, $cache, $definition, $ready, $resume, $output, $lookupReady, $lookupResume)
        $processInfo = [System.Diagnostics.ProcessStartInfo]::new((Get-Command -Name pwsh -ErrorAction Stop).Source)
        $processInfo.UseShellExecute = $false
        foreach ($argument in $arguments) { $processInfo.ArgumentList.Add($argument) }
        $process = [System.Diagnostics.Process]::Start($processInfo)
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (-not (Test-Path -LiteralPath $ready)) {
                if ($process.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Worker did not become ready' }
                Start-Sleep -Milliseconds 25
            }
            InModuleScope EvergreenUI -Parameters @{ Cache = $cache } {
                (Clear-EwCache -CachePath $Cache -Confirm:$false).Succeeded | Should -BeTrue
            }
            Set-Content -LiteralPath $resume -Value 'resume' -ErrorAction Stop
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (-not (Test-Path -LiteralPath $lookupReady)) {
                if ($process.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Lookup did not become ready' }
                Start-Sleep -Milliseconds 25
            }
            InModuleScope EvergreenUI -Parameters @{ Cache = $cache } {
                (Clear-EwCache -CachePath $Cache -Confirm:$false).Succeeded | Should -BeTrue
            }
            Set-Content -LiteralPath $lookupResume -Value 'resume' -ErrorAction Stop
            $process.WaitForExit(30000) | Should -BeTrue
            $process.ExitCode | Should -Be 0
            $result = Get-Content -LiteralPath $output -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $result.First | Should -Be 'Query1'
            $result.Second | Should -Be 'Query2'
            $result.FromCache | Should -BeFalse
            Test-Path -LiteralPath (Join-Path -Path $cache -ChildPath 'definition-artifact-cache.json') | Should -BeFalse
        }
        finally {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
            $process.Dispose()
        }
    }
}
