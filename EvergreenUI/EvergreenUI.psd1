#Requires -Version 5.1
@{
    # Module identity
    ModuleVersion     = '1.0.0'
    GUID              = 'e63b3f34-4e6c-433d-8544-fe497c21ad98'
    Author            = 'Aaron Parker'
    CompanyName       = 'EUC Pilots'
    Copyright         = '(c) 2026 EUC Pilots. Licensed under the MIT Licence.'
    Description       = 'WPF graphical frontend for the Evergreen PowerShell module. Provides a Windows-only GUI for Find-EvergreenApp, Get-EvergreenApp, Save-EvergreenApp, and Evergreen library management cmdlets.'

    # Compatibility
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Root module
    RootModule        = 'EvergreenUI.psm1'

    # Exports - only Start-EvergreenUI is public
    FunctionsToExport = @('Start-EvergreenUI')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Dependencies
    RequiredModules   = @(
        @{ ModuleName = 'Evergreen'; ModuleVersion = '2603.2832.0' }
    )

    # Module metadata
    PrivateData = @{
        PSData = @{
            Tags         = @('Evergreen', 'GUI', 'WPF', 'EUC', 'EvergreenUI', 'Windows')
            LicenseUri   = 'https://github.com/EUCPilots/evergreen-ui/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/EUCPilots/evergreen-ui'
            ReleaseNotes = 'Initial pre-release scaffold. Mostly working except for Downloads.'
            Prerelease   = 'beta'
        }
    }
}
