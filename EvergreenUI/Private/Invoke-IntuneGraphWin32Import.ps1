#Requires -Version 5.1
<#
.SYNOPSIS
    Imports a Win32 app into Microsoft Intune via the Microsoft Graph API using
    the existing Connect-MgGraph session.

.DESCRIPTION
    Takes a parsed App.json definition, a .intunewin package, and the resolved
    version string, then performs the full Graph-based Win32 LobApp upload:

      1. Reads encryption metadata from the .intunewin zip (detection.xml)
      2. Creates the Win32 app metadata object via POST /mobileApps
      3. Creates a content version
      4. Creates a file entry and obtains the Azure Blob SAS upload URI
      5. Uploads the encrypted inner package (IntunePackage.intunewin) to
         Azure Blob Storage in 4 MB chunks
      6. Commits the file with encryption metadata
      7. Polls until the commit state is 'commitFileSuccess'
      8. Patches the app to set committedContentVersion

    All calls use Invoke-MgGraphRequest so the existing Connect-MgGraph session
    is the only auth dependency; Connect-MSIntuneGraph is never called.

.PARAMETER DefinitionObject
    Parsed App.json object.

.PARAMETER DefinitionPath
    Full path to App.json (used to build the Notes Date field and for logging).

.PARAMETER IntuneWinPath
    Full path to the .intunewin file produced by New-IntuneWin32AppPackage.

.PARAMETER SetupFilePath
    Setup file name used when the .intunewin package was built. When provided,
    this is used as win32LobApp.setupFilePath to avoid mismatches with
    PackageInformation.SetupFile in App.json.

.PARAMETER DownloadedVersion
    Version string of the installer that was packaged (may differ from the
    version recorded in App.json PackageInformation.Version).

.PARAMETER PSPackageFactoryGuid
    The PSPackageFactory GUID from App.json Information.PSPackageFactoryGuid.

.PARAMETER SyncHash
    The shared UI synchronised hashtable used by Write-UILog.

.OUTPUTS
    PSCustomObject with:
        Succeeded    : bool
        IntuneAppId  : string  - the newly created Intune app ID
        DisplayName  : string  - the display name used at import time
        Error        : string  - populated on failure
