Param(
    [Parameter(HelpMessage = "The version to update to. Use Major.Minor[.Build][.Revision] for absolute change, use +1 to bump to the next major version, use +0.1 to bump to the next minor version, +0.0.1 to bump to the next build version or +0.0.0.1 to bump to the next revision version", Mandatory = $false)]
    [string] $versionNumber
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "IncrementVersion.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\ReadSettings\ReadSettings.Helper.ps1" -Resolve)

try {
    $baseFolder = $ENV:BUILD_REPOSITORY_LOCALPATH
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json

    if ([string]::IsNullOrEmpty($versionNumber)) {
        if (-not (Get-Member -InputObject $settings -Name 'updateVersionNumber')) {
            Write-Output "Version change not specified. Skipping version update."
            exit 0
        }
        if ($settings.updateVersionNumber -eq '') {
            Write-Output "Version change not specified. Skipping version update."
            exit 0
        }
        $versionNumber = $settings.updateVersionNumber
    }

    if ($versionNumber.StartsWith('+')) {
        # Handle incremental version number
        $allowedIncrementalVersionNumbers = @('+1', '+0.1')
        if ($settings.versioningStrategy -in @(3, 10)) {
            # Allow increment build
            $allowedIncrementalVersionNumbers += '+0.0.1'
        }
        if ($settings.versioningStrategy -eq 10) {
            $allowedIncrementalVersionNumbers += '+0.0.0.1'
        }
        if (-not $allowedIncrementalVersionNumbers.Contains($versionNumber)) {
            throw "Incremental version number $versionNumber is not allowed. Allowed incremental version numbers are: $($allowedIncrementalVersionNumbers -join ', ')"
        }
    }
    else {
        # Handle absolute version number
        $versionNumberFormat = '^\d+\.\d+$' # Major.Minor
        $correctFormatMsg = 'Major.Minor (e.g. 1.0 or 1.2)'
        if ($settings.versioningStrategy -in @(3, 10)) {
            $versionNumberFormat = '^\d+\.\d+\.\d+$' # Major.Minor.Build
            $correctFormatMsg = 'Major.Minor.Build (e.g. 1.0, 1.2 or 1.2.3)'
        }
        if ($settings.versioningStrategy -eq 10) {
            $versionNumberFormat = '^\d+\.\d+\.\d+.\d+$' # Major.Minor.Build.Revision
            $correctFormatMsg = 'Major.Minor.Build.Revision (e.g. 1.0, 1.2 or 1.2.3 or 1.2.3.4)'
        }
        if (-not ($versionNumber -match $versionNumberFormat)) {
            throw "Version number $versionNumber is not in the correct format. The version number must be in the format $correctFormatMsg"
        }
    }

    $repositorySettingsPath = Join-Path $baseFolder $RepoSettingsFile
    $repoVersionExistsInRepoSettings = Test-SettingExists -settingsFilePath $repositorySettingsPath -settingName 'repoVersion'

    # Set git user and restore unstaged changes for changed file
    Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    Set-GitUser
    Invoke-RestoreUnstagedChanges -appFilePath $repositorySettingsPath

    if ($repoVersionExistsInRepoSettings) {
        # If 'repoVersion' exists in repo settings, update it 
        Write-Host "Setting 'repoVersion' found in $repositorySettingsPath. Updating it on repo level instead"
        Set-VersionInSettingsFile -settingsFilePath $repositorySettingsPath -settingName 'repoVersion' -newValue $versionNumber
    }
    else {
        # If 'repoVersion' is not found in repo settings, force create it 
        # Ensure the repoVersion setting exists in the repo settings. Defaults to 1.0 if it doesn't exist.
        $settings = ReadSettings -baseFolder $baseFolder
        Set-VersionInSettingsFile -settingsFilePath $repositorySettingsPath -settingName 'repoVersion' -newValue $settings.repoVersion -Force
        Set-VersionInSettingsFile -settingsFilePath $repositorySettingsPath -settingName 'repoVersion' -newValue $versionNumber
    }

    # Find repository settings 
    $repositorySettings = ReadSettings -baseFolder $baseFolder
    $appFilePath = Join-Path $baseFolder "App\app.json"

    # Restore unstaged changes for changed file
    Invoke-RestoreUnstagedChanges -appFilePath $appFilePath

    # Set version in app manifests (app.json file)
    $newAppliedVersion = Set-VersionInAppManifests -appFilePath $appFilePath -settings $repositorySettings -newValue $versionNumber

    # Commit changes
    Invoke-GitAdd -appFilePath $repositorySettingsPath
    Invoke-GitAddCommit -appFilePath $appFilePath -commitMessage "Updating version to $newAppliedVersion"
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while updating app.json or pushing changes to Azure DevOps. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}