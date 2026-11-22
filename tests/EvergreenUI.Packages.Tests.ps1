#Requires -Version 7.6

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\EvergreenUI.psd1') -Force -ErrorAction Stop
    function New-TestM365ShellApp {
        param([string]$Root)
        $shellPath = Join-Path -Path $Root -ChildPath 'shell-app'
        $null = New-Item -Path $shellPath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $shellPath -ChildPath 'Definition.json') -Value '{"versions":[{"name":"old","file":{"sourceUrl":"","sha256":""}}]}'
        foreach ($name in 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
            Set-Content -LiteralPath (Join-Path -Path $shellPath -ChildPath $name) -Value 'Write-Output ok'
        }
    }
}

AfterAll {
    Remove-Module -Name EvergreenUI -ErrorAction SilentlyContinue
}

Describe 'Evergreen package builds' {
    BeforeEach {
        $script:packageRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $definitionDirectory = Join-Path -Path $packageRoot -ChildPath 'Example'
        New-Item -Path $definitionDirectory -ItemType Directory -Force | Out-Null
        $script:packageDefinition = Join-Path -Path $definitionDirectory -ChildPath 'App.json'
        [PSCustomObject]@{
            Application = [PSCustomObject]@{ Name = 'Example'; Filter = 'Get-EvergreenApp -Name "ExampleApp"' }
            PackageInformation = [PSCustomObject]@{ SetupFile = 'old.exe'; Version = '1.0' }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $packageDefinition
    }

    It 'resolves a valid latest Office channel version and rejects invalid metadata' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion {
                [PSCustomObject]@{ Channel = 'Current'; Version = 'unknown' }
                [PSCustomObject]@{ Channel = 'Current'; Version = '16.0.100.1' }
                [PSCustomObject]@{ Channel = 'Current'; Version = '16.0.200.1' }
                [PSCustomObject]@{ Channel = 'Other'; Version = '99.0.1.1' }
            }
            (Get-EwM365SetupArtifact -Channel Current).Version | Should -Be '16.0.200.1'
            Mock Get-EwAppVersion { [PSCustomObject]@{ Channel = 'Current'; Version = 'unknown' } }
            { Get-EwM365SetupArtifact -Channel Current } | Should -Throw '*no valid*'
        }
    }

    It 'resolves the newest valid deployment tool without accepting HTTP sources' {
        InModuleScope EvergreenUI {
            Mock Get-EwAppVersion {
                [PSCustomObject]@{ Version = '16.0.10.1'; URI = 'https://example.test/odt.exe' }
                [PSCustomObject]@{ Version = '16.0.20.1'; URI = 'http://example.test/odt.exe' }
                [PSCustomObject]@{ Version = 'invalid'; URI = 'https://example.test/odt.exe' }
            }
            (Get-EwM365DeploymentArtifact).Version | Should -Be '16.0.10.1'
        }
    }

    It 'extracts a signed deployment archive without launching its executable' {
        $payload = Join-Path -Path $packageRoot -ChildPath 'payload'
        $null = New-Item -Path $payload -ItemType Directory
        Set-Content -LiteralPath (Join-Path -Path $payload -ChildPath 'setup.exe') -Value 'fixture'
        $archive = Join-Path -Path $packageRoot -ChildPath 'odt.zip'
        Compress-Archive -Path (Join-Path -Path $payload -ChildPath 'setup.exe') -DestinationPath $archive
        $destination = Join-Path -Path $packageRoot -ChildPath 'extract with spaces'
        InModuleScope EvergreenUI -Parameters @{ Archive = $archive; Destination = $destination } {
            Mock Get-Item { [PSCustomObject]@{ FullName = $Archive; VersionInfo = @{ FileVersion = '16.0.10.1' } } }
            Mock Get-AuthenticodeSignature {
                $certificate = [PSCustomObject]@{}
                $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { 'Microsoft Corporation' }
                [PSCustomObject]@{ Status = 'Valid'; SignerCertificate = $certificate }
            }
            Mock Start-Process { throw 'The elevation-requiring executable must not be launched.' }
            $setup = Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination -ExpectedVersion '16.0.10.1'
            (Get-Content -LiteralPath $setup -Raw).Trim() | Should -Be 'fixture'
            Should -Invoke Start-Process -Exactly 0
        }
    }

    It 'checks deployment tool version and Microsoft signature before extraction' {
        $payload = Join-Path -Path $packageRoot -ChildPath 'payload'
        $null = New-Item -Path $payload -ItemType Directory
        Set-Content -LiteralPath (Join-Path -Path $payload -ChildPath 'setup.exe') -Value 'fixture'
        $archive = Join-Path -Path $packageRoot -ChildPath 'odt.zip'
        Compress-Archive -Path (Join-Path -Path $payload -ChildPath 'setup.exe') -DestinationPath $archive
        $destination = Join-Path -Path $packageRoot -ChildPath 'extract'
        InModuleScope EvergreenUI -Parameters @{ Archive = $archive; Destination = $destination } {
            Mock Get-Item {
                [PSCustomObject]@{ FullName = $Archive; VersionInfo = @{ FileVersion = '16.0.10.1' } }
            }
            Mock Get-AuthenticodeSignature {
                $certificate = [PSCustomObject]@{}
                $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { 'Microsoft Corporation' }
                [PSCustomObject]@{ Status = 'Valid'; SignerCertificate = $certificate }
            }
            Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination `
                -ExpectedVersion '16.0.10.1' | Should -Be (Join-Path -Path $Destination -ChildPath 'setup.exe')
            Should -Invoke Get-AuthenticodeSignature -Exactly 2
            { Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination `
                    -ExpectedVersion '16.0.20.1' } | Should -Throw '*does not match*'
            Mock Get-AuthenticodeSignature { [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
            { Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination `
                    -ExpectedVersion '16.0.10.1' } | Should -Throw '*valid Microsoft signature*'
        }
    }

    It 'rejects extraction failures and an unsigned setup executable' {
        $archive = Join-Path -Path $packageRoot -ChildPath 'invalid.zip'
        Set-Content -LiteralPath $archive -Value 'not an archive'
        $destination = Join-Path -Path $packageRoot -ChildPath 'extract'
        InModuleScope EvergreenUI -Parameters @{ Archive = $archive; Destination = $destination } {
            Mock Get-Item {
                [PSCustomObject]@{ FullName = $Archive; VersionInfo = @{ FileVersion = '16.0.10.1' } }
            }
            Mock Get-AuthenticodeSignature {
                $certificate = [PSCustomObject]@{}
                $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { 'Microsoft Corporation' }
                [PSCustomObject]@{ Status = 'Valid'; SignerCertificate = $certificate }
            }
            { Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination `
                    -ExpectedVersion '16.0.10.1' } | Should -Throw '*extraction failed*'
        }

        $payload = Join-Path -Path $packageRoot -ChildPath 'payload'
        $null = New-Item -Path $payload -ItemType Directory
        Set-Content -LiteralPath (Join-Path -Path $payload -ChildPath 'setup.exe') -Value 'fixture'
        $validArchive = Join-Path -Path $packageRoot -ChildPath 'valid.zip'
        Compress-Archive -Path (Join-Path -Path $payload -ChildPath 'setup.exe') -DestinationPath $validArchive
        $destination = Join-Path -Path $packageRoot -ChildPath 'extract-valid'
        InModuleScope EvergreenUI -Parameters @{ Archive = $validArchive; Destination = $destination } {
            Mock Get-Item { [PSCustomObject]@{ FullName = $Archive; VersionInfo = @{ FileVersion = '16.0.10.1' } } }
            Mock Get-AuthenticodeSignature {
                if ($FilePath -ne $Archive) { return [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
                $certificate = [PSCustomObject]@{}
                $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { 'Microsoft Corporation' }
                [PSCustomObject]@{ Status = 'Valid'; SignerCertificate = $certificate }
            }
            { Expand-EwM365DeploymentTool -Path $Archive -Destination $Destination `
                    -ExpectedVersion '16.0.10.1' } | Should -Throw '*setup.exe does not have a valid Microsoft signature*'
        }
    }

    It 'blocks a confirmed build when the configuration or resolved tool changes' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        $original = '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        Set-Content -LiteralPath $xmlPath -Value $original
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant'; Account = 'user@example.test' } }
            Mock Get-EwM365SetupArtifact { [PSCustomObject]@{ Version = '16.0.1234.1'; URI = 'https://example.test/office' } }
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt' } }
            Mock Invoke-EwArtifactSave { throw 'Download must not start.' }
            $parameters = @{
                ConfigurationPath = $ConfigurationPath; Provider = 'Intune'; Channel = 'Current'
                CompanyName = 'Contoso'; ImportFor = 'Single session'; TenantId = 'tenant'
            }
            $plan = Get-EwM365BuildPlan @parameters
            Add-Content -LiteralPath $ConfigurationPath -Value '<!-- changed -->'
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Intune -Channel Current -CompanyName Contoso -ImportFor 'Single session' `
                -TenantId tenant -M365Plan $plan
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'ConfigurationHash'
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
        Set-Content -LiteralPath $xmlPath -Value $original
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant'; Account = 'user@example.test' } }
            Mock Get-EwM365SetupArtifact { [PSCustomObject]@{ Version = '16.0.1234.1'; URI = 'https://example.test/office' } }
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt' } }
            $plan = Get-EwM365BuildPlan -ConfigurationPath $ConfigurationPath -Provider Intune `
                -Channel Current -CompanyName Contoso -ImportFor 'Single session' -TenantId tenant
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.2'; URI = 'https://example.test/odt' } }
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*ToolVersion*'
        }
    }

    It 'rejects changed template, tool URI and Graph session after preview' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        $template = Join-Path -Path $packageRoot -ChildPath 'template.json'
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Resources\m365-app.json') -Destination $template
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; Template = $template } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant'; Account = 'first@example.test' } }
            Mock Get-EwM365SetupArtifact { [PSCustomObject]@{ Version = '16.0.1234.1'; URI = 'https://example.test/office' } }
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt' } }
            $parameters = @{
                ConfigurationPath = $ConfigurationPath; Provider = 'Intune'; Channel = 'Current'
                CompanyName = 'Contoso'; ImportFor = 'Single session'; TenantId = 'tenant'; AppJsonTemplatePath = $Template
            }
            $plan = Get-EwM365BuildPlan @parameters
            Add-Content -LiteralPath $Template -Value ' '
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*TemplateHash*'
            $plan = Get-EwM365BuildPlan @parameters
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/changed' } }
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*ToolURI*'
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt' } }
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'tenant'; Account = 'second@example.test' } }
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*SessionIdentity*'
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'other'; Account = 'first@example.test' } }
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*tenant*'
        }
    }

    It 'previews a Nerdio API-only session and rejects changed scripts or uninstall XML' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        $uninstall = Join-Path -Path $packageRoot -ChildPath 'Uninstall-Microsoft365Apps.xml'
        $shellPath = Join-Path -Path $packageRoot -ChildPath 'shell-app'
        New-Item -Path $shellPath -ItemType Directory | Out-Null
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        Set-Content -LiteralPath $uninstall -Value '<Configuration><Remove All="TRUE" /></Configuration>'
        Set-Content -LiteralPath (Join-Path -Path $shellPath -ChildPath 'Definition.json') -Value '{"versions":[{"name":"old","file":{"sourceUrl":"","sha256":""}}]}'
        foreach ($name in 'Detect.ps1', 'Install.ps1', 'Uninstall.ps1') {
            Set-Content -LiteralPath (Join-Path -Path $shellPath -ChildPath $name) -Value 'Write-Output ok'
        }
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; Uninstall = $uninstall; ShellPath = $shellPath } {
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{ TenantId = 'tenant'; SessionId = 'session'; NmeHost = 'example.test'; ApiOnly = $true }
            }
            Mock Get-EwM365SetupArtifact { [PSCustomObject]@{ Version = '16.0.1234.1'; URI = 'https://example.test/office' } }
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt' } }
            $parameters = @{
                ConfigurationPath = $ConfigurationPath; Provider = 'Nerdio'; Channel = 'Current'
                CompanyName = 'Contoso'; ImportFor = 'Single session'; TenantId = 'tenant'
            }
            $plan = Get-EwM365BuildPlan @parameters
            $plan.SessionIdentity | Should -Be 'session|example.test'
            Add-Content -LiteralPath (Join-Path -Path $ShellPath -ChildPath 'Detect.ps1') -Value '# change'
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*ShellHash*'
            $plan = Get-EwM365BuildPlan @parameters
            Set-Content -LiteralPath $Uninstall -Value '<Configuration><Add /></Configuration>'
            { Assert-EwM365BuildPlan -Plan $plan } | Should -Throw '*Configuration.Remove*'
        }
    }

    It 'rejects configurations without a valid ID before resolving or downloading' -ForEach @(
        @{ ConfigId = '' }
        @{ ConfigId = 'invalid' }
        @{ ConfigId = '00000000-0000-0000-0000-000000000000' }
    ) {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        Set-Content -LiteralPath $xmlPath -Value "<Configuration ID='$ConfigId'><Add Channel='Current' OfficeClientEdition='64'><Product ID='O365ProPlusRetail' /></Add></Configuration>"
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Get-EwM365SetupArtifact { throw 'Unexpected version lookup.' }
            Mock Invoke-EwArtifactSave { throw 'Unexpected download.' }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Nerdio -Channel Current -CompanyName Contoso -ImportFor 'Single session' -TenantId 'tenant-id'
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'valid, non-empty configuration ID'
            Should -Invoke Get-EwM365SetupArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
    }

    It 'requires a matching provider session even when no build preview is supplied' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Assert-EwModule {}
            Mock Get-MgContext { [PSCustomObject]@{ TenantId = 'another-tenant'; Account = 'user@example.test' } }
            Mock Invoke-EwArtifactSave { throw 'Download must not start.' }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Intune -Channel Current -CompanyName Contoso -ImportFor 'Single session' -TenantId tenant
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'tenant'
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
        }
    }

    It 'builds an Intune package using the optional package builder' {
        $workingPath = Join-Path -Path $packageRoot -ChildPath 'BuildOutput'
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $workingPath } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                Get-Item -LiteralPath $path
            }
            Mock Invoke-EwIntunePackageBuilder {
                $package = Join-Path -Path $OutputFolder -ChildPath 'Example.intunewin'
                Set-Content -LiteralPath $package -Value 'package'
                $package
            }
            $result = New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath
            $result.Succeeded | Should -BeTrue -Because $result.Error
            $result.SetupFile | Should -Be 'setup.exe'
            $result.Version | Should -Be '2.0'
            Test-Path -LiteralPath $result.PackagePath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install.ps1') -PathType Leaf | Should -BeTrue
            Should -Invoke Invoke-EwIntunePackageBuilder -Exactly 1 -ParameterFilter {
                $SetupFile -eq 'setup.exe' -and $SourceFolder -like '*\Example\Source'
            }
        }
    }

    It 'does not add the shared installer to PSADT packages' {
        $definitionSource = Join-Path -Path (Split-Path -Path $packageDefinition -Parent) -ChildPath 'Source'
        New-Item -Path $definitionSource -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $definitionSource -ChildPath 'Invoke-AppDeployToolkit.ps1') -Value 'param()'
        $workingPath = Join-Path -Path $packageRoot -ChildPath 'BuildOutput'
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $workingPath } {
            Mock Resolve-EwArtifact {
                [PSCustomObject]@{
                    Succeeded = $true
                    Version = '2.0'
                    ResolvedArtifact = [PSCustomObject]@{ Version = '2.0'; URI = 'https://example.test/setup.exe' }
                    Error = ''
                }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                Get-Item -LiteralPath $path
            }
            Mock Invoke-EwIntunePackageBuilder {
                $package = Join-Path -Path $OutputFolder -ChildPath 'Example.intunewin'
                Set-Content -LiteralPath $package -Value 'package'
                $package
            }
            $result = New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath
            $result.Succeeded | Should -BeTrue -Because $result.Error
            Test-Path -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install.ps1') -PathType Leaf | Should -BeFalse
        }
    }

    It 'does not resolve or create a package when WhatIf is specified' {
        InModuleScope EvergreenUI -Parameters @{ DefinitionPath = $packageDefinition; WorkingPath = $packageRoot } {
            Mock Resolve-EwArtifact {}
            Mock Invoke-EwArtifactSave {}
            Mock Invoke-EwIntunePackageBuilder {}
            New-EwPackage -DefinitionPath $DefinitionPath -WorkingPath $WorkingPath -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Resolve-EwArtifact -Exactly 0
            Should -Invoke Invoke-EwArtifactSave -Exactly 0
            Should -Invoke Invoke-EwIntunePackageBuilder -Exactly 0
        }
    }

    It 'builds a Nerdio zip with updated ODT settings' {
        $configurationRoot = Join-Path -Path $packageRoot -ChildPath 'M365'
        New-Item -Path $configurationRoot -ItemType Directory -Force | Out-Null
        $xmlPath = Join-Path -Path $configurationRoot -ChildPath 'Install.xml'
        $uninstallPath = Join-Path -Path $configurationRoot -ChildPath 'Uninstall-Microsoft365Apps.xml'
        $templatePath = Join-Path -Path $configurationRoot -ChildPath 'template.json'
        $template = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Resources\m365-app.json') -Raw | ConvertFrom-Json
        ($template.DetectionRule | Where-Object ValueName -eq VersionToReport).Operator = 'equal'
        $template | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $templatePath
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Old" OfficeClientEdition="64"><Product ID="O365ProPlusRetail"><ExcludeApp ID="Bing" /></Product></Add><Property Name="TenantId" Value="old" /><Property Name="SharedComputerLicensing" Value="0" /><AppSettings><Setup Value="Old" /></AppSettings></Configuration>'
        Set-Content -LiteralPath $uninstallPath -Value '<Configuration><Remove All="TRUE" /></Configuration>'
        New-TestM365ShellApp -Root $configurationRoot
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; ConfigurationRoot = $configurationRoot; WorkingPath = $packageRoot; TemplatePath = $templatePath } {
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{ TenantId = 'tenant-id'; SessionId = 'session'; NmeHost = 'example.test'; ApiOnly = $true }
            }
            Mock Get-EwM365SetupArtifact {
                [PSCustomObject]@{ Channel = $Channel; Version = '16.0.1234.1'; URI = 'https://example.test/setup.exe' }
            }
            Mock Get-EwM365DeploymentArtifact {
                [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt.exe' }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'odt.exe'
                Set-Content -LiteralPath $path -Value 'tool'
                Get-Item -LiteralPath $path
            }
            Mock Expand-EwM365DeploymentTool {
                $null = New-Item -Path $Destination -ItemType Directory
                $path = Join-Path -Path $Destination -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                $path
            }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -ConfigurationRoot $ConfigurationRoot `
                -WorkingPath $WorkingPath -Provider Nerdio -Channel MonthlyEnterprise -CompanyName Contoso `
                -ImportFor 'Multi-session' -TenantId 'tenant-id' -AppJsonTemplatePath $TemplatePath
            $result.Succeeded | Should -BeTrue
            $result.Provider | Should -Be 'Nerdio'
            $result.Version | Should -Be '16.0.1234.1'
            $result.ToolVersion | Should -Be '16.0.5678.1'
            Should -Invoke Expand-EwM365DeploymentTool -Exactly 1 -ParameterFilter { $ExpectedVersion -eq '16.0.5678.1' }
            Test-Path -LiteralPath $result.PackagePath -PathType Leaf | Should -BeTrue
            [xml]$updated = Get-Content -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install-Microsoft365Apps.xml') -Raw
            $updated.Configuration.Add.Channel | Should -Be 'MonthlyEnterprise'
            ($updated.Configuration.Property | Where-Object Name -eq TenantId).Value | Should -Be 'tenant-id'
            ($updated.Configuration.Property | Where-Object Name -eq SharedComputerLicensing).Value | Should -Be '1'
            $updated.Configuration.AppSettings.Setup.Name | Should -Be 'Company'
            $updated.Configuration.AppSettings.Setup.Value | Should -Be 'Contoso'
            $appJson = Get-Content -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'App.json') -Raw | ConvertFrom-Json
            $appJson.Information.DisplayName | Should -Be 'Microsoft 365 Apps for enterprise: x64'
            ($appJson.DetectionRule | Where-Object ValueName -eq VersionToReport).Value | Should -Be '16.0.1234.1'
            ($appJson.DetectionRule | Where-Object ValueName -eq VersionToReport).Operator | Should -Be 'greaterThanOrEqual'
            $appJson.RequirementRule.Architecture | Should -Be 'x64'
            ($appJson.DetectionRule | Where-Object ValueName -eq ProductReleaseIds).Value | Should -Be 'O365ProPlusRetail'
            ($appJson.DetectionRule | Where-Object ValueName -eq SharedComputerLicensing).Value | Should -Be '1'
        }
    }

    It 'stages a rolling channel and shared licensing without changing the source XML' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        $original = '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Version="16.0.1.1" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add><Updates Channel="Old" TargetVersion="16.0.1.1" /></Configuration>'
        Set-Content -LiteralPath $xmlPath -Value $original
        Set-Content -LiteralPath (Join-Path -Path $packageRoot -ChildPath 'Uninstall-Microsoft365Apps.xml') -Value '<Configuration><Remove All="TRUE" /></Configuration>'
        New-TestM365ShellApp -Root $packageRoot
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{ TenantId = 'tenant-id'; SessionId = 'session'; NmeHost = 'example.test'; ApiOnly = $true }
            }
            Mock Get-EwM365SetupArtifact {
                [PSCustomObject]@{ Version = '16.0.1234.1'; URI = 'https://example.test/setup.exe' }
            }
            Mock Get-EwM365DeploymentArtifact {
                [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt.exe' }
            }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'odt.exe'
                Set-Content -LiteralPath $path -Value 'tool'
                Get-Item -LiteralPath $path
            }
            Mock Expand-EwM365DeploymentTool {
                $null = New-Item -Path $Destination -ItemType Directory
                $path = Join-Path -Path $Destination -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                $path
            }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Nerdio -Channel Current -CompanyName Contoso -ImportFor 'Multi-session' -TenantId 'tenant-id'
            $result.Succeeded | Should -BeTrue -Because $result.Error
            [xml]$staged = Get-Content -LiteralPath (Join-Path -Path $result.SourcePath -ChildPath 'Install-Microsoft365Apps.xml') -Raw
            $add = $staged.SelectSingleNode('/Configuration/Add')
            $add.GetAttribute('Channel') | Should -Be 'Current'
            $add.HasAttribute('Version') | Should -BeFalse
            $updates = $staged.SelectSingleNode('/Configuration/Updates')
            $updates.GetAttribute('Channel') | Should -Be 'Current'
            $updates.HasAttribute('TargetVersion') | Should -BeFalse
            $staged.SelectSingleNode("/Configuration/Property[@Name='SharedComputerLicensing']").GetAttribute('Value') | Should -Be '1'
            $staged.SelectSingleNode("/Configuration/Property[@Name='TenantId']").GetAttribute('Value') | Should -Be 'tenant-id'
            $staged.SelectSingleNode('/Configuration/AppSettings/Setup').GetAttribute('Name') | Should -Be 'Company'
            $staged.SelectSingleNode('/Configuration/AppSettings/Setup').GetAttribute('Value') | Should -Be 'Contoso'
        }
        (Get-Content -LiteralPath $xmlPath -Raw).Trim() | Should -Be $original
    }

    It 'rejects DownloadPath before resolving or changing build files' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" Version="16.0.1.1" DownloadPath="\\server\share" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Get-EwM365SetupArtifact { throw 'Unexpected version lookup.' }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Nerdio -Channel Current -CompanyName Contoso -ImportFor 'Single session' -TenantId 'tenant-id'
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'DownloadPath'
            Should -Invoke Get-EwM365SetupArtifact -Exactly 0
        }
    }

    It 'preserves an existing output package unless replacement was authorized' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        Set-Content -LiteralPath (Join-Path -Path $packageRoot -ChildPath 'Uninstall-Microsoft365Apps.xml') -Value '<Configuration><Remove All="TRUE" /></Configuration>'
        New-TestM365ShellApp -Root $packageRoot
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot } {
            Mock Get-EwNerdioSessionContext {
                [PSCustomObject]@{ TenantId = 'tenant-id'; SessionId = 'session'; NmeHost = 'example.test'; ApiOnly = $true }
            }
            Mock Get-EwM365SetupArtifact { [PSCustomObject]@{ Version = '16.0.1234.1' } }
            Mock Get-EwM365DeploymentArtifact { [PSCustomObject]@{ Version = '16.0.5678.1'; URI = 'https://example.test/odt.exe' } }
            Mock Invoke-EwArtifactSave {
                $path = Join-Path -Path $Path -ChildPath 'odt.exe'
                Set-Content -LiteralPath $path -Value 'tool'
                Get-Item -LiteralPath $path
            }
            Mock Expand-EwM365DeploymentTool {
                $null = New-Item -Path $Destination -ItemType Directory
                $path = Join-Path -Path $Destination -ChildPath 'setup.exe'
                Set-Content -LiteralPath $path -Value 'setup'
                $path
            }
            $parameters = @{
                M365ConfigurationPath = $ConfigurationPath; WorkingPath = $WorkingPath; Provider = 'Nerdio'
                Channel = 'Current'; CompanyName = 'Contoso'; ImportFor = 'Single session'; TenantId = 'tenant-id'
            }
            $first = New-EwPackage @parameters
            $first.Succeeded | Should -BeTrue -Because $first.Error
            Set-Content -LiteralPath $first.PackagePath -Value 'previous package'
            $second = New-EwPackage @parameters
            $second.Succeeded | Should -BeFalse
            $second.Error | Should -Match 'already exists'
            (Get-Content -LiteralPath $first.PackagePath -Raw).Trim() | Should -Be 'previous package'
            $third = New-EwPackage @parameters -Force
            $third.Succeeded | Should -BeTrue -Because $third.Error
            (Get-Content -LiteralPath $first.PackagePath -Raw) | Should -Not -Match 'previous package'
        }
    }

    It 'rejects an Intune template without Office version detection before downloading' {
        $xmlPath = Join-Path -Path $packageRoot -ChildPath 'Install.xml'
        $templatePath = Join-Path -Path $packageRoot -ChildPath 'template.json'
        Set-Content -LiteralPath $xmlPath -Value '<Configuration ID="9fddd581-f505-4760-9bb3-2365db204b38"><Add Channel="Current" OfficeClientEdition="64"><Product ID="O365ProPlusRetail" /></Add></Configuration>'
        Set-Content -LiteralPath $templatePath -Value '{"DetectionRule":[]}'
        InModuleScope EvergreenUI -Parameters @{ ConfigurationPath = $xmlPath; WorkingPath = $packageRoot; TemplatePath = $templatePath } {
            Mock Get-EwM365SetupArtifact { throw 'Unexpected version lookup.' }
            $result = New-EwPackage -M365ConfigurationPath $ConfigurationPath -WorkingPath $WorkingPath `
                -Provider Intune -Channel Current -CompanyName Contoso -ImportFor 'Single session' `
                -TenantId 'tenant-id' -AppJsonTemplatePath $TemplatePath
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -Match 'exactly one registry VersionToReport'
            Should -Invoke Get-EwM365SetupArtifact -Exactly 0
        }
    }
}
