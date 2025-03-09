
. (Join-Path -Path $PSScriptRoot -ChildPath "NuGet.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineArtifactUrl\DetermineArtifactUrl.Helper.ps1" -Resolve)

function AnalyzeRepo {
    [CmdletBinding()]
    Param(
        [hashtable] $settings,
        [switch] $skipAppsInPreview,
        [version] $minBcVersion = [version]'0.0.0.0'
    )
    $settings = $settings | Copy-HashTable

    Write-Host "::group::Analyzing repository"
    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null

    Write-Host "Checking type"
    if ($settings.type -eq "PTE") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $true)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $false)
        }
    }
    elseif ($settings.type -eq "AppSource App") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $false)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $true)
        }
        if ($settings.enableAppSourceCop -and (!($settings.appSourceCopMandatoryAffixes))) {
            Write-Error "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $repoSettingsFile"
        }
        if (!$settings.Contains('removeInternalsVisibleTo')) {
            $settings.Add('removeInternalsVisibleTo', $true)
        }
    }
    else {
        Write-Error "The type, specified in $repoSettingsFile, must be either 'PTE' or 'AppSource App'. It is '$($settings.type)'."
    }

    # Write-Host "Checking appFolders, testFolders and bcptTestFolders"
    # $dependencies = [ordered]@{}
    # $appIdFolders = [ordered]@{}
    # foreach ($folderTypeNumber in 1..3) {
    #     $appFolder = $folderTypeNumber -eq 1
    #     $testFolder = $folderTypeNumber -eq 2
    #     $bcptTestFolder = $folderTypeNumber -eq 3
    #     Write-Host "Reading apps #$folderTypeNumber"
        
    #     if ($appFolder) {
    #         $folders = @()
    #         if ($settings.appFolders) {
    #             $folders = @($settings.appFolders)
    #         }
    #         $descr = "App folder"
    #     }
    #     elseif ($testFolder) {
    #         $folders = @()
    #         if ($settings.testFolders) {
    #             $folders = @($settings.testFolders)
    #         }
    #         $descr = "Test folder"
    #     }
    #     elseif ($bcptTestFolder) {
    #         $folders = @()
    #         if ($settings.bcptTestFolders) {
    #             $folders = @($settings.bcptTestFolders)
    #         }
    #         $descr = "Bcpt Test folder"
    #     }
    #     else {
    #         Write-Error "Internal error"
    #     }     
    #     foreach ($folderName in $folders) {
    #         $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $folderName
    #         Write-Host "Analyzing dependencies for '$folderName' in '$folder'"
    #         $appJsonFile = Join-Path $folder "app.json"
    #         $bcptSuiteFile = Join-Path $folder "bcptSuite.json"
    #         $enumerate = $true

    #         # More compatible folder existence check
    #         if (!(Test-Path $folder -PathType Container)) {
    #             OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not exist"
    #         }
    #         elseif (!(Test-Path $appJsonFile -PathType Leaf)) {
    #             OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain the source code for an app (no app.json file)" 
    #         }
    #         elseif ($bcptTestFolder -and (!(Test-Path $bcptSuiteFile -PathType Leaf))) {
    #             OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain a BCPT Suite (bcptSuite.json)" 
    #             $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName })
    #             $enumerate = $false
    #         }

    #         if ($enumerate) {
    #             if ($dependencies.Contains($folderName)) {
    #                 Write-Error "$descr $folderName, specified in $repoSettingsFile, is specified more than once."
    #             }
    #             $dependencies[$folderName] = @()
    #             try {
    #                 $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
    #                 if ($appIdFolders.Contains($appJson.Id)) {
    #                     Write-Error "$descr $folderName contains a duplicate AppId ($($appIdFolders[$appJson.Id]))"
    #                 }
    #                 $appIdFolders[$appJson.Id] = $folderName

    #                 if ($null -ne (Get-Member -InputObject $appJson -Name 'Dependencies')) {
    #                     $appJson.dependencies | ForEach-Object {
    #                         $id = if ($null -ne (Get-Member -InputObject $_ -Name 'AppId')) { 
    #                             $_.AppId 
    #                         }
    #                         else { 
    #                             $_.Id 
    #                         }
    #                         if ($id -eq $applicationAppId) {
    #                             if ([Version]$_.Version -gt [Version]$settings.applicationDependency) {
    #                                 $settings.applicationDependency = $appDep
    #                             }
    #                         }
    #                         else {
    #                             $dependencies."$folderName" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
    #                         }
    #                     }
    #                 }
    #                 if ($null -ne (Get-Member -InputObject $appJson -Name 'Application')) {
    #                     $appDep = $appJson.application
    #                     if ([Version]$appDep -gt [Version]$settings.applicationDependency) {
    #                         $settings.applicationDependency = $appDep
    #                     }
    #                 }


    #                 $allBCDependenciesParam = @{}
    #                 if ($skipAppsInPreview -eq $true) {
    #                     $allBCDependenciesParam = @{ "skipAppsInPreview" = $true }
    #                 }

    #                 if ($appFolder) {
    #                     $mainAppId = $appJson.id
    #                     if ($appJson.PSObject.Properties.Name -eq 'Version') {
    #                         $settings.appJsonVersion = $appJson.version
    #                     }

    #                     $foundAppDependencies = @(Get-AppDependencies -appJsonFilePath $appJsonFile -minBcVersion $minBcVersion @allBCDependenciesParam)
    #                     if ($foundAppDependencies) {
    #                         $settings.appDependencies += Get-DependenciesAsTextString -dependencies $foundAppDependencies
    #                     }
    #                     Write-Host "Adding newly found APP dependencies: $($settings.appDependencies)"

    #                     if (!$settings.skipUpgrade) {
    #                         Write-Host "Locating previous release"      
    #                         try {
    #                             $latestRelease = Get-LatestRelease -appId $mainAppId 
    #                             if ($latestRelease) {
    #                                 Write-Host "Using $latestRelease as previous release"
    #                                 $settings.previousRelease += $latestRelease
    #                             }
    #                             else {
    #                                 OutputWarning -message "No previous release found"
    #                             }
    #                         }
    #                         catch {
    #                             Write-Host $_.Exception -ForegroundColor Red
    #                             Write-Host $_.ScriptStackTrace
    #                             Write-Host $_.PSMessageDetails
    
    #                             Write-Error "Error trying to locate previous release. See previous lines for details."
    #                         }
    #                     }
    #                     else {
    #                         Write-Host "Skipping upgrade check"
    #                     }
    #                 }
    #                 elseif ($testFolder) {
    #                     $foundTestDependencies = @(Get-AppDependencies -appJsonFilePath $appJsonFile -excludeExtensionID $mainAppId -minBcVersion $minBcVersion @allBCDependenciesParam)
    #                     if ($foundTestDependencies) {
    #                         $settings.testDependencies += Get-DependenciesAsTextString -dependencies $foundTestDependencies
    #                     }
    #                     Write-Host "Adding newly found TEST dependencies: $($settings.testDependencies)"
    #                 }
    #             }
    #             catch {
    #                 Write-Host $_.Exception.Message -ForegroundColor Red
    #                 Write-Host $_.ScriptStackTrace
    #                 if ($null -ne $_.ErrorDetails) {
    #                     Write-Host $_.ErrorDetails.Message
    #                 }
    #                 Write-Error "$descr $folderName, specified in $repoSettingsFile, contains a corrupt app.json file. See the error details above."
    #             }
    #         }
    #     }
    # }

    Initialize-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    Write-Host "Checking appDependenciesNuGet and testDependenciesNuGet"
    if ($settings.appDependenciesNuGet) {
        $settings.appDependenciesNuGet | ForEach-Object {
            $packageName = $_
            $appFile = Get-BcNugetPackage -packageName $packageName
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
            $appFile = Get-BcNugetPackage -packageName $packageName
            if ($appFile) {
                if (!$settings.testDependencies) {
                    $settings.testDependencies = @()
                }
                $settings.testDependencies += $appFile
                Write-Host "Adding test dependency $packageName"
            }
        }
    }

    if (!$settings.skipUpgrade) {
        Write-Host "Locating previous release"     
        if ($settings.appFolders) {
            $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
            $appJsonFile = Join-Path $folder "app.json"
            if (Test-Path $appJsonFile) {
                $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                $packageId = Get-BcNugetPackageId -id $appJson.id -name $appJson.name -publisher $appJson.publisher
                $appFile = Get-BcNugetPackage -packageName $packageId
                if ($appFile) {
                    if (!$settings.previousRelease) {
                        $settings.previousRelease = @()
                    }
                    $settings.previousRelease += $appFile
                    Write-Host "Adding previous release from NuGet: $packageId"
                } else {
                    OutputWarning -Message "No previous release found in NuGet for $packageId"
                }
            }
            else {
                Write-Error  "No app.json file found in $folder"
            }
        }
    }
    
    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }
    Write-Host "Settings installTestRunner = $($settings.installTestRunner), installPerformanceToolkit = $($settings.installPerformanceToolkit)"

    $foundAppDependencies + $foundTestDependencies | ForEach-Object {
        $dependency = $_
        if ($testRunnerApps.Contains($dependency.id)) { $settings.installTestRunner = $true }
        if ($testFrameworkApps.Contains($dependency.id)) { $settings.installTestFramework = $true }
        if ($testLibrariesApps.Contains($dependency.id)) { $settings.installTestLibraries = $true }
        if ($performanceToolkitApps.Contains($dependency.id)) { $settings.installPerformanceToolkit = $true }
    }
    Write-Host "Settings installTestRunner = $($settings.installTestRunner), installTestFramework = $($settings.installTestFramework), installTestLibraries = $($settings.installTestLibraries), installPerformanceToolkit = $($settings.installPerformanceToolkit)"
    
    Write-Host "App.json version $($settings.appJsonVersion)"
    Write-Host "Application Dependency $($settings.applicationDependency)"

    # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
    if ($settings.artifact -notlike "https://*") {
        $artifactUrl = DetermineArtifactUrl -settings $settings
        $version = $artifactUrl.Split('/')[4]
        Write-Host "Downloading artifacts from $($artifactUrl.Split('?')[0])"
        $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
        if (!($folders)) {
            Write-Error "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $repoSettingsFile."
        }
        $settings.artifact = $artifactUrl

        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            Write-Error "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }
    Write-Host "::endgroup::"

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

    Write-Host "Analyzing repository completed"
    $settings | Add-Member -NotePropertyName analyzeRepoCompleted -NotePropertyValue $true -Force
    return $settings
}

function Get-DependenciesAsTextString {
    [CmdletBinding()]
    Param(
        [array] $dependencies
    )
    return ($dependencies | ForEach-Object {
            $_.appFile
        }) -join ","
}