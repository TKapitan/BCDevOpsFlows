Param(
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
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
if (!$ENV:AL_APPDETAILS) {
    throw "No app to deploy settings found."
}
$appToDeploy = $ENV:AL_APPDETAILS | ConvertFrom-Json | ConvertTo-HashTable
if (!$appToDeploy) {
    throw "No app to deploy settings found."
}

$deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
$matchingEnvironments = @($deploymentEnvironments.GetEnumerator() | Where-Object { $_.Key -match $deployToEnvironmentsNameFilter } | Select-Object -ExpandProperty Key)
if ($matchingEnvironments.Count -eq 0) {
    throw "No environments found matching filter '$environmentsNameFilter'"
}
Write-Host "Found $($matchingEnvironments.Count) matching environments: $($matchingEnvironments -join ', ') for filter '$environmentsNameFilter'"

$environmentUrls = @{} | ConvertTo-Json
foreach ($environmentName in $matchingEnvironments) {
    Write-Host "Processing environment: $environmentName"

    try {
        $deploymentSettings = $deploymentEnvironments."$environmentName"
        if (!$deploymentSettings) {
            throw "No deployment settings found for environment '$environmentName'."
        }
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
            OutputError -message "Environment with name $($deploymentSettings.environmentName) does not exist in the current authorization context."
            exit
        }
        if ($response.Status -ne "Ready") {
            OutputError -message "Environment with name $($deploymentSettings.environmentName) is not ready (Status is $($response.Status))."
            exit
        }

        Write-Host "Apps to deploy"
        foreach ($appToDeployProperty in $appToDeploy.GetEnumerator()) {
            Write-Host " - $($appToDeployProperty.Name): $($appToDeployProperty.Value)"
        }
    
        # Deploy app
        $dependencies = @()
        Write-Host "Deploy app details: $appToDeploy"

        $appFile = $appToDeploy.appFile
        $appJsonFile = $appToDeploy.appJsonFile
        $minBcVersion = $appToDeploy.applicationVersion

        Write-Host "- $([System.IO.Path]::GetFileName($appFile))"

        if ($deploymentSettings.dependencyInstallMode -ne "ignore") {
            $dependenciesToDeploy = Get-AppDependencies -appJsonFilePath $appJsonFile -minBcVersion $minBcVersion
            if ($dependenciesToDeploy) {
                $dependencies += $dependenciesToDeploy
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
                    "appFile"       = $appFile
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
                    "appFiles"      = $appFile
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
    catch {
        Write-Host $_.Exception -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        Write-Host $_.PSMessageDetails

        Write-Error "Deployment to environment ($environmentName) failed. See previous lines for details."
    }
}

$ENV:AL_ENVIRONMENTURLS = $environmentUrls | ConvertTo-Json -Compress
Write-Host "##vso[task.setvariable variable=AL_ENVIRONMENTURLS;]$($environmentUrls | ConvertTo-Json -Compress)"
OutputDebug -Message "Set environment variable AL_ENVIRONMENTURLS to ($ENV:AL_ENVIRONMENTURLS)"
