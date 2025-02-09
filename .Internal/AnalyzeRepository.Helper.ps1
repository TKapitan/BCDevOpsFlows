
. (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineArtifactUrl\DetermineArtifactUrl.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "FindDependencies.Helper.ps1" -Resolve)

function AnalyzeRepo {
    [CmdletBinding()]
    Param(
        [hashTable] $settings,
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
        if ($settings.enableAppSourceCop -and (-not ($settings.appSourceCopMandatoryAffixes))) {
            Write-Error "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $repoSettingsFile"
        }
        if (!$settings.Contains('removeInternalsVisibleTo')) {
            $settings.Add('removeInternalsVisibleTo', $true)
        }
    }
    else {
        Write-Error "The type, specified in $repoSettingsFile, must be either 'PTE' or 'AppSource App'. It is '$($settings.type)'."
    }

    Write-Host "Checking appFolders, testFolders and bcptTestFolders"
    $dependencies = [ordered]@{}
    $appIdFolders = [ordered]@{}
    foreach ($folderTypeNumber in 1..3) {
        $appFolder = $folderTypeNumber -eq 1
        $testFolder = $folderTypeNumber -eq 2
        $bcptTestFolder = $folderTypeNumber -eq 3
        Write-Host "Reading apps #$folderTypeNumber"
        
        if ($appFolder) {
            $folders = [System.Collections.ArrayList]@($settings.appFolders)
            $descr = "App folder"
        }
        elseif ($testFolder) {
            $folders = [System.Collections.ArrayList]@($settings.testFolders)
            $descr = "Test folder"
        }
        elseif ($bcptTestFolder) {
            $folders = [System.Collections.ArrayList]@($settings.bcptTestFolders)
            $descr = "Bcpt Test folder"
        }
        else {
            Write-Error "Internal error"
        }
        $folders | ForEach-Object {
            $folderName = $_
            $folder = "$ENV:PIPELINE_WORKSPACE/App/$folderName"
            Write-Host "Analyzing dependencies for '$folderName' in '$folder'"
            $appJsonFile = Join-Path $folder "app.json"
            $bcptSuiteFile = Join-Path $folder "bcptSuite.json"
            $enumerate = $true

            # Check if there are any folders matching $folder
            if (!(Get-Item $folder | Where-Object { $_ -is [System.IO.DirectoryInfo] })) {
                OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not exist" 
            }
            elseif (-not (Test-Path $appJsonFile -PathType Leaf)) {
                OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain the source code for an app (no app.json file)" 
            }
            elseif ($bcptTestFolder -and (-not (Test-Path $bcptSuiteFile -PathType Leaf))) {
                OutputWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain a BCPT Suite (bcptSuite.json)" 
                $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName })
                $enumerate = $false
            }

            if ($enumerate) {
                if ($dependencies.Contains($folderName)) {
                    Write-Error "$descr $folderName, specified in $repoSettingsFile, is specified more than once."
                }
                $dependencies.Add($folderName, @())
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    if ($appIdFolders.Contains($appJson.Id)) {
                        Write-Error "$descr $folderName contains a duplicate AppId ($($appIdFolders."$($appJson.Id)"))"
                    }
                    $appIdFolders.Add($appJson.Id, $folderName)
                    if ($appJson.PSObject.Properties.Name -eq 'Dependencies') {
                        $appJson.dependencies | ForEach-Object {
                            if ($_.PSObject.Properties.Name -eq "AppId") {
                                $id = $_.AppId
                            }
                            else {
                                $id = $_.Id
                            }
                            if ($id -eq $applicationAppId) {
                                if ([Version]$_.Version -gt [Version]$settings.applicationDependency) {
                                    $settings.applicationDependency = $appDep
                                }
                            }
                            else {
                                $dependencies."$folderName" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
                            }
                        }
                    }
                    if ($appJson.PSObject.Properties.Name -eq 'Application') {
                        $appDep = $appJson.application
                        if ([Version]$appDep -gt [Version]$settings.applicationDependency) {
                            $settings.applicationDependency = $appDep
                        }
                    }
                    if ($appFolder) {
                        $mainAppId = $appJson.id
                        if ($appJson.PSObject.Properties.Name -eq 'Version') {
                            $settings.appJsonVersion = $appJson.version
                        }

                        $foundAppDependencies = @(Get-AppDependencies -appJsonFilePath $appJsonFile -minBcVersion $minBcVersion -includeAppsInPreview !$skipAppsInPreview)
                        if ($foundAppDependencies) {
                            $settings.appDependencies += Get-DependenciesAsTextString -dependencies $foundAppDependencies
                        }
                        Write-Host "Adding newly found APP dependencies: $($settings.appDependencies)"
                    }
                    elseif ($testFolder) {
                        $foundTestDependencies = @(Get-AppDependencies -appJsonFilePath $appJsonFile -excludeExtensionID $mainAppId -minBcVersion $minBcVersion -includeAppsInPreview !$skipAppsInPreview)
                        if ($foundTestDependencies) {
                            $settings.testDependencies += Get-DependenciesAsTextString -dependencies $foundTestDependencies
                        }
                        Write-Host "Adding newly found TEST dependencies: $($settings.testDependencies)"
                    }
                }
                catch {
                    Write-Host $_.Exception -ForegroundColor Red
                    Write-Host $_.ScriptStackTrace
                    Write-Host $_.PSMessageDetails

                    Write-Error "$descr $folderName, specified in $repoSettingsFile, contains a corrupt app.json file. See the error details above."
                }
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
        if (-not ($folders)) {
            Write-Error "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $repoSettingsFile."
        }
        $settings.artifact = $artifactUrl

        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            Write-Error "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }
    Write-Host "::endgroup::"

    if (!$settings.doNotRunBcptTests -and -not $settings.bcptTestFolders) {
        Write-Host "No performance test apps found in bcptTestFolders in $repoSettingsFile"
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and -not $settings.testFolders) {
        OutputWarning -Message "No test apps found in testFolders in $repoSettingsFile" 
        $settings.doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
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