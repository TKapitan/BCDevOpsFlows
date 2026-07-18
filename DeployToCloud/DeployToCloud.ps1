Param(
    [Parameter(HelpMessage = "Name of environment to deploy to OR regex filter of environment names to deploy to", Mandatory = $true)]
    [string] $deployToEnvironmentsNameFilter,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD', 'Publish')]
    [string] $deploymentType = "CD"
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeployToCloud.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BcCloud.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    if ([string]::IsNullOrWhiteSpace($ENV:AL_AUTHCONTEXTS_INTERNAL)) {
        throw "AL_AUTHCONTEXTS_INTERNAL is required and must contain valid JSON."
    }
    if ([string]::IsNullOrWhiteSpace($ENV:AL_SETTINGS)) {
        throw "AL_SETTINGS is required; run ReadSettings first."
    }
    if ([string]::IsNullOrWhiteSpace($ENV:AL_ENVIRONMENTS)) {
        throw "AL_ENVIRONMENTS is required and must contain valid JSON."
    }
    $authContexts = $ENV:AL_AUTHCONTEXTS_INTERNAL | ConvertFrom-Json
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
    # Validate regex filter to prevent ReDoS attacks
    try {
        [regex]::new($deployToEnvironmentsNameFilter, [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(5)) | Out-Null
    }
    catch {
        throw "Invalid regex pattern in deployToEnvironmentsNameFilter: $deployToEnvironmentsNameFilter"
    }
    $matchingEnvironments = @($deploymentEnvironments.GetEnumerator() | Where-Object { $_.Key -match $deployToEnvironmentsNameFilter } | Select-Object -ExpandProperty Key)
    if ($matchingEnvironments.Count -eq 0) {
        throw "No environments found matching filter '$deployToEnvironmentsNameFilter'"
    }
    Write-Host "Found $($matchingEnvironments.Count) matching environments: $($matchingEnvironments -join ', ') for filter '$deployToEnvironmentsNameFilter'"

    # Collect dependency app files once - the file set is identical for every environment and app folder
    $allDependencies = @()
    # NuGet dependencies
    $dependenciesFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".buildpackages"
    if (Test-Path $dependenciesFolder) {
        $allDependencies += Get-ChildItem -Path $dependenciesFolder -Directory | Where-Object { $_.Name -notlike 'Microsoft.*' } | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Filter "*.app" -Recurse | Select-Object -ExpandProperty FullName
        }
    }
    # BCContainerHelper dependencies
    $dependenciesFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".buildartifacts\Dependencies"
    if (Test-Path $dependenciesFolder) {
        $allDependencies += Get-ChildItem -Path $dependenciesFolder -Filter "*.app" -Recurse | Select-Object -ExpandProperty FullName
    }

    $noOfValidEnvironments = 0
    $environmentUrls = [ordered]@{}
    foreach ($environmentName in $matchingEnvironments) {
        Write-Host "Processing environment: $environmentName"

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
            throw "No AuthContextVariableName specified for environment ($environmentName)."
        }
        if (!$authContexts."$authContextVariableName") {
            throw "No AuthContext found for environment ($environmentName) with variable name ($authContextVariableName)."
        }
        try {
            $authContext = $authContexts."$authContextVariableName"
            $tenantID = $authContext.tenantID
            if ([string]::IsNullOrWhiteSpace($tenantID)) {
                $tenantID = $settings.tenantID
            }
            if ([string]::IsNullOrWhiteSpace($tenantID)) {
                throw "No tenant ID found for environment ($environmentName)."
            }
            $bcAuthContext = New-BCDevOpsFlowsAuthContext -tenantID $tenantID -clientID $authContext.clientID -clientSecret $authContext.clientSecret
            if ($null -eq $bcAuthContext -or [string]::IsNullOrWhiteSpace($bcAuthContext.AccessToken)) {
                throw "Authentication failed for environment '$environmentName' in tenant '$tenantID' using client ID '$($authContext.clientID)'."
            }
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $_.ScriptStackTrace
            Write-Host $_.PSMessageDetails

            throw "Authentication failed. See previous lines for details."
        }

        $environmentUrl = "$((Get-BCDevOpsFlowsBaseUrl).TrimEnd('/'))/$($tenantID)/$($deploymentSettings.environmentName)"

        $environmentUrls[$environmentName] = $environmentUrl
        OutputDebug -Message "Adding $environmentName with URL ($environmentUrl) to environmentUrls"
    
        Write-Host "EnvironmentUrl: $environmentUrl"
        $response = Invoke-RestMethodWithRetry -parameters @{ "UseBasicParsing" = $true; "Method" = 'Get'; "Uri" = "$environmentUrl/deployment/url" }
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
                $dependencies = $allDependencies
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
                if ($settings.Type -eq 'AppSource App' -or ($sandboxEnvironment -and !($bcAuthContext.clientSecret))) {
                    # Sandbox and not S2S -> use dev endpoint
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
                        "authContext" = $bcAuthContext
                        "environment" = $deploymentSettings.environmentName
                        "appFile"     = $appFilePath
                    }
                    if ($deploymentSettings.SyncMode) {
                        if (@('Add', 'ForceSync', 'Clean', 'Development') -notcontains $deploymentSettings.SyncMode) {
                            throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the development endpoint. Valid values are Add, ForceSync, Development and Clean."
                        }
                        Write-Host "Using $($deploymentSettings.SyncMode)"
                        $parameters += @{ "syncMode" = $deploymentSettings.SyncMode }
                    }
                    Write-Host "Publishing apps using development endpoint"
                    Publish-BCDevOpsFlowsDevEndpointApp @parameters -checkAlreadyInstalled
                }
                else {
                    # Use automation API for production environments
                    $parameters = @{
                        "authContext" = $bcAuthContext
                        "environment" = $deploymentSettings.environmentName
                        "appFiles"    = $appFilePath
                    }
                    if ($deploymentSettings.SyncMode) {
                        if (@('Add', 'ForceSync') -notcontains $deploymentSettings.SyncMode) {
                            throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the automation API. Valid values are Add and ForceSync."
                        }
                        Write-Host "Using $($deploymentSettings.SyncMode)"
                        $syncMode = $deploymentSettings.SyncMode
                        if ($syncMode -eq 'ForceSync') { $syncMode = 'Force' }
                        $parameters += @{ "schemaSyncMode" = $syncMode }
                    }
                    Write-Host "Publishing apps using automation API"
                    Publish-BCDevOpsFlowsPerTenantExtensionApps @parameters
                }
            }
        }
    }

    if ($noOfValidEnvironments -eq 0) {
        throw "No valid environments found matching filter '$deployToEnvironmentsNameFilter'"
    }

    $ENV:AL_ENVIRONMENTURLS = $environmentUrls | ConvertTo-Json -Compress
    Write-Host "##vso[task.setvariable variable=AL_ENVIRONMENTURLS;]$($environmentUrls | ConvertTo-Json -Compress)"
    OutputDebug -Message "Set environment variable AL_ENVIRONMENTURLS to ($ENV:AL_ENVIRONMENTURLS)"
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while deploying to environment $environmentName. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}