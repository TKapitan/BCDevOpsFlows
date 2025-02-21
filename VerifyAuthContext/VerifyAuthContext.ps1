Param(
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    $deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $deploymentSettings = $deploymentEnvironments."$environmentName"
    if (!$deploymentSettings) {
        throw "No deployment settings found for environment '$environmentName'."
    }
    $authContexts = $ENV:AL_AUTHCONTEXTS_INTERNAL | ConvertFrom-Json

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
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Error while verifying auth context. See previous lines for details."
}
