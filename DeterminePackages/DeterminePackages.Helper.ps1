. (Join-Path -Path $PSScriptRoot -ChildPath "ForBCContainerHelper\DetermineArtifactUrl.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)

function Get-NuGetPackagesAndAddToSettings {
    [CmdletBinding()]
    Param(
        [hashtable] $settings,
        [string] $sourceProperty,
        [string] $targetProperty,
        [hashtable] $packageParams
    )
    
    if ($settings[$sourceProperty]) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings[$sourceProperty] | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @packageParams
            if (-not $appFile) {
                throw "Package $packageName not found in NuGet feeds"
            }
            if (!$settings[$targetProperty]) {
                $settings[$targetProperty] = @()
            }
            $settings[$targetProperty] += $appFile
            Write-Host " - adding app: $packageName"
        }
    }
}

function Get-DependenciesFromNuGet {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )

    $settings = $settings | Copy-HashTable
    Write-Host "Checking appDependenciesNuGet and testDependenciesNuGet"
    $getDependencyNuGetPackageParams = @{}
    if ($ENV:AL_ALLOWPRERELEASE -eq "true") {
        $getDependencyNuGetPackageParams += @{
            "allowPrerelease" = $true
        }
    }

    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    if (!$settings.doNotRunBcptTests -and !$settings.bcptTestFolders) {
        Write-Host "No performance test apps found in bcptTestFolders in settings."
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotBuildTests -and !$settings.testFolders) {
        OutputWarning -Message "No test apps found in testFolders in settings, skipping tests."
        $settings.doNotBuildTests = $true
    }
    if (!$settings.doNotBuildTests) {
        $folderFound = $false
        foreach ($folderName in $settings.testFolders) {
            $testFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath $folderName
            if (Test-Path $testFolder) {
                $folderFound = $true
            }
        }
        if (-not $folderFound) {
            OutputWarning -Message "Test folder specified in settings but the folder does not exist, skipping tests."
            $settings.doNotBuildTests = $true
        }
    }
    if (!$settings.appFolders) {
        OutputWarning -Message "No apps found in appFolders in settings."
    }
    Write-Host "Analyzing dependencies completed"
    
    # Process app dependencies from NuGet
    Write-Host "Adding app dependencies:"
    Get-NuGetPackagesAndAddToSettings -settings $settings -sourceProperty "appDependenciesNuGet" -targetProperty "appDependencies" -packageParams $getDependencyNuGetPackageParams

    if (-not $settings.doNotBuildTests) {
        # Process test dependencies from NuGet
        Write-Host "Adding test dependencies:"
        Get-NuGetPackagesAndAddToSettings -settings $settings -sourceProperty "testDependenciesNuGet" -targetProperty "testDependencies" -packageParams $getDependencyNuGetPackageParams
    }

    Write-Host "Checking installAppsNuGet and installTestAppsNuGet"
    
    # Process install apps from NuGet
    Write-Host "Adding additional apps to install:"
    Get-NuGetPackagesAndAddToSettings -settings $settings -sourceProperty "installAppsNuGet" -targetProperty "installApps" -packageParams $getDependencyNuGetPackageParams

    if (-not $settings.doNotBuildTests) {
        # Process install test apps from NuGet
        Write-Host "Adding additional test apps to install:"
        Get-NuGetPackagesAndAddToSettings -settings $settings -sourceProperty "installTestAppsNuGet" -targetProperty "installTestApps" -packageParams $getDependencyNuGetPackageParams
    }

    return $settings
}

function Get-PreviousReleaseFromNuGet {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )

    $settings = $settings | Copy-HashTable
    if ($settings.skipUpgrade -or $null -eq $settings.appFolders -or $settings.appFolders.Count -eq 0) {
        $settings.previousRelease = @()
        return $settings
    }

    Write-Host "Locating previous release"     
    $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
    $appJsonFile = Join-Path $folder "app.json"
    $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    if (Test-Path $appJsonFile) {
        $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
        $packageId = Get-BCDevOpsFlowsNuGetPackageId -id $appJson.id -name $appJson.name -publisher $appJson.publisher
        $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageId
        if ($appFile) {
            if (!$settings.previousRelease) {
                $settings.previousRelease = @()
            }
            $settings.previousRelease += $appFile
            Write-Host "Adding previous release from NuGet: $packageId"
        }
        else {
            OutputWarning -Message "No previous release found in NuGet for $packageId"
        }
    }
    else {
        throw  "No app.json file found in $folder"
    }
    return $settings
}

function Update-CustomCodeCops {
    [CmdletBinding()]
    Param(
        [hashtable] $settings,
        [string] $runWith
    )

    if (!$settings.customCodeCops) {
        $settings.customCodeCops = @()
    }
    $settings.customCodeCops = $settings.customCodeCops | Where-Object { $_ -notlike "https://github.com/StefanMaron/BusinessCentral.LinterCop*" }
    if ($settings.customCodeCops.Count -eq 0) {
        $settings.customCodeCops = @()
    }    
    
    if (-not $settings.enableLinterCop) {
        return $settings
    }

    Write-Host "Determining LinterCop version"     
    if ($runWith -eq 'nuget') {
        $majorVersion = "Current"
        $linterCopURL = "BusinessCentral.LinterCop.dll"
    }
    else {
        $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
        $appJsonFile = Join-Path $folder "app.json"
        if (Test-Path $appJsonFile) {
            $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
            $majorVersion = [Version]::Parse($appJson.application).Major
            # https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/BusinessCentral.LinterCop.dll
            switch ($majorVersion) {
                25 { $linterCopURL = "BusinessCentral.LinterCop.AL-14.3.1327807.dll" }
                24 { $linterCopURL = "BusinessCentral.LinterCop.AL-13.1.1065068.dll" }
                23 { $linterCopURL = "BusinessCentral.LinterCop.AL-12.7.964847.dll" }
                default { $linterCopURL = "BusinessCentral.LinterCop.dll" }
            }
        }
        else {
            throw  "No app.json file found in $folder"
        }
    }
    
    Write-Host "Using LinterCop for version $majorVersion, URL: $linterCopURL"
    $settings.customCodeCops += "https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/$linterCopURL"
    Write-Host "Configured custom CodeCops:"
    $settings.customCodeCops | ForEach-Object {
        Write-Host "- $_"
    }
    return $settings
}

