
. (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineArtifactUrl\DetermineArtifactUrl.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "Output.Helper.ps1" -Resolve)

function AnalyzeRepo {
    [CmdletBinding()]
    Param(
        [hashTable] $settings,
        [switch] $skipAppsInPreview,
        [version] $minBcVersion = [version]'0.0.0.0'
    )
    $settings = $settings | Copy-HashTable

    if (!$runningLocal) {
        OutputMessage "::group::Analyzing repository"
    }

    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null

    OutputMessage "Checking type"
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
            OutputError "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $repoSettingsFile"
        }
    }
    else {
        OutputError "The type, specified in $repoSettingsFile, must be either 'PTE' or 'AppSource App'. It is '$($settings.type)'."
    }

    OutputMessage "Checking appFolders, testFolders and bcptTestFolders"
    $dependencies = [ordered]@{}
    $appIdFolders = [ordered]@{}
    foreach ($folderTypeNumber in 1..3) {
        $appFolder = $folderTypeNumber -eq 1
        $testFolder = $folderTypeNumber -eq 2
        $bcptTestFolder = $folderTypeNumber -eq 3
        OutputMessage "Reading apps #$folderTypeNumber"
        
        if ($appFolder) {
            $folders = @($settings.appFolders)
            $descr = "App folder"
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
            $descr = "Test folder"
        }
        elseif ($bcptTestFolder) {
            $folders = @($settings.bcptTestFolders)
            $descr = "Bcpt Test folder"
        }
        else {
            OutputError "Internal error"
        }

        $folders | ForEach-Object {
            $folderName = $_
            $folder = "$ENV:PIPELINE_WORKSPACE/App/$folderName"
            OutputMessage "Analyzing dependencies for '$folderName' in '$folder'"
            $appJsonFile = Join-Path $folder "app.json"
            $bcptSuiteFile = Join-Path $folder "bcptSuite.json"
            $enumerate = $true

            # Check if there are any folders matching $folder
            if (!(Get-Item $folder | Where-Object { $_ -is [System.IO.DirectoryInfo] })) {
                OutputMessageWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not exist" 
            }
            elseif (-not (Test-Path $appJsonFile -PathType Leaf)) {
                OutputMessageWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain the source code for an app (no app.json file)" 
            }
            elseif ($bcptTestFolder -and (-not (Test-Path $bcptSuiteFile -PathType Leaf))) {
                OutputMessageWarning -Message "$descr $folderName, specified in $repoSettingsFile, does not contain a BCPT Suite (bcptSuite.json)" 
                $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName })
                $enumerate = $false
            }

            if ($enumerate) {
                if ($dependencies.Contains($folderName)) {
                    OutputError "$descr $folderName, specified in $repoSettingsFile, is specified more than once."
                }
                $dependencies.Add($folderName, @())
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    if ($appIdFolders.Contains($appJson.Id)) {
                        OutputError "$descr $folderName contains a duplicate AppId ($($appIdFolders."$($appJson.Id)"))"
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

                        $foundAppDependencies = Get-AppDependencies -appArtifactSharedFolder $settings.appArtifactSharedFolder -appJsonFilePath $appJsonFile -minBcVersion $minBcVersion -includeAppsInPreview !$skipAppsInPreview
                        if ($foundAppDependencies) {
                            $settings.appDependencies += $foundAppDependencies
                        }
                        OutputMessage "Adding newly found APP dependencies: $($settings.appDependencies)"
                    }
                    elseif ($testFolder) {
                        $foundTestDependencies = Get-AppDependencies -appArtifactSharedFolder $settings.appArtifactSharedFolder -appJsonFilePath $appJsonFile -excludeExtensionID $mainAppId -minBcVersion $minBcVersion -includeAppsInPreview !$skipAppsInPreview
                        if ($foundTestDependencies) {
                            $settings.testDependencies += $foundTestDependencies
                        }
                        OutputMessage "Adding newly found TEST dependencies: $($settings.testDependencies)"
                    }
                }
                catch {
                    OutputMessage $_.Exception
                    OutputMessage $_.ScriptStackTrace
                    OutputMessage $_.PSMessageDetails

                    OutputError "$descr $folderName, specified in $repoSettingsFile, contains a corrupt app.json file. See the error details above."
                }
            }
        }
    }
    OutputMessage "App.json version $($settings.appJsonVersion)"
    OutputMessage "Application Dependency $($settings.applicationDependency)"

    # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
    if ($settings.artifact -notlike "https://*") {
        $artifactUrl = DetermineArtifactUrl -settings $settings
        $version = $artifactUrl.Split('/')[4]
        OutputMessage "Downloading artifacts from $($artifactUrl.Split('?')[0])"
        $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
        if (-not ($folders)) {
            OutputError "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $repoSettingsFile."
        }
        $settings.artifact = $artifactUrl

        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            OutputError "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }

    OutputMessage "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    # TODO review design
    # $settings.appDependencies + $settings.testDependencies | ForEach-Object {
    #     $dep = $_
    #     if ($dep.GetType().Name -eq "OrderedDictionary") {
    #         if ($testRunnerApps.Contains($dep.id)) { $settings.installTestRunner = $true }
    #         if ($testFrameworkApps.Contains($dep.id)) { $settings.installTestFramework = $true }
    #         if ($testLibrariesApps.Contains($dep.id)) { $settings.installTestLibraries = $true }
    #         if ($performanceToolkitApps.Contains($dep.id)) { $settings.installPerformanceToolkit = $true }
    #     }
    # }

    if (!$runningLocal) {
        OutputMessage "::endgroup::"
    }

    if (!$settings.doNotRunBcptTests -and -not $settings.bcptTestFolders) {
        OutputMessage "No performance test apps found in bcptTestFolders in $repoSettingsFile"
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and -not $settings.testFolders) {
        OutputMessageWarning -Message "No test apps found in testFolders in $repoSettingsFile" 
        $settings.doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
        OutputMessageWarning -Message "No apps found in appFolders in $repoSettingsFile" 
    }

    OutputMessage "Analyzing repository completed"
    $settings | Add-Member -NotePropertyName analyzeRepoCompleted -NotePropertyValue $true -Force
    return $settings
}
