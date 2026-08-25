#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Get-InstallPackageLatestVersion cache' -Tag 'Unit' {
    BeforeEach {
        $global:installCacheRoot = Join-Path -Path $env:TEMP -ChildPath "EvergreenUI_LatestCache_$(Get-Random)"
        $global:installDefinition = [PSCustomObject]@{ Application = [PSCustomObject]@{ Filter = 'Get-EvergreenApp' } }
        $global:installLiveResult = [PSCustomObject]@{
            Succeeded        = $true
            Version          = '1.2.3'
            URI              = 'https://example.test/app.exe'
            ResolvedArtifact = [PSCustomObject]@{ Version = '1.2.3' }
            FilterExpression = 'Get-EvergreenApp'
            Error            = ''
        }
    }

    AfterEach {
        Remove-Item -Path $global:installCacheRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'uses a fresh cache hit without querying live' {
        InModuleScope EvergreenUI {
            Mock Get-IntunePackageLatestVersion { throw 'live lookup should not run' }
            New-Item -Path $global:installCacheRoot -ItemType Directory -Force | Out-Null
            $cacheFile = Join-Path -Path $global:installCacheRoot -ChildPath 'install-latest-cache.json'
            [PSCustomObject]@{
                DefinitionPath   = 'c:\defs\app.json'
                RetrievedUtc     = [DateTime]::UtcNow.ToString('o')
                Succeeded        = $true
                Version          = '9.9.9'
                URI              = 'https://example.test/cached.exe'
                ResolvedArtifact = $null
                FilterExpression = 'Get-EvergreenApp'
                Error            = ''
            } | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8

            $result = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\App.json' -DefinitionObject $global:installDefinition -CacheRootPath $global:installCacheRoot

            $result.IsFromCache | Should -BeTrue
            $result.Version | Should -Be '9.9.9'
            Should -Invoke Get-IntunePackageLatestVersion -Times 0 -Exactly
        }
    }

    It 'refreshes a stale cache entry' {
        InModuleScope EvergreenUI {
            Mock Get-IntunePackageLatestVersion {
                [PSCustomObject]@{ Succeeded = $true; Version = '1.2.3'; URI = 'https://example.test/app.exe'; ResolvedArtifact = $null; FilterExpression = 'Get-EvergreenApp'; Error = '' }
            }
            New-Item -Path $global:installCacheRoot -ItemType Directory -Force | Out-Null
            $cacheFile = Join-Path -Path $global:installCacheRoot -ChildPath 'install-latest-cache.json'
            [PSCustomObject]@{
                DefinitionPath = 'c:\defs\app.json'
                RetrievedUtc = [DateTime]::UtcNow.AddHours(-48).ToString('o')
                Succeeded = $true
                Version = '1.0.0'
            } | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8

            $result = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\App.json' -DefinitionObject $global:installDefinition -CacheRootPath $global:installCacheRoot

            $result.IsFromCache | Should -BeFalse
            $result.Version | Should -Be '1.2.3'
            Should -Invoke Get-IntunePackageLatestVersion -Times 1 -Exactly
        }
    }

    It 'treats malformed cache content as a live lookup' {
        InModuleScope EvergreenUI {
            Mock Get-IntunePackageLatestVersion {
                [PSCustomObject]@{ Succeeded = $true; Version = '1.2.3'; URI = 'https://example.test/app.exe'; ResolvedArtifact = $null; FilterExpression = 'Get-EvergreenApp'; Error = '' }
            }
            New-Item -Path $global:installCacheRoot -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $global:installCacheRoot 'install-latest-cache.json') -Value '{invalid' -Encoding UTF8

            $result = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\App.json' -DefinitionObject $global:installDefinition -CacheRootPath $global:installCacheRoot

            $result.Succeeded | Should -BeTrue
            $result.Version | Should -Be '1.2.3'
            Should -Invoke Get-IntunePackageLatestVersion -Times 1 -Exactly
        }
    }

    It 'removes duplicate definition keys when saving a batch state' {
        InModuleScope EvergreenUI {
            Mock Get-IntunePackageLatestVersion { $global:installLiveResult }
            New-Item -Path $global:installCacheRoot -ItemType Directory -Force | Out-Null
            $cacheFile = Join-Path -Path $global:installCacheRoot -ChildPath 'install-latest-cache.json'
            @(
                [PSCustomObject]@{ DefinitionPath = 'c:\defs\app.json'; RetrievedUtc = [DateTime]::UtcNow.AddHours(-48).ToString('o'); Version = '1.0.0' }
                [PSCustomObject]@{ DefinitionPath = 'C:\Defs\App.json'; RetrievedUtc = [DateTime]::UtcNow.AddHours(-48).ToString('o'); Version = '1.1.0' }
            ) | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
            $state = Initialize-InstallLatestCache -CacheFile $cacheFile

            $null = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\App.json' -DefinitionObject $global:installDefinition -CacheRootPath $global:installCacheRoot -CacheState $state
            $null = Save-InstallLatestCache -CacheState $state
            $saved = @(Get-Content -Path $cacheFile -Raw | ConvertFrom-Json)

            @($saved | Where-Object { $_.DefinitionPath -eq 'c:\defs\app.json' }) | Should -HaveCount 1
        }
    }

    It 'keeps partial live failures in the batch cache without stopping' {
        InModuleScope EvergreenUI {
            $secondDefinition = [PSCustomObject]@{ Application = [PSCustomObject]@{ Filter = 'Get-EvergreenApp' } }
            $global:installCacheCallCount = 0
            Mock Get-IntunePackageLatestVersion {
                $global:installCacheCallCount++
                if ($global:installCacheCallCount -eq 1) {
                    [PSCustomObject]@{ Succeeded = $true; Version = '1.2.3'; URI = 'https://example.test/app.exe'; ResolvedArtifact = $null; FilterExpression = 'Get-EvergreenApp'; Error = '' }
                }
                else {
                    [PSCustomObject]@{ Succeeded = $false; Version = ''; URI = ''; ResolvedArtifact = $null; FilterExpression = ''; Error = 'not found' }
                }
            }
            New-Item -Path $global:installCacheRoot -ItemType Directory -Force | Out-Null
            $state = Initialize-InstallLatestCache -CacheFile (Join-Path $global:installCacheRoot 'install-latest-cache.json')

            $first = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\One.json' -DefinitionObject $global:installDefinition -CacheRootPath $global:installCacheRoot -CacheState $state
            $second = Get-InstallPackageLatestVersion -DefinitionPath 'C:\Defs\Two.json' -DefinitionObject $secondDefinition -CacheRootPath $global:installCacheRoot -CacheState $state
            $null = Save-InstallLatestCache -CacheState $state

            $first.Succeeded | Should -BeTrue
            $second.Succeeded | Should -BeFalse
            $state.Entries | Should -HaveCount 2
            Should -Invoke Get-IntunePackageLatestVersion -Times 2 -Exactly
        }
    }
}
