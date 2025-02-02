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
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\AnalyzeRepository.Helper.ps1" -Resolve)

$containerBaseFolder = $null
try {
    OutputMessage "Using artifact $artifact"

    DownloadAndImportBcContainerHelper

    if ($isWindows) {
        # Pull docker image in the background
        OutputMessage "Pulling generic image in the background"
        $genericImageName = Get-BestGenericImageName
        OutputMessage " - name: $genericImageName"
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
        OutputMessage "Creating temp folder"
        New-Item -Path $containerBaseFolder -ItemType Directory | Out-Null
        Copy-Item -Path $ENV:BUILD_REPOSITORY_LOCALPATH -Destination $containerBaseFolder -Recurse -Force
        $baseFolder = Join-Path $containerBaseFolder (Get-Item -Path $ENV:BUILD_REPOSITORY_LOCALPATH).BaseName
    }

    if (!$ENV:AL_SETTINGS) {
        OutputError "ENV:AL_SETTINGS not found. The Read-Settings step must be run before this step."
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
            OutputMessage "Changing settings to use artifact = $artifact from $($settings.artifact)"
            $settings | Add-Member -NotePropertyName artifact -NotePropertyValue $artifact -Force
        }
        $settings = AnalyzeRepo -settings $settings @analyzeRepoParams
    }
    else {
        OutputMessage "Skipping AnalyzeRepo. Using existing settings from ENV:AL_SETTINGS"
    }

    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    if ((-not $settings.appFolders) -and (-not $settings.testFolders) -and (-not $settings.bcptTestFolders)) {
        OutputError "Repository is empty (no app or test folders found)"
        exit
    }

    # Trusted NuGet feeds not supported
    OutputMessage "Trusted NuGet feeds not supported, skipping"
    $bcContainerHelperConfig.TrustedNuGetFeeds = @()

    $installApps = $settings.installApps
    $installTestApps = $settings.installTestApps

    $installApps += $installAppsJson | ConvertFrom-Json
    $installApps += $settings.appDependencies
    OutputMessage "InstallApps: $installApps"

    $installTestApps += $installTestAppsJson | ConvertFrom-Json
    $installTestApps += $settings.testDependencies
    OutputMessage "InstallTestApps: $installTestApps"

    # Check if codeSignCertificateUrl+Password is used (and defined)
    if (!$settings.doNotSignApps -and $codeSignCertificateUrl -and $codeSignCertificatePassword -and !$settings.keyVaultCodesignCertificateName) {
        OutputMessageWarning -Message "Using the legacy CodeSignCertificateUrl and CodeSignCertificatePassword parameters. Consider using the new Azure Keyvault signing instead. Go to https://aka.ms/ALGoSettings#keyVaultCodesignCertificateName to find out more"
        $runAlPipelineParams += @{
            "CodeSignCertPfxFile"     = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -string $codeSignCertificatePassword
        }
    }
    if ($applicationInsightsConnectionString) {
        $runAlPipelineParams += @{
            "applicationInsightsConnectionString" = $applicationInsightsConnectionString
        }
    }

    if ($keyVaultCertificateUrl -and $keyVaultCertificatePassword -and $keyVaultClientId) {
        $runAlPipelineParams += @{
            "KeyVaultCertPfxFile"     = $keyVaultCertificateUrl
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -string $keyVaultCertificatePassword
            "keyVaultClientId"        = $keyVaultClientId
        }
    }

    $previousApps = @()
    if (!$settings.skipUpgrade) {
        OutputMessage "::group::Locating previous release"
        OutputMessage "Skipping upgrade validation - NOT YET IMPLEMENTED" # TODO Implement upgrade validation
        OutputMessage "::endgroup::"
    }

    $additionalCountries = $settings.additionalCountries

    $imageName = $settings.cacheImageName
    if ($imageName) {
        OutputMessage "::group::Flush ContainerHelper Cache"
        Flush-ContainerHelperCache -cache 'all,exitedcontainers' -keepdays $settings.cacheKeepDays
        OutputMessage "::endgroup::"
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($settings.versioningStrategy -eq -1) {
        OutputMessage "Applying versioning strategy -1 ($($settings.artifact))"
        $artifactVersion = [Version]$settings.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif ($settings.versioningStrategy -eq 10) {
        # The app.json version is applied in Run-AlPipeline
        OutputMessage "Applying versioning strategy 10 ($($settings.appJsonVersion))"
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
    OutputMessage "##vso[task.setvariable variable=AL_CONTAINERNAME;]$containerName"
    OutputMessage "Set environment variable AL_CONTAINERNAME to ($ENV:AL_CONTAINERNAME)"

    Set-Location $baseFolder
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $scriptsFolderName "$scriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            OutputMessage "Add override for $scriptName"
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
            OutputMessage "Adding Import Test Data override"
            OutputMessage "Configured config packages:"
            $settings.Keys | Where-Object { $_ -like 'configPackages*' } | ForEach-Object {
                OutputMessage "- $($_):"
                $settings."$_" | ForEach-Object {
                    OutputMessage "  - $_"
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
                        OutputMessage "Importing config packages from $prop"
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
    "enableCodeAnalyzersOnTestApps",
    "useCompilerFolder" | ForEach-Object {
        if ($settings."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    if ($buildMode -eq 'Translated') {
        if ($runAlPipelineParams.Keys -notcontains 'features') {
            $runAlPipelineParams["features"] = @()
        }
        OutputMessage "Adding translationfile feature"
        $runAlPipelineParams["features"] += "translationfile"
    }

    if ($runAlPipelineParams.Keys -notcontains 'preprocessorsymbols') {
        $runAlPipelineParams["preprocessorsymbols"] = @()
    }

    if ($settings.ContainsKey('preprocessorSymbols')) {
        OutputMessage "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $runAlPipelineParams["preprocessorsymbols"] += $settings.preprocessorSymbols
    }

    $workflowName = "$ENV:BUILD_TRIGGEREDBY_DEFINITIONNAME".Trim()
    OutputMessage "Invoke Run-AlPipeline with buildmode $buildMode"
    Run-AlPipeline @runAlPipelineParams `
        -accept_insiderEula `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $settings.artifact.replace('{INSIDERSASTOKEN}', '') `
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
    OutputMessage "Copy artifacts and build output back from build container to $testResultsDestinationFolder"
    Copy-Item -Path (Join-Path $baseFolder ".buildartifacts") -Destination $testResultsDestinationFolder -Recurse -Force
    Copy-Item -Path (Join-Path $baseFolder ".output") -Destination $testResultsDestinationFolder -Recurse -Force
    Copy-Item -Path (Join-Path $baseFolder "testResults*.xml") -Destination $testResultsDestinationFolder
    Copy-Item -Path (Join-Path $baseFolder "bcptTestResults*.json") -Destination $testResultsDestinationFolder
    Copy-Item -Path $buildOutputFile -Destination $testResultsDestinationFolder -Force -ErrorAction SilentlyContinue
    Copy-Item -Path $containerEventLogFile -Destination $testResultsDestinationFolder -Force -ErrorAction SilentlyContinue

    $ENV:TestResults = $allTestResults
    OutputMessage "##vso[task.setvariable variable=TestResults]$allTestResults"
    OutputMessage "Set environment variable TestResults to ($ENV:TestResults)"
}
catch {
    OutputMessage $_.Exception
    OutputMessage $_.ScriptStackTrace
    OutputMessage $_.PSMessageDetails

    OutputError "Error running pipeline. See previous lines for details."
}
finally {
    try {
        if (Test-BcContainer -containerName $containerName) {
            OutputMessage "Get Event Log from container"
            $eventlogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
            Copy-Item -Path $eventLogFile -Destination $containerEventLogFile
        }
    }
    catch {
        OutputError "Error getting event log from container: $($_.Exception.Message)"
    }
}