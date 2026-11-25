#Requires -Version 7.6
@{
    # Module identity
    ModuleVersion     = '2.0.1'
    GUID              = 'e63b3f34-4e6c-433d-8544-fe497c21ad98'
    Author            = 'Aaron Parker (stealthpuppy)'
    CompanyName       = 'EUC Pilots'
    Copyright         = '(c) 2026 EUC Pilots. Licensed under the MIT Licence.'
    Description       = 'EvergreenUI and the Evergreen Workbench is WPF graphical frontend for the Evergreen PowerShell module. Provides a Windows-only GUI for Find-EvergreenApp, Get-EvergreenApp, Save-EvergreenApp, and Evergreen library management cmdlets. The Evergreen Workbench also supports packaging apps for Microsoft Intune and Nerdio Manager Shell Apps, and installing apps locally using Evergreen.'

    # Compatibility
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    # Root module
    RootModule        = 'EvergreenUI.psm1'

    # Export only implemented commands
    FunctionsToExport = @(
        'Get-EwSetting', 'Set-EwSetting', 'Reset-EwSetting',
        'Start-EwJob', 'Get-EwJob', 'Stop-EwJob', 'Remove-EwJob',
        'Get-EwApp', 'Get-EwFilterableProperty', 'Save-EwArtifact',
        'Get-EwLibrary', 'Update-EwLibrary', 'Remove-EwLibraryApp',
        'Get-EwDefinition', 'Resolve-EwArtifact', 'Update-EwDefinition',
        'Test-EwDetection', 'Install-EwPackage', 'New-EwPackage',
        'Connect-EwIntune', 'Disconnect-EwIntune', 'Connect-EwNerdio', 'Disconnect-EwNerdio',
        'Publish-EwIntuneApp', 'Publish-EwIntuneBatch', 'Publish-EwNerdioApp', 'Publish-EwNerdioBatch', 'Set-EwIntuneSupersedence',
        'Add-EwFavouriteApp', 'Remove-EwFavouriteApp',
        'Get-EwDependency', 'Update-EwEvergreen', 'Clear-EwCache',
        'Get-EwM365Configuration', 'Get-EwM365BuildPlan', 'Get-EwM365NerdioPublishPlan', 'Publish-EwM365NerdioApp',
        'Get-EwM365IntunePublishPlan', 'Publish-EwM365IntuneApp', 'Get-EwM365IntuneRecovery', 'Clear-EwM365IntuneRecovery',
        'Get-EwIntuneApp', 'Compare-EwIntuneApp',
        'Connect-EwAzure', 'Disconnect-EwAzure', 'Get-EwAzureResourceGroup',
        'Get-EwAzureStorageAccount', 'Get-EwAzureStorageContainer',
        'Get-EwNerdioDefinition', 'Get-EwNerdioShellApp', 'Get-EwNerdioShellAppVersion',
        'Compare-EwNerdioShellApp', 'Get-EwNerdioPublishPlan', 'Get-EwNerdioShellAppVersionPrunePlan',
        'Remove-EwNerdioShellAppVersion',
        'Start-EvergreenWorkbench'
    )
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
            Prerelease   = 'preview'
            ExternalModuleDependencies = @('IntuneWin32App', 'Microsoft.Graph.Authentication', 'Az.Accounts', 'Az.Resources', 'Az.Storage')
        }
    }
}
