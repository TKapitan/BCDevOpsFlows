Param(
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '[]',
    [Parameter(HelpMessage = "A JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '[]',
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $skipAppsInPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\RunPipeline\RunPipeline.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\ApplyAppJsonUpdates.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\AnalyzeRepository.Helper.ps1" -Resolve)

$containerBaseFolder = $null
try {
    Write-Host "Using artifact $artifact"

    DownloadAndImportBcContainerHelper

    if ($isWindows) {
        # Pull docker image in the background
        Write-Host "Pulling generic image in the background"
        $genericImageName = Get-BestGenericImageName
        Write-Host " - name: $genericImageName"
        Start-Job -ScriptBlock {
            docker pull --quiet $using:genericImageName
        } | Out-Null
    }

    $containerName = GetContainerName

    $runAlPipelineParams = @{
        "sourceRepositoryUrl" = "$ENV:BUILD_REPOSITORY_URI"
        "sourceCommit"        = $ENV:BUILD_SOURCEVERSION
        "buildBy"             = "BCDevOpsFlows"
    }
    $baseFolder = $ENV:BUILD_REPOSITORY_LOCALPATH
    if ($bcContainerHelperConfig.useVolumes -and $bcContainerHelperConfig.hostHelperFolder -eq "HostHelperFolder") {
        $allVolumes = "{$(((docker volume ls --format "'{{.Name}}': '{{.Mountpoint}}'") -join ",").Replace('\','\\').Replace("'",'"'))}" | ConvertFrom-Json | ConvertTo-HashTable
        $containerBaseFolder = Join-Path $allVolumes.hostHelperFolder $containerName
        if (Test-Path $containerBaseFolder) {
            Remove-Item -Path $containerBaseFolder -Recurse -Force
        }
        Write-Host "Creating temp folder"
        New-Item -Path $containerBaseFolder -ItemType Directory | Out-Null
        Copy-Item -Path $ENV:BUILD_REPOSITORY_LOCALPATH -Destination $containerBaseFolder -Recurse -Force
        $baseFolder = Join-Path $containerBaseFolder (Get-Item -Path $ENV:BUILD_REPOSITORY_LOCALPATH).BaseName
    }

    if (!$ENV:AL_SETTINGS) {
        Write-Error "ENV:AL_SETTINGS not found. The Read-Settings step must be run before this step."
    }
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    if (!$settings.analyzeRepoCompleted -or ($artifact -and ($artifact -ne $settings.artifact))) {
        $analyzeRepoParams = @{}
        if ($skipAppsInPreview) {
            $analyzeRepoParams += @{
                "skipAppsInPreview" = $true
            }
        }

        if ($artifact) {
            Write-Host "Changing settings to use artifact = $artifact from $($settings.artifact)"
            $settings | Add-Member -NotePropertyName artifact -NotePropertyValue $artifact -Force
        }
        $settings = AnalyzeRepo -settings $settings @analyzeRepoParams
    }
    else {
        Write-Host "Skipping AnalyzeRepo. Using existing settings from ENV:AL_SETTINGS"
    }

    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    if ((-not $settings.appFolders) -and (-not $settings.testFolders) -and (-not $settings.bcptTestFolders)) {
        Write-Error "Repository is empty (no app or test folders found)"
        exit
    }

    $bcContainerHelperConfig.TrustedNuGetFeeds = @()
    if ($ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL) {
        $trustedNuGetFeeds = $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL | ConvertFrom-Json
        if ($trustedNuGetFeeds -and $trustedNuGetFeeds.Count -gt 0) {
            Write-Host "Adding trusted NuGet feeds from environment variable"
            $trustedNuGetFeeds = @($trustedNuGetFeeds | ForEach-Object {
                $feed = $_
                OutputDebug -Message "Adding trusted NuGet feed $($feed.serverUrl)"
                [PSCustomObject]@{
                    url   = $feed.serverUrl
                    token = $feed.token
                }
            })
        }
    }
    if ($settings.trustMicrosoftNuGetFeeds) {
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{
            "url"   = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
            "token" = ''
        })
    }

    # PS7 builds do not support (unstable) SSL for WinRM in some Azure VMs
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $bcContainerHelperConfig.useSslForWinRmSession = $false
    }

    $installApps = $settings.installApps
    $installTestApps = $settings.installTestApps

    $installApps += $installAppsJson | ConvertFrom-Json
    $installApps += $settings.appDependencies
    Write-Host "InstallApps: $installApps"

    $installTestApps += $installTestAppsJson | ConvertFrom-Json
    $installTestApps += $settings.testDependencies
    Write-Host "InstallTestApps: $installTestApps"

    if ($applicationInsightsConnectionString) {
        $runAlPipelineParams += @{
            "applicationInsightsConnectionString" = $applicationInsightsConnectionString
        }
    }

    $previousApps = @()
    if (!$settings.skipUpgrade) {
        if ($settings.previousRelease) {
            Write-Host "Using $($settings.previousRelease) as previous release"
            $previousApps = $settings.previousRelease
        }
        else {
            OutputWarning -message "No previous release found"
        }
    }

    $additionalCountries = $settings.additionalCountries

    $imageName = $settings.cacheImageName
    if ($imageName) {
        Write-Host "::group::Flush ContainerHelper Cache"
        Flush-ContainerHelperCache -cache 'all,exitedcontainers' -keepdays $settings.cacheKeepDays
        Write-Host "::endgroup::"
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($settings.versioningStrategy -eq -1) {
        Write-Host "Applying versioning strategy -1 ($($settings.artifact))"
        $artifactVersion = [Version]$settings.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif ($settings.versioningStrategy -eq 10) {
        # The app.json version is applied in Run-AlPipeline
        Write-Host "Applying versioning strategy 10 ($($settings.appJsonVersion))"
        $runAlPipelineParams += @{
            "appVersion" = $null
        }
        $appBuild = $null
        $appRevision = $null
    }
    elseif (($settings.versioningStrategy -band 16) -eq 16) {
        $runAlPipelineParams += @{
            "appVersion" = $settings.repoVersion
        }
    }

    $buildArtifactFolder = Join-Path $baseFolder ".buildartifacts"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

    $allTestResults = "testresults*.xml"
    $testResultsFile = Join-Path $baseFolder "TestResults.xml"
    $testResultsFiles = Join-Path $baseFolder $allTestResults
    if (Test-Path $testResultsFiles) {
        Remove-Item $testResultsFiles -Force
    }

    $buildOutputFile = Join-Path $baseFolder "BuildOutput.txt"
    $containerEventLogFile = Join-Path $baseFolder "ContainerEventLog.evtx"

    $ENV:AL_CONTAINERNAME = $containerName
    Write-Host "##vso[task.setvariable variable=AL_CONTAINERNAME;]$containerName"
    OutputDebug -Message "Set environment variable AL_CONTAINERNAME to ($ENV:AL_CONTAINERNAME)"

    Set-Location $baseFolder
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $scriptsFolderName "$scriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $scriptName"
            Trace-Information -Message "Using override for $scriptName"

            $runAlPipelineParams += @{
                "$scriptName" = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }

    if ($runAlPipelineParams.Keys -notcontains 'RemoveBcContainer') {
        $runAlPipelineParams += @{
            "RemoveBcContainer" = {
                Param([Hashtable]$parameters)
                Remove-BcContainerSession -containerName $parameters.ContainerName -killPsSessionProcess
                Remove-BcContainer @parameters
            }
        }
    }

    if ($runAlPipelineParams.Keys -notcontains 'ImportTestDataInBcContainer') {
        if (($settings.configPackages) -or ($settings.Keys | Where-Object { $_ -like 'configPackages.*' })) {
            Write-Host "Adding Import Test Data override"
            Write-Host "Configured config packages:"
            $settings.Keys | Where-Object { $_ -like 'configPackages*' } | ForEach-Object {
                Write-Host "- $($_):"
                $settings."$_" | ForEach-Object {
                    Write-Host "  - $_"
                }
            }
            $runAlPipelineParams += @{
                "ImportTestDataInBcContainer" = {
                    Param([Hashtable]$parameters)
                    $country = Get-BcContainerCountry -containerOrImageName $parameters.containerName
                    $prop = "configPackages.$country"
                    if ($settings.Keys -notcontains $prop) {
                        $prop = "configPackages"
                    }
                    if ($settings."$prop") {
                        Write-Host "Importing config packages from $prop"
                        $settings."$prop" | ForEach-Object {
                            $configPackage = $_.Split(',')[0].Replace('{COUNTRY}', $country)
                            $packageId = $_.Split(',')[1]
                            UploadImportAndApply-ConfigPackageInBcContainer `
                                -containerName $parameters.containerName `
                                -companyName $settings.companyName `
                                -Credential $parameters.credential `
                                -Tenant $parameters.tenant `
                                -ConfigPackage $configPackage `
                                -PackageId $packageId
                        }
                    }
                }
            }
        }
    }

    if (($bcContainerHelperConfig.ContainsKey('TrustedNuGetFeeds') -and ($bcContainerHelperConfig.TrustedNuGetFeeds.Count -gt 0)) -and ($runAlPipelineParams.Keys -notcontains 'InstallMissingDependencies')) {
        if ($githubPackagesContext) {
            $gitHubPackagesCredential = $gitHubPackagesContext | ConvertFrom-Json
        }
        else {
            $gitHubPackagesCredential = [PSCustomObject]@{ "serverUrl" = ''; "token" = '' }
        }
        $runAlPipelineParams += @{
            "InstallMissingDependencies" = {
                Param([Hashtable]$parameters)
                $parameters.missingDependencies | ForEach-Object {
                    $appid = $_.Split(':')[0]
                    $appName = $_.Split(':')[1]
                    $version = $appName.SubString($appName.LastIndexOf('_') + 1)
                    $version = [System.Version]$version.SubString(0, $version.Length - 4)
                    $publishParams = @{
                        "nuGetServerUrl" = $gitHubPackagesCredential.serverUrl
                        "nuGetToken"     = $gitHubPackagesCredential.token
                        "packageName"    = $appId
                        "version"        = $version
                    }
                    if ($parameters.ContainsKey('CopyInstalledAppsToFolder')) {
                        $publishParams += @{
                            "CopyInstalledAppsToFolder" = $parameters.CopyInstalledAppsToFolder
                        }
                    }
                    if ($parameters.ContainsKey('containerName')) {
                        Publish-BcNuGetPackageToContainer -containerName $parameters.containerName -tenant $parameters.tenant -skipVerification -appSymbolsFolder $parameters.appSymbolsFolder @publishParams -ErrorAction SilentlyContinue
                    }
                    else {
                        Download-BcNuGetPackageToFolder -folder $parameters.appSymbolsFolder @publishParams | Out-Null
                    }
                }
            }
        }
    }

    Write-Error "DEBUG STOP"

    Update-AppJson -settings $settings

    "enableTaskScheduler",
    "assignPremiumPlan",
    "doNotBuildTests",
    "doNotRunTests",
    "doNotRunBcptTests",
    "doNotRunPageScriptingTests",
    "doNotPublishApps",
    "installTestRunner",
    "installTestFramework",
    "installTestLibraries",
    "installPerformanceToolkit",
    "enableCodeCop",
    "enableAppSourceCop",
    "enablePerTenantExtensionCop",
    "enableUICop",
    "enableCodeAnalyzersOnTestApps" | ForEach-Object {
        if ($settings."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    if ($buildMode -eq 'Translated') {
        if ($runAlPipelineParams.Keys -notcontains 'features') {
            $runAlPipelineParams["features"] = @()
        }
        Write-Host "Adding translationfile feature"
        $runAlPipelineParams["features"] += "translationfile"
    }

    if ($runAlPipelineParams.Keys -notcontains 'preprocessorsymbols') {
        $runAlPipelineParams["preprocessorsymbols"] = @()
    }

    if ($settings.ContainsKey('preprocessorSymbols')) {
        Write-Host "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $runAlPipelineParams["preprocessorsymbols"] += $settings.preprocessorSymbols
    }

    $workflowName = "$ENV:BUILD_TRIGGEREDBY_DEFINITIONNAME".Trim()
    Write-Host "Invoke Run-AlPipeline with buildmode $buildMode"
    Run-AlPipeline @runAlPipelineParams `
        -accept_insiderEula `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $settings.artifact `
        -vsixFile $settings.vsixFile `
        -companyName $settings.companyName `
        -memoryLimit $settings.memoryLimit `
        -baseFolder $baseFolder `
        -sharedFolder $sharedFolder `
        -licenseFile $licenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -installOnlyReferencedApps:$settings.installOnlyReferencedApps `
        -generateDependencyArtifact `
        -updateDependencies:$settings.updateDependencies `
        -previousApps $previousApps `
        -appFolders $settings.appFolders `
        -testFolders $settings.testFolders `
        -bcptTestFolders $settings.bcptTestFolders `
        -pageScriptingTests $settings.pageScriptingTests `
        -restoreDatabases $settings.restoreDatabases `
        -buildOutputFile $buildOutputFile `
        -containerEventLogFile $containerEventLogFile `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -customCodeCops $settings.customCodeCops `
        -failOn $settings.failOn `
        -treatTestFailuresAsWarnings:$settings.treatTestFailuresAsWarnings `
        -rulesetFile $settings.rulesetFile `
        -enableExternalRulesets:$settings.enableExternalRulesets `
        -appSourceCopMandatoryAffixes $settings.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -obsoleteTagMinAllowedMajorMinor $settings.obsoleteTagMinAllowedMajorMinor `
        -buildArtifactFolder $buildArtifactFolder `
        -pageScriptingTestResultsFile (Join-Path $buildArtifactFolder 'PageScriptingTestResults.xml') `
        -pageScriptingTestResultsFolder (Join-Path $buildArtifactFolder 'PageScriptingTestResultDetails') `
        -CreateRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild  `
        -appRevision $appRevision `
        -uninstallRemovedApps

    $testResultsDestinationFolder = $ENV:COMMON_TESTRESULTSDIRECTORY
    Write-Host "Copy artifacts and build output back from build container to $testResultsDestinationFolder"
    Copy-Item -Path (Join-Path $baseFolder ".buildartifacts") -Destination $testResultsDestinationFolder -Recurse -Force
    Copy-Item -Path (Join-Path $baseFolder ".output") -Destination $testResultsDestinationFolder -Recurse -Force
    Copy-Item -Path (Join-Path $baseFolder "testResults*.xml") -Destination $testResultsDestinationFolder
    Copy-Item -Path (Join-Path $baseFolder "bcptTestResults*.json") -Destination $testResultsDestinationFolder
    Copy-Item -Path $buildOutputFile -Destination $testResultsDestinationFolder -Force -ErrorAction SilentlyContinue
    Copy-Item -Path $containerEventLogFile -Destination $testResultsDestinationFolder -Force -ErrorAction SilentlyContinue

    $ENV:TestResults = $allTestResults
    Write-Host "##vso[task.setvariable variable=TestResults]$allTestResults"
    OutputDebug -Message "Set environment variable TestResults to ($ENV:TestResults)"
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Error running pipeline. See previous lines for details."
}
finally {
    try {
        if (Test-BcContainer -containerName $containerName) {
            Write-Host "Get Event Log from container"
            $eventlogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
            Copy-Item -Path $eventLogFile -Destination $containerEventLogFile
        }
    }
    catch {
        Write-Error "Error getting event log from container: $($_.Exception.Message)"
    }
}