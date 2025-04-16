Param(
    [Parameter(HelpMessage = "Name of environment to verify authcontext OR regex filter of environment names to verify authcontext", Mandatory = $true)]
    [string] $environmentsNameFilter
)
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$authContexts = $ENV:AL_AUTHCONTEXTS_INTERNAL | ConvertFrom-Json
$deploymentEnvironments = $ENV:AL_ENVIRONMENTS | ConvertFrom-Json | ConvertTo-HashTable -recurse
$matchingEnvironments = @($deploymentEnvironments.GetEnumerator() | Where-Object { $_.Key -match $environmentsNameFilter } | Select-Object -ExpandProperty Key)
if ($matchingEnvironments.Count -eq 0) {
    throw "No environments found matching filter '$environmentsNameFilter'"
}
Write-Host "Found $($matchingEnvironments.Count) matching environments: $($matchingEnvironments -join ', ') for filter '$environmentsNameFilter'"

$noOfValidEnvironments = 0
foreach ($environmentName in $matchingEnvironments) {
    Write-Host "Processing environment: $environmentName"

    try {
        $deploymentSettings = $deploymentEnvironments."$environmentName"
        if (!$deploymentSettings) {
            throw "No deployment settings found for environment '$environmentName'."
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
    }
    catch {
        Write-Host $_.Exception -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        Write-Host $_.PSMessageDetails

        Write-Error "Error while verifying auth context for environment '$environmentName'. See previous lines for details."
    }
}

if ($noOfValidEnvironments -eq 0) {
    Write-Error "No valid environments found matching filter '$deployToEnvironmentsNameFilter'"
}
