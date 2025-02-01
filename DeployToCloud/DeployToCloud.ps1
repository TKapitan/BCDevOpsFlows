Param(
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD', 'Publish')]
    [string] $deploymentType = "CD"
)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeployToCloud.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper

try {
    $deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $deploymentSettings = $deploymentEnvironments."$environmentName"
    if (!$deploymentSettings) {
        throw "No deployment settings found for environment '$environmentName'."
    }
    $appToDeploy = $ENV:AL_APPDETAILS | ConvertFrom-Json | ConvertTo-HashTable
    if (!$appToDeploy) {
        throw "No app to deploy settings found."
    }
    $buildMode = $deploymentSettings.buildMode
    if ($null -eq $buildMode -or $buildMode -eq 'default') {
        $buildMode = ''
    }
    $authContexts = $ENV:AL_AUTHCONTEXT | ConvertFrom-Json
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json

    $authContext = $null
    $authContextVariableName = $deploymentSettings.authContextVariableName
    Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    if (!$authContextVariableName) {
        OutputError "No AuthContextVariableName specified for environment ($environmentName)."
    }
    if (!$authContexts."$authContextVariableName") {
        OutputError "No AuthContext found for environment ($environmentName) with variable name ($authContextVariableName)."
    }
    try {
        $authContext = $authContexts."$authContextVariableName"
        $bcAuthContext = New-BcAuthContext -tenantID $authContext.tenantID -clientID $authContext.clientID -clientSecret $authContext.clientSecret
        if ($null -eq $bcAuthContext) {
            throw "Authentication failed"
        }
    }
    catch {
        OutputMessage $_.Exception -ForegroundColor Red
        OutputMessage $_.ScriptStackTrace
        OutputMessage $_.PSMessageDetails
    
        OutputError "Authentication failed. See previous lines for details."
    }

    $environmentUrl = "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.environmentName)"
    
    $ENV:AL_ENVIRONMENTURL = $environmentUrl
    OutputMessage "##vso[task.setvariable variable=AL_ENVIRONMENTURL;]$environmentUrl"
    OutputMessage "Set environment variable AL_ENVIRONMENTURL to ($ENV:AL_ENVIRONMENTURL)"
    
    OutputMessage "EnvironmentUrl: $environmentUrl"
    $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$environmentUrl/deployment/url"
    if ($response.Status -eq "DoesNotExist") {
        OutputMessageError -message "Environment with name $($deploymentSettings.environmentName) does not exist in the current authorization context."
        exit
    }
    if ($response.Status -ne "Ready") {
        OutputMessageError -message "Environment with name $($deploymentSettings.environmentName) is not ready (Status is $($response.Status))."
        exit
    }

    OutputMessage "Apps to deploy"
    foreach ($appToDeployProperty in $appToDeploy.GetEnumerator()) {
        OutputMessage " - $($appToDeployProperty.Name): $($appToDeployProperty.Value)"
    }
    
    # Deploy app
    $dependencies = @()
    OutputMessage "Deploy app details: $appToDeploy"

    $appFile = $appToDeploy.appFile
    $appJsonFile = $appToDeploy.appJsonFile
    $minBcVersion = $appToDeploy.applicationVersion

    OutputMessage "- $([System.IO.Path]::GetFileName($appFile))"

    if ($deploymentSettings.dependencyInstallMode -ne "ignore") {
        $dependenciesToDeploy = Get-AppDependencies -appArtifactSharedFolder $settings.appArtifactSharedFolder -appJsonFilePath $appJsonFile -minBcVersion $minBcVersion -includeAppsInPreview $includeAppsInPreview
        if ($dependenciesToDeploy) {
            $dependencies += $dependenciesToDeploy
        }
    
        OutputMessage "Dependencies to $($deploymentSettings.dependencyInstallMode)"
        if ($dependencies) {
            $dependencies | ForEach-Object {
                OutputMessage "- $([System.IO.Path]::GetFileName($_))"
            }
        }
        else {
            OutputMessage "- None"
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
        OutputMessage "::Warning::Ignoring environment $($deploymentSettings.environmentName), which is a production environment"
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
                "appFile"       = $appFile
            }
            if ($deploymentSettings.SyncMode) {
                if (@('Add', 'ForceSync', 'Clean', 'Development') -notcontains $deploymentSettings.SyncMode) {
                    throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the development endpoint. Valid values are Add, ForceSync, Development and Clean."
                }
                OutputMessage "Using $($deploymentSettings.SyncMode)"
                $parameters += @{ "SyncMode" = $deploymentSettings.SyncMode }
            }
            OutputMessage "Publishing apps using development endpoint"
            Publish-BcContainerApp @parameters -useDevEndpoint -checkAlreadyInstalled -excludeRuntimePackages -replacePackageId
        }
        else {
            # Use automation API for production environments (Publish-PerTenantExtensionApps)
            $parameters = @{
                "bcAuthContext" = $bcAuthContext
                "environment"   = $deploymentSettings.environmentName
                "appFiles"      = $appFile
            }
            if ($deploymentSettings.SyncMode) {
                if (@('Add', 'ForceSync') -notcontains $deploymentSettings.SyncMode) {
                    throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the automation API. Valid values are Add and ForceSync."
                }
                OutputMessage "Using $($deploymentSettings.SyncMode)"
                $syncMode = $deploymentSettings.SyncMode
                if ($syncMode -eq 'ForceSync') { $syncMode = 'Force' }
                $parameters += @{ "SchemaSyncMode" = $syncMode }
            }
            OutputMessage "Publishing apps using automation API"
            Publish-PerTenantExtensionApps @parameters
        }
    }
}
catch {
    OutputMessage $_.Exception -ForegroundColor Red
    OutputMessage $_.ScriptStackTrace
    OutputMessage $_.PSMessageDetails

    OutputError "Error running deployment pipeline. See previous lines for details."
}
