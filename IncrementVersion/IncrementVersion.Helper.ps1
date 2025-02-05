. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteSettings.Helper.ps1" -Resolve)

function Test-SettingExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $settingsFilePath,
        [Parameter(Mandatory = $true)]
        [string] $settingName
    )

    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    try {
        $settingsJson = Get-Content $settingsFilePath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    catch {
        throw "Settings file ($settingsFilePath) is malformed: $_"
    }

    $settingExists = [bool] ($settingsJson.PSObject.Properties.Name -eq $settingName)
    return $settingExists
}
function Set-VersionInSettingsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $settingsFilePath,
        [Parameter(Mandatory = $true)]
        [string] $settingName,
        [Parameter(Mandatory = $true)]
        [string] $newValue,
        [switch] $Force
    )

    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    try {
        $settingsJson = Get-Content $settingsFilePath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    catch {
        throw "Settings file ($settingsFilePath) is malformed: $_"
    }

    $settingExists = [bool] ($settingsJson.PSObject.Properties.Name -eq $settingName)
    if ((-not $settingExists) -and (-not $Force)) {
        Write-Host "Setting $settingName not found in $settingsFilePath"
        return
    }

    # Add the setting if it does not exist
    if (-not $settingExists) {
        $settingsJson | Add-Member -MemberType NoteProperty -Name $settingName -Value $null
    }

    $oldVersion = [System.Version] $settingsJson.$settingName
    # Validate new version value
    if ($newValue.StartsWith('+')) {
        # Handle incremental version number

        # Defensive check. Should never happen.
        $allowedIncrementalVersionNumbers = @('+1', '+0.1', '+0.0.1', '+0.0.0.1')
        if (-not $allowedIncrementalVersionNumbers.Contains($newValue)) {
            throw "Unexpected error - incremental version number $newValue is not allowed. Allowed incremental version numbers are: $($allowedIncrementalVersionNumbers -join ', ')"
        }
        # Defensive check. Should never happen.
        if ($null -eq $oldVersion) {
            throw "Unexpected error - the setting $settingName does not exist in the settings file. It must exist to be able to increment the version number."
        }
    }
    else {
        # Handle absolute version number

        # Defensive check. Should never happen.
        $versionNumberFormat = '^\d+\.\d+(\.\d+(\.\d+))?$' # Major.Minor or Major.Minor.Build or Major.Minor.Build.Revision
        if (-not ($newValue -match $versionNumberFormat)) {
            throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build or Major.Minor.Build.Revision (e.g. 1.0, 1.2, 1.3.0 or 1.4.0.1)"
        }
    }

    $versionNumbers = @() # an array to hold the version numbers: major, minor, build, revision

    switch ($newValue) {
        '+1' {
            # Increment major version number
            $versionNumbers += $oldVersion.Major + 1
            $versionNumbers += 0
            # Include build number if it exists in the old version number
            if ($oldVersion.Build -ne -1) {
                $versionNumbers += 0
            }
            # Include revision number if it exists in the old version number
            if ($oldVersion.Revision -ne -1) {
                $versionNumbers += 0
            }
        }
        '+0.1' {
            # Increment minor version number
            $versionNumbers += $oldVersion.Major
            $versionNumbers += $oldVersion.Minor + 1
            # Include build number if it exists in the old version number
            if ($oldVersion.Build -ne -1) {
                $versionNumbers += 0
            }
            # Include revision number if it exists in the old version number
            if ($oldVersion.Revision -ne -1) {
                $versionNumbers += 0
            }
        }
        '+0.0.1' {
            # Increment build version number
            $versionNumbers += $oldVersion.Major
            $versionNumbers += $oldVersion.Minor
            if ($oldVersion.Build -eq -1) {
                $versionNumbers += 1
            }
            else {
                $versionNumbers += $oldVersion.Build + 1
            }
        }
        '+0.0.0.1' {
            # Increment revision version number
            $versionNumbers += $oldVersion.Major
            $versionNumbers += $oldVersion.Minor
            $versionNumbers += $oldVersion.Build
            if ($oldVersion.Revision -eq -1) {
                $versionNumbers += 1
            }
            else {
                $versionNumbers += $oldVersion.Revision + 1
            }
        }
        default {
            # Absolute version number
            $versionNumbers += $newValue.Split('.')
            if ($versionNumbers.Count -eq 2 -and ($null -ne $oldVersion -and $oldVersion.Build -ne -1)) {
                $versionNumbers += 0
            }
        }
    }

    # Construct the new version number. Cast to System.Version to validate if the version number is valid.
    $newVersion = [System.Version] "$($versionNumbers -join '.')"

    if ($newVersion -lt $oldVersion) {
        throw "The new version number ($newVersion) is less than the old version number ($oldVersion). The version number must be incremented."
    }

    if ($newVersion -eq $oldVersion) {
        Write-Host "The setting $settingName is already set to $newVersion in $settingsFilePath"
        return
    }

    if ($null -eq $oldVersion) {
        Write-Host "Setting setting $settingName to $newVersion in $settingsFilePath"
    }
    else {
        Write-Host "Changing $settingName from $oldVersion to $newVersion in $settingsFilePath"
    }

    $settingsJson.$settingName = $newVersion.ToString()
    Set-JsonContentLF -Path $settingsFilePath -object $settingsJson
    return $settingsJson.$settingName
}
function Set-VersionInAppManifests($appFilePath, $settings, $newValue) {
    # Check if repository uses repoVersion versioning strategy
    $useRepoVersion = (($settings.PSObject.Properties.Name -eq "versioningStrategy") -and (($settings.versioningStrategy -band 16) -eq 16))
    if ($useRepoVersion) {
        $newValue = $settings.repoVersion
    }
    # Set version in app.json file
    $newVersion = Set-VersionInSettingsFile -settingsFilePath $appFilePath -settingName 'version' -newValue $newValue
    OutputDebug -Message "New version applied to app.json: $newVersion"
    return $newVersion
}