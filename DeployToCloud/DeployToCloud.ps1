Param(
    [Parameter(HelpMessage = "Name of environment to deploy to OR regex filter of environment names to deploy to", Mandatory = $true)]
    [string] $deployToEnvironmentsNameFilter,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD', 'Publish')]
    [string] $deploymentType = "CD"
)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeployToCloud.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper

$authContexts = $ENV:AL_AUTHCONTEXTS_INTERNAL | ConvertFrom-Json
$settings = $ENV:AL_SETTINGS | ConvertFrom-Json
$deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
$matchingEnvironments = @($deploymentEnvironments.GetEnumerator() | Where-Object { $_.Key -match $deployToEnvironmentsNameFilter } | Select-Object -ExpandProperty Key)
if ($matchingEnvironments.Count -eq 0) {
    throw "No environments found matching filter '$deployToEnvironmentsNameFilter'"
}
Write-Host "Found $($matchingEnvironments.Count) matching environments: $($matchingEnvironments -join ', ') for filter '$deployToEnvironmentsNameFilter'"

$noOfValidEnvironments = 0
$environmentUrls = @{} | ConvertTo-Json
foreach ($environmentName in $matchingEnvironments) {
    Write-Host "Processing environment: $environmentName"

    try {
        $deploymentSettings = $deploymentEnvironments."$environmentName"
        if (!$deploymentSettings) {
            throw "No deployment settings found for environment '$environmentName'."
        }
        OutputDebug -Message "DeploymentSettings for $environmentName : $($deploymentSettings | ConvertTo-Json -Depth 10)"
        $buildMode = $deploymentSettings.buildMode
        if ($null -eq $buildMode -or $buildMode -eq 'default') {
            $buildMode = ''
        }

        $authContext = $null
        $authContextVariableName = $deploymentSettings.authContextVariableName
        Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
        if (!$authContextVariableName) {
            Write-Error "No AuthContextVariableName specified for environment ($environmentName)."
        }
        if (!$authContexts."$authContextVariableName") {
            Write-Error "No AuthContext found for environment ($environmentName) with variable name ($authContextVariableName)."
        }
        try {
            $authContext = $authContexts."$authContextVariableName"
            $bcAuthContext = New-BcAuthContext -tenantID $authContext.tenantID -clientID $authContext.clientID -clientSecret $authContext.clientSecret
            if ($null -eq $bcAuthContext) {
                throw "Authentication failed"
            }
        }
        catch {
            Write-Host $_.Exception -ForegroundColor Red
            Write-Host $_.ScriptStackTrace
            Write-Host $_.PSMessageDetails
    
            Write-Error "Authentication failed. See previous lines for details."
        }

        $environmentUrl = "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.environmentName)"
    
        $environmentUrls | Add-Member -NotePropertyName $environmentName -NotePropertyValue $environmentUrl -Force
        OutputDebug -Message "Adding $environmentName with URL ($environmentUrl) to environmentUrls"
    
        Write-Host "EnvironmentUrl: $environmentUrl"
        $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$environmentUrl/deployment/url"
        if ($response.Status -eq "DoesNotExist") {
            Write-Warning "Environment with name $($deploymentSettings.environmentName) does not exist in the current authorization context. Skipping..."
            continue
        }
        if ($response.Status -ne "Ready") {
            Write-Warning "Environment with name $($deploymentSettings.environmentName) is not ready (Status is $($response.Status)). Skipping..."
            continue
        }
        $noOfValidEnvironments++

        # Deploy app
        $dependencies = @()
        $folders = @($settings.appFolders)
        foreach ($folderName in $folders) {
            $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "$folderName\app.json"
            $appJsonContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
            $appFilePath = Get-AppSourceFileLocation -appFile $appJsonContent

            Write-Host "Deploying app $($appJsonContent.name) by $($appJsonContent.publisher) to $($deploymentSettings.environmentName)"
            Write-Host "- $([System.IO.Path]::GetFileName($appFilePath))"

            if ($deploymentSettings.dependencyInstallMode -ne "ignore") {
                # NuGet dependencies
                $dependenciesFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".buildpackages"
                if (Test-Path $dependenciesFolder) {
                    $dependencies += Get-ChildItem -Path $dependenciesFolder -Directory | Where-Object { $_.Name -notlike 'Microsoft.*' } | ForEach-Object {
                        Get-ChildItem -Path $_.FullName -Filter "*.app" -Recurse | Select-Object -ExpandProperty FullName
                    }
                }
                # BCContainerHelper dependencies
                $dependenciesFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".buildartifacts\Dependencies"
                if (Test-Path $dependenciesFolder) {
                    $dependencies += Get-ChildItem -Path $dependenciesFolder -Filter "*.app" -Recurse | Select-Object -ExpandProperty FullName
                }
                Write-Host "Dependencies to $($deploymentSettings.dependencyInstallMode)"
                if ($dependencies) {
                    $dependencies | ForEach-Object {
                        Write-Host "- $([System.IO.Path]::GetFileName($_))"
                    }
                }
                else {
                    Write-Host "- None"
                }
            }

            $sandboxEnvironment = ($response.environmentType -eq 1)
            $scope = $deploymentSettings.Scope
            if ($null -eq $scope) {
                if ($settings.Type -eq 'AppSource App' -or ($sandboxEnvironment -and !($bcAuthContext.ClientSecret -or $bcAuthContext.ClientAssertion))) {
                    # Sandbox and not S2S -> use dev endpoint (Publish-BcContainerApp)
                    $scope = 'Dev'
                }
                else {
                    $scope = 'PTE'
                }
            }
            elseif (@('Dev', 'PTE') -notcontains $scope) {
                throw "Invalid Scope $($scope). Valid values are Dev and PTE."
            }
            if (!$sandboxEnvironment -and $deploymentType -eq 'CD' -and !($deploymentSettings.continuousDeployment)) {
                # Continuous deployment is undefined in settings - we will not deploy to production environments
                Write-Host "::Warning::Ignoring environment $($deploymentSettings.environmentName), which is a production environment"
            }
            else {
                if ($dependencies) {
                    InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $deploymentSettings.environmentName -Apps $dependencies -installMode $deploymentSettings.dependencyInstallMode
                }

                if ($scope -eq 'Dev') {
                    if (!$sandboxEnvironment) {
                        throw "Scope Dev is only valid for sandbox environments"
                    }
                    $parameters = @{
                        "bcAuthContext" = $bcAuthContext
                        "environment"   = $deploymentSettings.environmentName
                        "appFile"       = $appFilePath
                    }
                    if ($deploymentSettings.SyncMode) {
                        if (@('Add', 'ForceSync', 'Clean', 'Development') -notcontains $deploymentSettings.SyncMode) {
                            throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the development endpoint. Valid values are Add, ForceSync, Development and Clean."
                        }
                        Write-Host "Using $($deploymentSettings.SyncMode)"
                        $parameters += @{ "SyncMode" = $deploymentSettings.SyncMode }
                    }
                    Write-Host "Publishing apps using development endpoint"
                    Publish-BcContainerApp @parameters -useDevEndpoint -checkAlreadyInstalled -excludeRuntimePackages -replacePackageId
                }
                else {
                    # Use automation API for production environments (Publish-PerTenantExtensionApps)
                    $parameters = @{
                        "bcAuthContext" = $bcAuthContext
                        "environment"   = $deploymentSettings.environmentName
                        "appFiles"      = $appFilePath
                    }
                    if ($deploymentSettings.SyncMode) {
                        if (@('Add', 'ForceSync') -notcontains $deploymentSettings.SyncMode) {
                            throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the automation API. Valid values are Add and ForceSync."
                        }
                        Write-Host "Using $($deploymentSettings.SyncMode)"
                        $syncMode = $deploymentSettings.SyncMode
                        if ($syncMode -eq 'ForceSync') { $syncMode = 'Force' }
                        $parameters += @{ "SchemaSyncMode" = $syncMode }
                    }
                    Write-Host "Publishing apps using automation API"
                    Publish-PerTenantExtensionApps @parameters
                }
            }
        }
    }
    catch {
        Write-Host $_.Exception -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        Write-Host $_.PSMessageDetails

        Write-Error "Deployment to environment ($environmentName) failed. See previous lines for details."
    }
}

if ($noOfValidEnvironments -eq 0) {
    Write-Error "No valid environments found matching filter '$deployToEnvironmentsNameFilter'"
}

$ENV:AL_ENVIRONMENTURLS = $environmentUrls | ConvertTo-Json -Compress
Write-Host "##vso[task.setvariable variable=AL_ENVIRONMENTURLS;]$($environmentUrls | ConvertTo-Json -Compress)"
OutputDebug -Message "Set environment variable AL_ENVIRONMENTURLS to ($ENV:AL_ENVIRONMENTURLS)"
