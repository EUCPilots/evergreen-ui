#Requires -Version 5.1

Describe 'Module manifest' -Tag 'Unit' {
    BeforeAll {
        $script:manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1'
    }

    It 'Has a valid module manifest' {
        { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Exports the public workbench and prerequisite commands' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        $manifest.FunctionsToExport | Should -Be @('Start-EvergreenWorkbench', 'Test-EvergreenUIPrerequisite')
    }

    It 'Declares only Evergreen as a required module' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        @($manifest.RequiredModules).ModuleName | Should -Be @('Evergreen')
    }

    It 'Lists optional feature dependencies in manifest metadata' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        @($manifest.PrivateData.OptionalModules).Name | Should -Be @(
            'Microsoft.Graph.Authentication', 'IntuneWin32App', 'Az.Accounts', 'Az.Resources', 'Az.Storage'
        )
    }

    It 'Loads the package-filter dependency before the latest-version resolver in isolated runspaces' {
        $workbenchPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Public\Start-EvergreenWorkbench.ps1'
        $workbenchContent = Get-Content -LiteralPath $workbenchPath -Raw -ErrorAction Stop
        $resolverCount = ([regex]::Matches($workbenchContent, "'Get-IntunePackageLatestVersion\.ps1'")).Count
        $orderedDependencyCount = ([regex]::Matches(
                $workbenchContent,
                "'Invoke-PackageFilter\.ps1'\s*\r?\n\s*'Get-IntunePackageLatestVersion\.ps1'"
            )).Count

        $resolverCount | Should -BeGreaterThan 0
        $orderedDependencyCount | Should -Be $resolverCount
    }
}