#Requires -Version 5.1

BeforeAll {
    $script:xamlPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Resources\EvergreenUI.xaml'
    $script:workbenchPath = Join-Path -Path $PSScriptRoot -ChildPath '..\EvergreenUI\Public\Start-EvergreenWorkbench.ps1'
}

Describe 'EvergreenUI XAML' -Tag 'Unit' {
    It 'Loads on an STA thread and contains every control requested by FindName' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $workbenchContent = Get-Content -LiteralPath $script:workbenchPath -Raw -ErrorAction Stop
        $requestedNames = @(
            [regex]::Matches($workbenchContent, "\.FindName\('([^']+)'\)") |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        )

        $runspace = [RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = [Threading.ApartmentState]::STA
        $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseCurrentThread
        $pipeline = [PowerShell]::Create()
        $pipeline.Runspace = $runspace

        try {
            $runspace.Open()
            $null = $pipeline.AddScript({
                param($Path, $Names)

                Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
                $stream = $null
                try {
                    $stream = [IO.File]::OpenRead((Resolve-Path -Path $Path).Path)
                    $window = [System.Windows.Markup.XamlReader]::Load($stream)
                }
                finally {
                    if ($null -ne $stream) {
                        $stream.Dispose()
                    }
                }

                $missingNames = @($Names | Where-Object { $null -eq $window.FindName($_) })
                [PSCustomObject]@{
                    MissingNames = $missingNames
                    LoadedType   = $window.GetType().FullName
                }
            }).AddParameters(@{
                Path  = $script:xamlPath
                Names = $requestedNames
            })

            $result = @($pipeline.Invoke())
            $pipeline.HadErrors | Should -BeFalse -Because ($pipeline.Streams.Error -join [Environment]::NewLine)
            $result | Should -HaveCount 1
            $result[0].LoadedType | Should -Be 'System.Windows.Window'
            @($result[0].MissingNames) | Should -HaveCount 0
        }
        finally {
            $pipeline.Dispose()
            $runspace.Dispose()
        }
    }

    It 'Exposes accessible names for status dots and progress indicators' {
        $xamlContent = Get-Content -LiteralPath $script:xamlPath -Raw -ErrorAction Stop

        $requiredControls = @(
            'DownloadProgressBar',
            'LibraryUpdateProgressBar',
            'IntuneDefinitionsProgressBar',
            'IntuneImportProgressBar',
            'NerdioShellAppsProgressBar',
            'M365ConfigsProgressBar',
            'InstallProgressBar',
            'NerdioImportAuthStatusDot',
            'NerdioAzureAuthStatusDot',
            'M365IntuneAuthStatusDot',
            'M365NerdioAuthStatusDot',
            'InstallElevationStatusDot'
        )

        foreach ($controlName in $requiredControls) {
            $namedPattern = [regex]::Escape("x:Name=`"$controlName`"")
            ($xamlContent -match $namedPattern) | Should -BeTrue -Because "the control $controlName should exist in the XAML resource"

            $accessibilityPattern = [regex]::Escape("x:Name=`"$controlName`"") + '(?s).*?AutomationProperties.Name="[^"]+"'
            ($xamlContent -match $accessibilityPattern) | Should -BeTrue -Because "the control $controlName should have an accessible name"
        }
    }
}
