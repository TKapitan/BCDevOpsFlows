Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '[]',
    [Parameter(HelpMessage = "A JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '[]',
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [string] $skipAppsInPreview = $false
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\Troubleshooting\Troubleshooting.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\RunPipeline\RunPipeline.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AnalyzeRepository\AnalyzeRepository.ps1" -Resolve)

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

    $workflowName = "$ENV:BUILD_TRIGGEREDBY_DEFINITIONNAME".Trim()
    Write-Host "use settings and secrets"
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
    # ENV:Secrets is not set when running Pull_Request trigger
    if ($env:Secrets) {
        $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $secrets = @{}
    }

    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl', 'codeSignCertificateUrl', '*codeSignCertificatePassword', 'keyVaultCertificateUrl', '*keyVaultCertificatePassword', 'keyVaultClientId', 'applicationInsightsConnectionString' | ForEach-Object {
        # Secrets might not be read during Pull Request runs
        if ($secrets.Keys -contains $_) {
            $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $value = ""
        }
        # Secrets preceded by an asterisk are returned encrypted.
        # Variable name should not include the asterisk
        Set-Variable -Name $_.TrimStart('*') -Value $value
    }

    $analyzeRepoParams = @{}

    if ($artifact) {
        # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
        $settings.artifact = $artifact
        if ($artifact -like "https://*") {
            $analyzeRepoParams += @{
                "doNotCheckArtifactSetting" = $true
            }
        }
    }

    $settings = AnalyzeRepo -settings $settings -skipAppsInPreview $skipAppsInPreview 

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

    # Check if codeSignCertificateUrl+Password is used (and defined)
    if (!$settings.doNotSignApps -and $codeSignCertificateUrl -and $codeSignCertificatePassword -and !$settings.keyVaultCodesignCertificateName) {
        OutputWarning -Message "Using the legacy CodeSignCertificateUrl and CodeSignCertificatePassword parameters. Consider using the new Azure Keyvault signing instead. Go to https://aka.ms/ALGoSettings#keyVaultCodesignCertificateName to find out more"
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
        Write-Host "::group::Locating previous release"
        Write-Host "Skipping upgrade validation - NOT YET IMPLEMENTED" # TODO Implement upgrade validation
        # try {
        #     $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $ENV:GITHUB_REF_NAME
        #     if ($latestRelease) {
        #         Write-Host "Using $($latestRelease.name) (tag $($latestRelease.tag_name)) as previous release"
        #         $artifactsFolder = Join-Path $baseFolder "artifacts"
        #         New-Item $artifactsFolder -ItemType Directory | Out-Null
        #         DownloadRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder -mask "Apps"
        #         $previousApps += @(Get-ChildItem -Path $artifactsFolder | ForEach-Object { $_.FullName })
        #     }
        #     else {
        #         OutputWarning -Message "No previous release found"
        #     }
        # }
        # catch {
        #     OutputError -Message "Error trying to locate previous release. Error was $($_.Exception.Message)"
        #     exit
        # }
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

    $ENV:CONTAINERNAME = $containerName
    Write-Host "##vso[task.setvariable variable=containerName;]$containerName"
    Write-Host "Set environment variable containerName to ($ENV:CONTAINERNAME)"

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

    Write-Host "Invoke Run-AlPipeline with buildmode $buildMode"
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

    if ($containerBaseFolder) {
        Write-Host "Copy artifacts and build output back from build container"
        $destFolder = $ENV:BUILD_REPOSITORY_LOCALPATH
        Copy-Item -Path (Join-Path $baseFolder ".buildartifacts") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $baseFolder ".output") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $baseFolder "testResults*.xml") -Destination $destFolder
        Copy-Item -Path (Join-Path $baseFolder "bcptTestResults*.json") -Destination $destFolder
        Copy-Item -Path $buildOutputFile -Destination $destFolder -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $containerEventLogFile -Destination $destFolder -Force -ErrorAction SilentlyContinue
    }
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