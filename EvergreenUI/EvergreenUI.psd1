#Requires -Version 5.1
@{
    # Module identity
    ModuleVersion     = '2.0.0'
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

    )

    # Module metadata
    PrivateData = @{
        PSData = @{
            Tags         = @('Evergreen', 'GUI', 'MSI', 'MSIX', 'Windows', 'Intune', 'Nerdio', 'M365')
            LicenseUri   = 'https://github.com/EUCPilots/evergreen-ui/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/EUCPilots/evergreen-ui'
            ReleaseNotes = ''
            Prerelease   = ''
        }
    }
}
