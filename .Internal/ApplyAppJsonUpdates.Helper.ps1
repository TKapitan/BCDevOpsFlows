. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteSettings.Helper.ps1" -Resolve)

function Update-AppJson {
    Param(
        [Parameter(Mandatory)]
        [PSCustomObject]$settings
    )
    RemoveInternalsVisibleTo -settings $settings
    OverrideResourceExposurePolicy -settings $settings
}

function RemoveInternalsVisibleTo {
    Param(
        [Parameter(Mandatory)]
        [PSCustomObject]$settings
    )

    if ($settings.removeInternalsVisibleTo) {
        $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "App\app.json"
        $appFileJson = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
        
        $settingExists = [bool] ($appFileJson.PSObject.Properties.Name -eq 'internalsVisibleTo')
        if (!$settingExists) {
            OutputDebug -Message "Setting 'internalsVisibleTo' not found in app.json - nothing to remove"
        }
        else {
            if ($appFileJson.internalsVisibleTo.Count -eq 0) {
                OutputDebug -Message "'internalsVisibleTo' is blank - nothing to remove"
            }
            else {
                $appFileJson.internalsVisibleTo = @()
                Write-Host "Removing 'internalsVisibleTo' from app.json by replacing with empty array"
            }
        }
        Set-JsonContentLF -Path $appJsonFilePath -object $appFileJson
    }
}

function OverrideResourceExposurePolicy {
    Param(
        [Parameter(Mandatory)]
        [PSCustomObject]$settings
    )

    if ($settings.overrideResourceExposurePolicy) {
        $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "App\app.json"
        $appFileJson = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
    
        $resourceExposurePolicySpecified = [bool] ($appFileJson.PSObject.Properties.Name -eq 'resourceExposurePolicy')
        if (!$resourceExposurePolicySpecified) {
            $resourceExposurePolicy = [PSCustomObject]@{}
            OutputDebug -Message "Setting 'resourceExposurePolicy' using settings from pipeline. No existing setting found in app.json"
        }
        else {
            $resourceExposurePolicy = $appFileJson.resourceExposurePolicy
            OutputDebug -Message "Setting 'resourceExposurePolicy' using settings from pipeline and existing app.json setting"
        }

        if ($settings.Contains('allowDebugging')) {
            $resourceExposurePolicy | Add-Member -MemberType NoteProperty -Name 'allowDebugging' -Value $settings.allowDebugging -Force
            OutputDebug -Message "Setting 'allowDebugging' from $($appFileJson.resourceExposurePolicy.allowDebugging) to $($settings.allowDebugging)"
        }
        if ($settings.Contains('allowDownloadingSource')) {
            $resourceExposurePolicy | Add-Member -MemberType NoteProperty -Name 'allowDownloadingSource' -Value $settings.allowDownloadingSource -Force
            OutputDebug -Message "Setting 'allowDownloadingSource' from $($appFileJson.resourceExposurePolicy.allowDownloadingSource) to $($settings.allowDownloadingSource)"
        }
        if ($settings.Contains('includeSourceInSymbolFile')) {
            $resourceExposurePolicy | Add-Member -MemberType NoteProperty -Name 'includeSourceInSymbolFile' -Value $settings.includeSourceInSymbolFile -Force
            OutputDebug -Message "Setting 'includeSourceInSymbolFile' from $($appFileJson.resourceExposurePolicy.includeSourceInSymbolFile) to $($settings.includeSourceInSymbolFile)"
        }
        if ($settings.Contains('applyToDevExtension')) {
            $resourceExposurePolicy | Add-Member -MemberType NoteProperty -Name 'applyToDevExtension' -Value $settings.applyToDevExtension -Force
            OutputDebug -Message "Setting 'applyToDevExtension' from $($appFileJson.resourceExposurePolicy.applyToDevExtension) to $($settings.applyToDevExtension)"
        }
    
        $appFileJson | Add-Member -MemberType NoteProperty -Name 'resourceExposurePolicy' -Value $resourceExposurePolicy -Force
        Set-JsonContentLF -Path $appJsonFilePath -object $appFileJson
    }
}
