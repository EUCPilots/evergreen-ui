#Requires -Version 5.1
@{
    # Module identity
    ModuleVersion     = '0.1.0'
    GUID              = 'a3f8c2d1-4b7e-4f9a-8c3d-1e2f5a6b7c8d'
    Author            = 'EUC Pilots'
    CompanyName       = ''
    Copyright         = '(c) 2026 EUC Pilots. Licensed under the MIT Licence.'
    Description       = 'WPF graphical frontend for the Evergreen PowerShell module. Provides a Windows-only GUI for Find-EvergreenApp, Get-EvergreenApp, Save-EvergreenApp, and Evergreen library management cmdlets.'

    # Compatibility
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Root module
    RootModule        = 'EvergreenUI.psm1'

    # Exports — only Start-EvergreenUI is public
    FunctionsToExport = @('Start-EvergreenUI')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Dependencies
    RequiredModules   = @(
        @{ ModuleName = 'Evergreen'; ModuleVersion = '2603.2832.0' }
    )

    RequiredAssemblies = @(
        'PresentationFramework'
        'PresentationCore'
        'WindowsBase'
        'System.Windows.Forms'
    )

    # Module metadata
    PrivateData = @{
        PSData = @{
            Tags         = @('Evergreen', 'GUI', 'WPF', 'EUC', 'EvergreenUI', 'Windows')
            LicenseUri   = 'https://github.com/your-org/EvergreenUI/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/your-org/EvergreenUI'
            ReleaseNotes = 'Initial pre-release scaffold. No functional UI yet.'
        }
    }
}
