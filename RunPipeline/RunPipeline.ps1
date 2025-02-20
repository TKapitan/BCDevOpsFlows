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
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteSettings.Helper.ps1" -Resolve)
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

    # Trusted NuGet feeds not supported
    Write-Host "Trusted NuGet feeds not supported, skipping"
    $bcContainerHelperConfig.TrustedNuGetFeeds = @()

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
        Write-Host "::group::Locating previous release"
        Write-Host "Skipping upgrade validation - NOT YET IMPLEMENTED" # TODO Implement upgrade validation
        Write-Host "::endgroup::"
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

    Write-Host "OLD"
    Write-Host ($appFileJson | ConvertTo-Json -Depth 99)

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

    Write-Host "NEW"
    Write-Host ($appFileJson | ConvertTo-Json -Depth 99)
    Write-Error "STOP"

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