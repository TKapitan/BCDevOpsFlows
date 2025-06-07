. (Join-Path -Path $PSScriptRoot -ChildPath "NuGet.Helper.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\DeterminePackages\ForBCContainerHelper\DetermineArtifactUrl.Helper.ps1" -Resolve)

function Get-DependenciesFromNuGet {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )

    $settings = $settings | Copy-HashTable
    $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    Write-Host "Checking appDependenciesNuGet and testDependenciesNuGet"
    $getDependencyNuGetPackageParams = @{}
    if ($ENV:AL_ALLOWPRERELEASE) {
        $getDependencyNuGetPackageParams += @{
            "allowPrerelease" = $true
        }
    }
    if ($settings.appDependenciesNuGet) {
        $settings.appDependenciesNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.appDependencies) {
                    $settings.appDependencies = @()
                }
                $settings.appDependencies += $appFile
                Write-Host "Adding app dependency $packageName"
            }
        }
    }

    if ($settings.testDependenciesNuGet) {
        $settings.testDependenciesNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @getDependencyNuGetPackageParams
            if ($appFile) {
                if (!$settings.testDependencies) {
                    $settings.testDependencies = @()
                }
                $settings.testDependencies += $appFile
                Write-Host "Adding test dependency $packageName"
            }
        }
    }
    
    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    if (!$settings.doNotRunBcptTests -and !$settings.bcptTestFolders) {
        Write-Host "No performance test apps found in bcptTestFolders in $repoSettingsFile"
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and !$settings.testFolders) {
        OutputWarning -Message "No test apps found in testFolders in $repoSettingsFile" 
        $settings.doNotRunTests = $true
    }
    if (!$settings.appFolders) {
        OutputWarning -Message "No apps found in appFolders in $repoSettingsFile" 
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
