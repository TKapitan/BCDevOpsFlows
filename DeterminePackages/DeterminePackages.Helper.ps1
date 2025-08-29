. (Join-Path -Path $PSScriptRoot -ChildPath "ForBCContainerHelper\DetermineArtifactUrl.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)

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
    if ($settings.appDependenciesNuGet) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings.appDependenciesNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.appDependencies) {
                    $settings.appDependencies = @()
                }
                $settings.appDependencies += $appFile
                Write-Host "Adding app dependency: $packageName"
            }
        }
    }

    if ($settings.testDependenciesNuGet) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings.testDependenciesNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.testDependencies) {
                    $settings.testDependencies = @()
                }
                $settings.testDependencies += $appFile
                Write-Host "Adding test dependency: $packageName"
            }
        }
    }
    
    Write-Host "Checking installAppsNuGet and installTestAppsNuGet"
    
    if ($settings.installAppsNuGet) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings.installAppsNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.installApps) {
                    $settings.installApps = @()
                }
                $settings.installApps += $appFile
                Write-Host "Adding app to install: $packageName"
            }
        }
    }

    if ($settings.installTestAppsNuGet) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings.installTestAppsNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.installTestApps) {
                    $settings.installTestApps = @()
                }
                $settings.installTestApps += $appFile
                Write-Host "Adding test app to install: $packageName"
            }
        }
    }
    
    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    if (!$settings.doNotRunBcptTests -and !$settings.bcptTestFolders) {
        Write-Host "No performance test apps found in bcptTestFolders in settings."
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and !$settings.testFolders) {
        OutputWarning -Message "No test apps found in testFolders in settings."
        $settings.doNotRunTests = $true
    }
    if (!$settings.appFolders) {
        OutputWarning -Message "No apps found in appFolders in settings."
    }
    Write-Host "Analyzing dependencies completed"

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