#>
function Invoke-IntuneGraphWin32Import {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$DefinitionObject,

        [Parameter(Mandatory)]
        [string]$IntuneWinPath,

        [Parameter()]
        [string]$SetupFilePath = '',

        [Parameter(Mandatory)]
        [string]$DownloadedVersion,

        [Parameter(Mandatory)]
        [string]$PSPackageFactoryGuid,

        [Parameter()]
        [string]$DefinitionPath = '',

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash
    )

    $fail = {
        param([string]$Msg)
        return [PSCustomObject]@{
            Succeeded   = $false
            IntuneAppId = ''
            DisplayName = ''
            Error       = $Msg
        }
    }

    # -- Validate prerequisites ------------------------------------------------
    if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
        return (& $fail 'Invoke-MgGraphRequest is not available. Ensure Microsoft.Graph.Authentication is imported and Connect-MgGraph has been called.')
    }

    $mgContext = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $mgContext) {
        return (& $fail 'No active Microsoft Graph context. Call Connect-MgGraph first.')
    }

    if (-not (Test-Path -LiteralPath $IntuneWinPath -PathType Leaf)) {
        return (& $fail "IntuneWin file not found: $IntuneWinPath")
    }

    # -- Parse encryption info from the .intunewin zip ------------------------
    Write-UILog -Message 'Parsing .intunewin package metadata...' -Level Info -SyncHash $SyncHash

    Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue

    $encKey             = ''
    $encMacKey          = ''
    $encIV              = ''
    $encMac             = ''
    $encFileDigest      = ''
    $encFileDigestAlg   = 'SHA256'
    $encProfileId       = 'ProfileVersion1'
    $unencryptedSize    = [long]0
    $encryptedSize      = [long]0
    $encryptedFilePath  = ''

    $zipEntry_package   = $null
    $zipEntry_detection = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.Name -ieq 'detection.xml')       { $zipEntry_detection = $entry }
                if ($entry.Name -ieq 'IntunePackage.intunewin') { $zipEntry_package = $entry }
            }

            if ($null -eq $zipEntry_detection) {
                return (& $fail 'detection.xml not found inside the .intunewin archive.')
            }
            if ($null -eq $zipEntry_package) {
                return (& $fail 'IntunePackage.intunewin not found inside the .intunewin archive.')
            }

            # Read detection.xml
            $detReader = [System.IO.StreamReader]::new($zipEntry_detection.Open())
            $detXml    = $detReader.ReadToEnd()
            $detReader.Close()
            [xml]$xmlDoc = $detXml
            $appInfo = $xmlDoc.ApplicationInfo
            $encInfo = $appInfo.EncryptionInfo

            $unencryptedSize  = [long]$appInfo.UnencryptedContentSize
            $encKey           = [string]$encInfo.EncryptionKey
            $encMacKey        = [string]$encInfo.MacKey
            $encIV            = [string]$encInfo.InitializationVector
            $encMac           = [string]$encInfo.Mac
            $encFileDigest    = [string]$encInfo.FileDigest
            $encFileDigestAlg = [string]$encInfo.FileDigestAlgorithm
            $encProfileId     = [string]$encInfo.ProfileIdentifier

            # Extract the encrypted inner package to a temp file
            $tempUploadFile  = Join-Path -Path $env:TEMP -ChildPath "IntuneUpload_$([System.Guid]::NewGuid().ToString('N')).intunewin"
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zipEntry_package, $tempUploadFile, $true)
            $encryptedFilePath = $tempUploadFile
            $encryptedSize = ([System.IO.FileInfo]::new($encryptedFilePath)).Length
        }
        finally {
            $zip.Dispose()
        }
    }
    catch {
        return (& $fail "Failed to parse .intunewin archive: $($_.Exception.Message)")
    }

    # -- Build Win32 app display name ------------------------------------------
    $baseDisplayName = [string]$DefinitionObject.Information.DisplayName
    if ([string]::IsNullOrWhiteSpace($baseDisplayName)) {
        $baseDisplayName = [string]$DefinitionObject.Application.Name
    }
    # Replace version placeholder: strip existing version and append current
    $displayName = "$baseDisplayName $DownloadedVersion" -replace '\s+\d[\d\.]+$', ''
    $displayName = "$baseDisplayName $DownloadedVersion"

    Write-UILog -Message "Creating Win32 app: '$displayName'..." -Level Info -SyncHash $SyncHash

    # -- Build detection rules -------------------------------------------------
    $detectionRules = @()
    if ($null -ne $DefinitionObject.DetectionRule) {
        foreach ($rule in $DefinitionObject.DetectionRule) {
            $ruleType = [string]$rule.Type
            switch ($ruleType) {
                'File' {
                    $detType = switch ([string]$rule.DetectionMethod) {
                        'Version'   { 'version' }
                        'Existence' { 'exists' }
                        'Size'      { 'sizeOrDateModified' }
                        'DateModified' { 'modifiedDate' }
                        default     { 'version' }
                    }
                    $graphRule = [ordered]@{
                        '@odata.type'       = '#microsoft.graph.win32LobAppFileSystemDetection'
                        'path'              = [string]$rule.Path
                        'fileOrFolderName'  = [string]$rule.FileOrFolder
                        'check32BitOn64System' = ([string]$rule.Check32BitOn64System -ieq 'true')
                        'detectionType'     = $detType
                    }
                    if ($detType -ne 'exists') {
                        $graphRule['operator']       = [string]$rule.Operator
                        $graphRule['detectionValue'] = [string]$rule.VersionValue
                    }
                    $detectionRules += $graphRule
                }
                'Registry' {
                    $detType = switch ([string]$rule.DetectionMethod) {
                        'Version'   { 'version' }
                        'Existence' { 'exists' }
                        'String'    { 'string' }
                        'Integer'   { 'integer' }
                        'Boolean'   { 'boolean' }
                        default     { 'string' }
                    }
                    $graphRule = [ordered]@{
                        '@odata.type'         = '#microsoft.graph.win32LobAppRegistryDetection'
                        'keyPath'             = [string]$rule.KeyPath
                        'valueName'           = [string]$rule.ValueName
                        'check32BitOn64System' = ([string]$rule.Check32BitOn64System -ieq 'true')
                        'detectionType'       = $detType
                    }
                    if ($detType -ne 'exists') {
                        $graphRule['operator']       = [string]$rule.Operator
                        $graphRule['detectionValue'] = [string]$rule.DetectionValue
                    }
                    $detectionRules += $graphRule
                }
                'MSI' {
                    $detectionRules += [ordered]@{
                        '@odata.type'             = '#microsoft.graph.win32LobAppProductCodeDetection'
                        'productCode'             = [string]$rule.ProductCode
                        'productVersionOperator'  = [string]$rule.ProductVersionOperator
                        'productVersion'          = [string]$rule.ProductVersion
                    }
                }
            }
        }
    }

    # Fallback: create a minimal PowerShell script detection if none present
    if ($detectionRules.Count -eq 0) {
        Write-UILog -Message 'No detection rules defined in App.json; skipping detection rule upload.' -Level Warning -SyncHash $SyncHash
    }

    # -- Build minimum OS version object --------------------------------------
    $minOsRaw = [string]$DefinitionObject.RequirementRule.MinimumRequiredOperatingSystem
    $minOsKey = ($minOsRaw -replace '^W', 'v' -replace '^(v10|v11)_', '$1_').ToLowerInvariant()
    # Map "W10_1809" -> "v10_1809"
    $minOsKey = $minOsRaw -replace '^W10_', 'v10_' -replace '^W11_', 'v11_'

    $minimumOsObject = [ordered]@{ '@odata.type' = '#microsoft.graph.windowsMinimumOperatingSystem' }
    if (-not [string]::IsNullOrWhiteSpace($minOsKey)) {
        $minimumOsObject[$minOsKey] = $true
    }
    else {
        $minimumOsObject['v10_1809'] = $true  # safe default
    }

    # -- Build allowed architectures string -----------------------------------
    # The Graph API allowedArchitectures field is a string enum, not an array.
    # Parse RequirementRule.Architecture (single value or comma-separated list)
    # and map to the nearest valid Graph enum value:
    #   x64 only                -> 'x64'         (x64 machines only)
    #   arm64 only              -> 'arm64'        (arm64 machines only)
    #   x86 only                -> 'x86'          (x86 machines only)
    #   x86,x64 or x86,x64,arm64 -> 'x86,x64,arm64' (union spans all machine types)
    #   null / unspecified      -> 'x86,x64,arm64' (safe default)
    $archRaw = [string]$DefinitionObject.RequirementRule.Architecture
    $archList = @(
        $archRaw -split ',' |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { $_ -ne '' }
    )

    $allowedArchitectures = if ($archList.Count -eq 1) {
        switch ($archList[0]) {
            'x64'   { 'x64' }
            'x86'   { 'x86' }
            'arm64' { 'arm64' }
            default { 'x86,x64,arm64' }
        }
    }
    else {
        'x86,x64,arm64'
    }
    Write-UILog -Message "Allowed architectures resolved to '$allowedArchitectures' (RequirementRule.Architecture='$archRaw')." -Level Info -SyncHash $SyncHash

    # -- Build install experience ----------------------------------------------
    $runAs          = if ([string]$DefinitionObject.Program.InstallExperience -ieq 'user') { 'user' } else { 'system' }
    $deviceRestart  = [string]$DefinitionObject.Program.DeviceRestartBehavior
    if ([string]::IsNullOrWhiteSpace($deviceRestart)) { $deviceRestart = 'suppress' }

    # -- Build Notes JSON (PSPackageFactory format) ----------------------------
    $importDate = (Get-Date).ToUniversalTime().ToString('o')
    $notesObject = [ordered]@{
        CreatedBy = 'PSPackageFactory'
        Guid      = $PSPackageFactoryGuid
        Date      = $importDate
    }
    $notesJson = $notesObject | ConvertTo-Json -Compress

    # -- Build icon (best-effort, skip on failure) -----------------------------
    $largeIcon = $null
    $iconUrl   = [string]$DefinitionObject.PackageInformation.IconFile
    if (-not [string]::IsNullOrWhiteSpace($iconUrl)) {
        try {
            $iconBytes    = (Invoke-WebRequest -Uri $iconUrl -UseBasicParsing -ErrorAction Stop).Content
            $iconMimeType = if ($iconUrl -match '\.png') { 'image/png' } elseif ($iconUrl -match '\.jpg|\.jpeg') { 'image/jpeg' } else { 'image/png' }
            $largeIcon    = [ordered]@{
                '@odata.type' = '#microsoft.graph.mimeContent'
                'type'        = $iconMimeType
                'value'       = [Convert]::ToBase64String($iconBytes)
            }
        }
        catch {
            Write-UILog -Message "Icon download skipped (non-fatal): $($_.Exception.Message)" -Level Warning -SyncHash $SyncHash
        }
    }

    # -- Build app body --------------------------------------------------------
    $setupFilePath = ''
    if (-not [string]::IsNullOrWhiteSpace($SetupFilePath)) {
        $setupFilePath = [System.IO.Path]::GetFileName($SetupFilePath)
    }
    else {
        $setupFilePath = [System.IO.Path]::GetFileName([string]$DefinitionObject.PackageInformation.SetupFile)
    }

    if ([string]::IsNullOrWhiteSpace($setupFilePath)) {
        $setupFilePath = [System.IO.Path]::GetFileName($IntuneWinPath)
    }

    $appBodyJson = ''
    $appBody = [ordered]@{
        '@odata.type'                = '#microsoft.graph.win32LobApp'
        'displayName'                = $displayName
        'description'                = [string]$DefinitionObject.Information.Description
        'publisher'                  = [string]$DefinitionObject.Information.Publisher
        'informationUrl'             = [string]$DefinitionObject.Information.InformationURL
        'privacyInformationUrl'      = [string]$DefinitionObject.Information.PrivacyURL
        'isFeatured'                 = $false
        'displayVersion'             = $DownloadedVersion
        'fileName'                   = [System.IO.Path]::GetFileName($IntuneWinPath)
        'installCommandLine'         = [string]$DefinitionObject.Program.InstallCommand
        'uninstallCommandLine'       = [string]$DefinitionObject.Program.UninstallCommand
        'installExperience'          = [ordered]@{
            'runAsAccount'          = $runAs
        }
        'deviceRestartBehavior'      = $deviceRestart
        'allowAvailableUninstall'    = [bool]$DefinitionObject.Program.AllowAvailableUninstall
        'setupFilePath'              = $setupFilePath
        'allowedArchitectures'        = $allowedArchitectures
        'minimumSupportedOperatingSystem' = $minimumOsObject
        'detectionRules'             = @($detectionRules)
        'requirementRules'           = @()
        'notes'                      = $notesJson
    }

    if ($null -ne $largeIcon) {
        $appBody['largeIcon'] = $largeIcon
    }

    $appBodyJson = $appBody | ConvertTo-Json -Depth 20

    # Log an equivalent Add-IntuneWin32App command line for troubleshooting parity.
    $logDisplayName = ([string]$displayName).Replace('"', "''")
    $logSetupFilePath = ([string]$setupFilePath).Replace('"', "''")
    $logInstallCommand = ([string]$DefinitionObject.Program.InstallCommand).Replace('"', "''")
    $logUninstallCommand = ([string]$DefinitionObject.Program.UninstallCommand).Replace('"', "''")
    $logInfoUrl = ([string]$DefinitionObject.Information.InformationURL).Replace('"', "''")
    $logPrivacyUrl = ([string]$DefinitionObject.Information.PrivacyURL).Replace('"', "''")

    $addIntuneCmdLine = @(
        'Add-IntuneWin32App'
        ("-FilePath {0}" -f $IntuneWinPath)
        ("-DisplayName {0}" -f $logDisplayName)
        ("-Publisher {0}" -f ([string]$DefinitionObject.Information.Publisher).Replace('"', "''"))
        ("-Description {0}" -f ([string]$DefinitionObject.Information.Description).Replace('"', "''"))
        ("-AppVersion {0}" -f $DownloadedVersion)
        ("-SetupFilePath {0}" -f $logSetupFilePath)
        ("-InstallCommandLine {0}" -f $logInstallCommand)
        ("-UninstallCommandLine {0}" -f $logUninstallCommand)
        ("-InformationURL {0}" -f $logInfoUrl)
        ("-PrivacyURL {0}" -f $logPrivacyUrl)
    ) -join ' '

    Write-UILog -Message $addIntuneCmdLine -Level Cmd -SyncHash $SyncHash

    # -- Step 1: Create the app ------------------------------------------------
    Write-UILog -Message "POST /beta/deviceAppManagement/mobileApps" -Level Cmd -SyncHash $SyncHash
    $appResponse = $null
    try {
        $appResponse = Invoke-MgGraphRequest -Method POST `
            -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
            -Body $appBodyJson `
            -ContentType 'application/json' `
            -OutputType PSObject -ErrorAction Stop
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorDetails = ''

        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
            $errorDetails = [string]$_.ErrorDetails.Message
        }

        if ([string]::IsNullOrWhiteSpace($errorDetails)) {
            try {
                if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.Content) {
                    $rawResponse = $_.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    if (-not [string]::IsNullOrWhiteSpace($rawResponse)) {
                        $errorDetails = $rawResponse
                    }
                }
            }
            catch {
                # best-effort - secondary read/parse errors when building diagnostics must not mask the primary error
                Write-Verbose -Message "EvergreenUI: Could not read Graph error response body (ignored): $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($errorDetails)) {
            Write-UILog -Message ("Graph create-app response: {0}" -f $errorDetails) -Level Error -SyncHash $SyncHash
        }

        Write-UILog -Message ("Graph create-app request payload: {0}" -f $appBodyJson) -Level Cmd -SyncHash $SyncHash
        return (& $fail "Failed to create Win32 app: $errorMessage")
    }

    $appId = [string]$appResponse.id
    if ([string]::IsNullOrWhiteSpace($appId)) {
        return (& $fail 'App creation response did not contain an ID.')
    }
    Write-UILog -Message "Win32 app created: id=$appId" -Level Info -SyncHash $SyncHash

    $baseAppUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp"

    # -- Step 2: Create a content version -------------------------------------
    Write-UILog -Message "POST $baseAppUri/contentVersions" -Level Cmd -SyncHash $SyncHash
    $contentVersionResponse = $null
    try {
        $contentVersionResponse = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseAppUri/contentVersions" `
            -Body '{}' `
            -ContentType 'application/json' `
            -OutputType PSObject -ErrorAction Stop
    }
    catch {
        return (& $fail ("Failed to create content version for app {0} - {1}" -f $appId, $_.Exception.Message))
    }

    $contentVersionId = [string]$contentVersionResponse.id
    Write-UILog -Message "Content version created: id=$contentVersionId" -Level Info -SyncHash $SyncHash

    # -- Step 3: Create the file entry -----------------------------------------
    Write-UILog -Message "POST $baseAppUri/contentVersions/$contentVersionId/files" -Level Cmd -SyncHash $SyncHash
    $fileBody = [ordered]@{
        '@odata.type'  = '#microsoft.graph.mobileAppContentFile'
        'name'         = 'IntunePackage.intunewin'
        'size'         = $unencryptedSize
        'sizeEncrypted' = $encryptedSize
        'isDependency' = $false
    }
    $fileEntryResponse = $null
    try {
        $fileEntryResponse = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseAppUri/contentVersions/$contentVersionId/files" `
            -Body ($fileBody | ConvertTo-Json) `
            -ContentType 'application/json' `
            -OutputType PSObject -ErrorAction Stop
    }
    catch {
        return (& $fail "Failed to create file entry: $($_.Exception.Message)")
    }

    $fileId  = [string]$fileEntryResponse.id
    $sasUri  = [string]$fileEntryResponse.azureStorageUri
    Write-UILog -Message "File entry created: id=$fileId" -Level Info -SyncHash $SyncHash

    # Poll for SAS URI to become available if not immediately returned
    if ([string]::IsNullOrWhiteSpace($sasUri)) {
        $fileUri = "$baseAppUri/contentVersions/$contentVersionId/files/$fileId"
        $pollingAttempts = 0
        $maxPollingAttempts = 20
        while ([string]::IsNullOrWhiteSpace($sasUri) -and $pollingAttempts -lt $maxPollingAttempts) {
            Start-Sleep -Seconds 3
            $pollingAttempts++
            try {
                $fileStatus = Invoke-MgGraphRequest -Method GET -Uri $fileUri -OutputType PSObject -ErrorAction Stop
                $sasUri = [string]$fileStatus.azureStorageUri
            }
            catch {
                # best-effort - transient Graph errors during SAS URI polling should not abort the loop
                Write-UILog -Message "SAS URI poll attempt $pollingAttempts/$maxPollingAttempts failed (retrying): $($_.Exception.Message)" -Level Warning -SyncHash $SyncHash
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($sasUri)) {
            Write-UILog -Message "SAS URI obtained after $pollingAttempts attempt(s)." -Level Info -SyncHash $SyncHash
        }
    }

    if ([string]::IsNullOrWhiteSpace($sasUri)) {
        return (& $fail 'Azure Blob SAS URI was not returned after polling.')
    }

    # -- Step 4: Upload encrypted content to Azure Blob ------------------------
    Write-UILog -Message "Uploading package to Azure Blob Storage ($('{0:N0}' -f ($encryptedSize / 1MB)) MB)..." -Level Info -SyncHash $SyncHash

    try {
        $innerFileInfo = [System.IO.FileInfo]::new($encryptedFilePath)
        $actualSize    = $innerFileInfo.Length
        if ($encryptedSize -le 0) {
            $encryptedSize = $actualSize
        }
        $chunkSize     = 4 * 1024 * 1024  # 4 MB
        $blockIds      = [System.Collections.Generic.List[string]]::new()
        $blockNum      = 0
        $fileStream    = [System.IO.File]::OpenRead($encryptedFilePath)
        $buffer        = [byte[]]::new($chunkSize)

        try {
            while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                # Always upload an exact byte[] slice for this block.
                # Using range slicing on a byte[] can produce object[] in PowerShell,
                # which corrupts the payload and causes commitFileFailed.
                $chunk = [byte[]]::new($bytesRead)
                [System.Array]::Copy($buffer, 0, $chunk, 0, $bytesRead)

                $blockId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($blockNum.ToString('D8')))
                $blockIds.Add($blockId)

                $separator = if ($sasUri -match '\?') { '&' } else { '?' }
                $blockUrl  = "$sasUri${separator}comp=block&blockid=$([Uri]::EscapeDataString($blockId))"

                Invoke-RestMethod -Uri $blockUrl -Method Put `
                    -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } `
                    -Body $chunk -ContentType 'application/octet-stream' -ErrorAction Stop | Out-Null

                $blockNum++
                if ($blockNum % 10 -eq 0) {
                    $pct = [Math]::Round(($blockNum * $chunkSize / $actualSize) * 100, 0)
                    Write-UILog -Message "Upload progress: ~$pct%" -Level Info -SyncHash $SyncHash
                }
            }
        }
        finally {
            $fileStream.Close()
        }

        # Finalize: PUT block list
        $blockListXml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
        foreach ($id in $blockIds) { $blockListXml += "<Latest>$id</Latest>" }
        $blockListXml += '</BlockList>'

        $separator     = if ($sasUri -match '\?') { '&' } else { '?' }
        $blockListUrl  = "$sasUri${separator}comp=blocklist"
        Invoke-RestMethod -Uri $blockListUrl -Method Put -ContentType 'application/xml' `
            -Body $blockListXml -ErrorAction Stop | Out-Null

        Write-UILog -Message 'Upload to Azure Blob Storage complete.' -Level Info -SyncHash $SyncHash
    }
    catch {
        return (& $fail "Azure Blob upload failed: $($_.Exception.Message)")
    }
    finally {
        # Clean up temp file regardless of success/failure
        if (-not [string]::IsNullOrWhiteSpace($encryptedFilePath) -and
            (Test-Path -LiteralPath $encryptedFilePath)) {
            Remove-Item -LiteralPath $encryptedFilePath -Force -ErrorAction SilentlyContinue
        }
    }

    # -- Step 5: Commit the file ------------------------------------------------
    Write-UILog -Message 'Committing file to Intune...' -Level Info -SyncHash $SyncHash
    $commitBody = [ordered]@{
        'fileEncryptionInfo' = [ordered]@{
            '@odata.type'          = '#microsoft.graph.fileEncryptionInfo'
            'encryptionKey'       = $encKey
            'macKey'              = $encMacKey
            'initializationVector' = $encIV
            'mac'                 = $encMac
            'profileIdentifier'   = $encProfileId
            'fileDigest'          = $encFileDigest
            'fileDigestAlgorithm' = $encFileDigestAlg
        }
    }

    $fileUri = "$baseAppUri/contentVersions/$contentVersionId/files/$fileId"
    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "$fileUri/commit" `
            -Body ($commitBody | ConvertTo-Json) `
            -ContentType 'application/json' -ErrorAction Stop | Out-Null
    }
    catch {
        return (& $fail "File commit failed: $($_.Exception.Message)")
    }

    # Poll for commit success
    $commitSuccess  = $false
    $commitAttempts = 0
    $maxCommitAttempts = 40
    while (-not $commitSuccess -and $commitAttempts -lt $maxCommitAttempts) {
        Start-Sleep -Seconds 5
        $commitAttempts++
        try {
            $fileStatus   = Invoke-MgGraphRequest -Method GET -Uri $fileUri -OutputType PSObject -ErrorAction Stop
            $uploadState  = [string]$fileStatus.uploadState
            Write-UILog -Message "Commit state: $uploadState" -Level Info -SyncHash $SyncHash
            if ($uploadState -ieq 'commitFileSuccess') {
                $commitSuccess = $true
            }
            elseif ($uploadState -imatch 'failed|error') {
                try {
                    $failureDetails = $fileStatus | ConvertTo-Json -Depth 12 -Compress
                    Write-UILog -Message "Commit failure details: $failureDetails" -Level Error -SyncHash $SyncHash
                }
                catch {
                    # best-effort - JSON serialisation of diagnostic details is non-fatal
                    Write-UILog -Message 'Could not serialise commit failure details for logging.' -Level Warning -SyncHash $SyncHash
                }
                return (& $fail "File commit reached failed state: $uploadState")
            }
        }
        catch {
            Write-UILog -Message "Commit poll error (retrying): $($_.Exception.Message)" -Level Warning -SyncHash $SyncHash
        }
    }

    if (-not $commitSuccess) {
        return (& $fail 'File commit did not reach commitFileSuccess state within the timeout period.')
    }

    # -- Step 6: Patch app with committed content version ---------------------
    Write-UILog -Message "Updating app '$appId' with committedContentVersion '$contentVersionId'..." -Level Info -SyncHash $SyncHash
    $patchBody = [ordered]@{
        '@odata.type'               = '#microsoft.graph.win32LobApp'
        'committedContentVersion'   = $contentVersionId
    }
    try {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId" `
            -Body ($patchBody | ConvertTo-Json) `
            -ContentType 'application/json' -ErrorAction Stop | Out-Null
    }
    catch {
        return (& $fail "Failed to set committedContentVersion on app '$appId': $($_.Exception.Message)")
    }

    Write-UILog -Message "Import complete. App '$displayName' created with id: $appId" -Level Info -SyncHash $SyncHash

    return [PSCustomObject]@{
        Succeeded   = $true
        IntuneAppId = $appId
        DisplayName = $displayName
        Error       = ''
    }
}


