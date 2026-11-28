Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-EwM365ConfigurationSummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [xml]$Configuration
    )

    $productNames = @{
        O365ProPlusRetail = 'Microsoft 365 Apps for enterprise'
        O365ProPlusEEANoTeamsRetail = 'Microsoft 365 Apps for enterprise (no Teams)'
        O365BusinessRetail = 'Microsoft 365 Apps for business'
        O365BusinessEEANoTeamsRetail = 'Microsoft 365 Apps for business (no Teams)'
        VisioProRetail = 'Visio Professional'
        VisioStdRetail = 'Visio Standard'
        ProjectProRetail = 'Project Professional'
        ProjectStdRetail = 'Project Standard'
        AccessRuntimeRetail = 'Access Runtime'
        LanguagePack = 'Language Pack'
        ProofingTools = 'Proofing Tools'
    }
    $appNames = [ordered]@{
        Word = 'Word'
        Excel = 'Excel'
        PowerPoint = 'PowerPoint'
        Outlook = 'Outlook (classic)'
        OutlookForWindows = 'Outlook (new)'
        OneNote = 'OneNote'
        OneDrive = 'OneDrive'
        Teams = 'Teams'
        Access = 'Access'
        Publisher = 'Publisher'
        Lync = 'Skype for Business'
        Groove = 'OneDrive for Business (Groove)'
        Bing = 'Microsoft Search in Bing'
    }
    $suiteApps = @('Word', 'Excel', 'PowerPoint', 'Outlook', 'OutlookForWindows', 'OneNote', 'OneDrive', 'Teams', 'Access', 'Publisher', 'Lync')
    $languageNames = @{
        MatchOS = 'Match the Windows display language'
        MatchInstalled = 'Match languages already installed'
        MatchPreviousMSI = 'Match languages from the removed MSI Office'
    }
    $getProperty = {
        param([string]$Name)
        $node = $Configuration.SelectSingleNode("/Configuration/Property[@Name='$Name']")
        if ($null -eq $node) { return '' }
        return $node.GetAttribute('Value')
    }

    $addNode = $Configuration.SelectSingleNode('/Configuration/Add')
    $products = if ($null -ne $addNode) { @($addNode.SelectNodes('Product')) } else { @() }
    $primary = $products | Where-Object { $_.GetAttribute('ID') -like 'O365*' } | Select-Object -First 1
    if ($null -eq $primary) { $primary = $products | Select-Object -First 1 }
    $primaryId = if ($null -ne $primary) { $primary.GetAttribute('ID') } else { '' }
    $productName = {
        param([string]$Id)
        if ($productNames.ContainsKey($Id)) { return $productNames[$Id] }
        return $Id
    }

    $excludedIds = @(if ($null -ne $primary) {
            foreach ($exclude in @($primary.SelectNodes('ExcludeApp'))) {
                $id = $exclude.GetAttribute('ID')
                if (-not [string]::IsNullOrWhiteSpace($id)) { $id }
            }
        })
    $includedApps = @(if ($primaryId -like 'O365*') {
            foreach ($id in $suiteApps) {
                if ($id -eq 'Teams' -and $primaryId -like '*NoTeams*') { continue }
                if ($excludedIds -notcontains $id) { $appNames[$id] }
            }
        })
    $excludedApps = @(foreach ($id in $excludedIds) {
            if ($appNames.Contains($id)) { $appNames[$id] } else { $id }
        })
    $additionalProducts = @(foreach ($product in $products) {
            if (-not [object]::ReferenceEquals($product, $primary)) { & $productName $product.GetAttribute('ID') }
        })

    $languages = [System.Collections.Generic.List[string]]::new()
    foreach ($language in @($products | ForEach-Object { @($_.SelectNodes('Language')) })) {
        $id = $language.GetAttribute('ID')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $name = if ($languageNames.ContainsKey($id)) {
            $languageNames[$id]
        }
        else {
            try { "$([System.Globalization.CultureInfo]::GetCultureInfo($id).DisplayName) ($id)" }
            catch {
                Write-Verbose -Message "EvergreenUI: Microsoft 365 language '$id' is not a known culture: $($_.Exception.Message)"
                $id
            }
        }
        if (-not $languages.Contains($name)) { $languages.Add($name) }
    }

    $edition = if ($null -ne $addNode) { $addNode.GetAttribute('OfficeClientEdition') } else { '' }
    $architecture = if ($edition -eq '32') { '32-bit' } else { '64-bit' }
    $sharedLicensing = (& $getProperty 'SharedComputerLicensing') -eq '1'
    $deviceLicensing = (& $getProperty 'DeviceBasedLicensing') -eq '1'
    $licensing = if ($sharedLicensing) { 'Shared computer activation' }
    elseif ($deviceLicensing) { 'Device-based licensing' }
    else { 'User-based licensing' }
    $updatesNode = $Configuration.SelectSingleNode('/Configuration/Updates')
    $displayNode = $Configuration.SelectSingleNode('/Configuration/Display')
    $companyNode = $Configuration.SelectSingleNode("/Configuration/AppSettings/Setup[@Name='Company']")
    $description = ''
    $infoNode = $Configuration.SelectSingleNode('/Configuration/Info')
    if ($null -ne $infoNode) {
        $description = if ($infoNode.HasAttribute('Description')) { $infoNode.GetAttribute('Description') }
        else {
            $descriptionNode = $infoNode.SelectSingleNode('Description')
            if ($null -ne $descriptionNode) { $descriptionNode.InnerText } else { '' }
        }
    }
    Write-Verbose -Message "EvergreenUI: Microsoft 365 configuration summary for '$primaryId' includes $($includedApps.Count) apps and excludes $($excludedApps.Count)"

    [PSCustomObject]@{
        PrimaryProductId = $primaryId
        PrimaryProduct = if ([string]::IsNullOrWhiteSpace($primaryId)) { '' } else { & $productName $primaryId }
        Description = $description
        IncludedApps = [string[]]$includedApps
        ExcludedApps = [string[]]$excludedApps
        AdditionalProducts = [string[]]$additionalProducts
        Channel = if ($null -ne $addNode) { $addNode.GetAttribute('Channel') } else { '' }
        Architecture = $architecture
        MigrateArchitecture = $null -ne $addNode -and $addNode.GetAttribute('MigrateArch') -eq 'TRUE'
        Languages = [string[]]$languages
        Licensing = $licensing
        IsVdi = $sharedLicensing
        DeviceBasedLicensing = $deviceLicensing
        TenantId = & $getProperty 'TenantId'
        CompanyName = if ($null -ne $companyNode) { $companyNode.GetAttribute('Value') } else { '' }
        RemoveMsi = $null -ne $Configuration.SelectSingleNode('/Configuration/RemoveMSI')
        UpdatesEnabled = $null -eq $updatesNode -or $updatesNode.GetAttribute('Enabled') -ne 'FALSE'
        ForceAppShutdown = (& $getProperty 'FORCEAPPSHUTDOWN') -eq 'TRUE'
        DisplayLevel = if ($null -ne $displayNode -and $displayNode.HasAttribute('Level')) { $displayNode.GetAttribute('Level') } else { 'Full' }
        AcceptEula = $null -ne $displayNode -and $displayNode.GetAttribute('AcceptEULA') -eq 'TRUE'
        UserSettingCount = @($Configuration.SelectNodes('/Configuration/AppSettings/User')).Count
    }
}
