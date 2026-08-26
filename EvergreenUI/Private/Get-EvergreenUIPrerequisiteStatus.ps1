#Requires -Version 5.1
function Get-EvergreenUIPrerequisiteStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath
    )

    $manifest = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
    $required = [System.Collections.Generic.List[PSCustomObject]]::new()
    $optional = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($requirement in @($manifest.RequiredModules)) {
        $required.Add([PSCustomObject]@{
                Name           = [string]$requirement.ModuleName
                MinimumVersion = [version]$requirement.ModuleVersion
                Feature        = 'Core'
            })
    }

    foreach ($requirement in @($manifest.PrivateData.OptionalModules)) {
        $optional.Add([PSCustomObject]@{
                Name           = $requirement.Name
                MinimumVersion = $null
                Feature        = $requirement.Feature
            })
    }

    $getStatus = {
        param([PSCustomObject]$requirement, [bool]$isRequired)

        $installed = Get-Module -Name $requirement.Name -ListAvailable -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        $installedVersion = if ($null -eq $installed) { $null } else { [version]$installed.Version }
        $satisfied = $null -ne $installedVersion
        if ($isRequired -and $satisfied) {
            $satisfied = $installedVersion -ge $requirement.MinimumVersion
        }

        $message = if ($satisfied) {
            if ($isRequired) {
                "$($requirement.Name) $installedVersion is installed."
            }
            else {
                "$($requirement.Name) $installedVersion is available for $($requirement.Feature)."
            }
        }
        elseif ($isRequired) {
            "Install $($requirement.Name) version $($requirement.MinimumVersion) or later with Install-Module -Name $($requirement.Name) -Scope CurrentUser."
        }
        else {
            "Install $($requirement.Name) with Install-Module -Name $($requirement.Name) -Scope CurrentUser to enable $($requirement.Feature)."
        }

        [PSCustomObject]@{
            Name             = $requirement.Name
            Feature          = $requirement.Feature
            Required         = $isRequired
            MinimumVersion   = if ($null -eq $requirement.MinimumVersion) { $null } else { $requirement.MinimumVersion.ToString() }
            InstalledVersion = if ($null -eq $installedVersion) { $null } else { $installedVersion.ToString() }
            Satisfied        = $satisfied
            Message          = $message
        }
    }

    $requiredStatus = @($required | ForEach-Object { & $getStatus $_ $true })
    $optionalStatus = @($optional | ForEach-Object { & $getStatus $_ $false })
    $missingRequired = @($requiredStatus | Where-Object { -not $_.Satisfied })
    $missingOptional = @($optionalStatus | Where-Object { -not $_.Satisfied })

    [PSCustomObject]@{
        Succeeded       = $missingRequired.Count -eq 0
        Required        = $requiredStatus
        Optional        = $optionalStatus
        MissingRequired = $missingRequired
        MissingOptional = $missingOptional
        Messages        = @($missingRequired + $missingOptional | ForEach-Object { $_.Message })
    }
}