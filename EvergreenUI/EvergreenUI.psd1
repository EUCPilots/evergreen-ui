#Requires -Version 5.1
@{
    # Module identity
    ModuleVersion     = '1.0.22'
    GUID              = 'e63b3f34-4e6c-433d-8544-fe497c21ad98'
    Author            = 'Aaron Parker (stealthpuppy)'
    CompanyName       = 'EUC Pilots'
    Copyright         = '(c) 2026 EUC Pilots. Licensed under the MIT Licence.'
    Description       = 'EvergreenUI and the Evergreen Workbench is WPF graphical frontend for the Evergreen PowerShell module. Provides a Windows-only GUI for Find-EvergreenApp, Get-EvergreenApp, Save-EvergreenApp, and Evergreen library management cmdlets. The Evergreen Workbench also supports packaging apps for Microsoft Intune and Nerdio Manager Shell Apps, and installing apps locally using Evergreen.'

    # Compatibility
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Root module
    RootModule        = 'EvergreenUI.psm1'

    # Exports - only Start-EvergreenWorkbench is public
    FunctionsToExport = @('Start-EvergreenWorkbench')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Dependencies
    RequiredModules   = @(
        @{ ModuleName = 'Evergreen'; ModuleVersion = '2603.2832.0' }
    )

    # All files shipped with the module
    FileList = @(
        'EvergreenUI.psd1'
        'EvergreenUI.psm1'
        'en-US\EvergreenUI-help.xml'
        'Resources\EvergreenUI.xaml'
        'Resources\NerdioShellApps.psm1'
        'Resources\m365-app.json'
        'Resources\evergreenbulb.png'
        'Public\Start-EvergreenWorkbench.ps1'
        'Private\Format-LogEntry.ps1'
        'Private\Get-EvergreenAppList.ps1'
        'Private\Get-FilterableProperties.ps1'
        'Private\Get-InstallPackageDefinitions.ps1'
        'Private\Get-InstallPackageLatestVersion.ps1'
        'Private\Get-IntunePackageLatestVersion.ps1'
        'Private\Get-M365AppConfigurations.ps1'
        'Private\Get-SafeFolderName.ps1'
        'Private\Get-UIConfig.ps1'
        'Private\Invoke-AppDownload.ps1'
        'Private\Invoke-AzureSignIn.ps1'
        'Private\Invoke-FilterUpdate.ps1'
        'Private\Invoke-IntuneDefinitionUpdate.ps1'
        'Private\Invoke-IntuneGraphWin32Import.ps1'
        'Private\Invoke-IntunePackageBuild.ps1'
        'Private\Invoke-LibraryUpdate.ps1'
        'Private\Invoke-LocalPackageInstall.ps1'
        'Private\Invoke-M365AppPackageBuild.ps1'
        'Private\Invoke-M365AppShellAppBuild.ps1'
        'Private\Merge-ConfigSection.ps1'
        'Private\New-FilterPanel.ps1'
        'Private\New-WpfRunspace.ps1'
        'Private\Set-DwmTitleBarColor.ps1'
        'Private\Set-IntuneGraphWin32Supersedence.ps1'
        'Private\Set-UIConfig.ps1'
        'Private\Test-EvergreenModule.ps1'
        'Private\Test-LocalPackageDetection.ps1'
        'Private\Write-UILog.ps1'
        'Private\Write-UpdateOutput.ps1'
        'Private\themes\Set-DarkTheme.ps1'
        'Private\themes\Set-LightTheme.ps1'
    )

    # Module metadata
    PrivateData = @{
        PSData = @{
            Tags         = @('Evergreen', 'GUI', 'MSI', 'EvergreenUI', 'Windows')
            LicenseUri   = 'https://github.com/EUCPilots/evergreen-ui/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/EUCPilots/evergreen-ui'
            ReleaseNotes = 'Pre-release. Updates Intune Win32 package support including x64 and arm64 architectures.'
            Prerelease   = 'beta'
        }
    }
}
