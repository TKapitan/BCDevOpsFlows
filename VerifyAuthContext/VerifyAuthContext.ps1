Param(
    [Parameter(HelpMessage = "Name of environment to verify authcontext OR regex filter of environment names to verify authcontext", Mandatory = $true)]
    [string] $environmentsNameFilter
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\CloudAuth.Helper.ps1" -Resolve)

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
        [regex]::new($environmentsNameFilter, [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(5)) | Out-Null
    }
    catch {
        throw "Invalid regex pattern in environmentsNameFilter: $environmentsNameFilter"
    }
    $matchingEnvironments = @($deploymentEnvironments.GetEnumerator() | Where-Object { $_.Key -match $environmentsNameFilter } | Select-Object -ExpandProperty Key)
    if ($matchingEnvironments.Count -eq 0) {
        throw "No environments found matching filter '$environmentsNameFilter'"
    }
    Write-Host "Found $($matchingEnvironments.Count) matching environments: $($matchingEnvironments -join ', ') for filter '$environmentsNameFilter'"

    $noOfValidEnvironments = 0
    foreach ($environmentName in $matchingEnvironments) {
        Write-Host "Processing environment: $environmentName"

        $deploymentSettings = $deploymentEnvironments."$environmentName"
        if (!$deploymentSettings) {
            throw "No deployment settings found for environment '$environmentName'."
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
            $accessToken = Get-BCDevOpsFlowsAuthToken -tenantID $tenantID -clientID $authContext.clientID -clientSecret $authContext.clientSecret
            if ([string]::IsNullOrWhiteSpace($accessToken)) {
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

    if ($noOfValidEnvironments -eq 0) {
        throw "No valid environments found matching filter '$environmentsNameFilter'"
    }
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while verifying auth context for environment '$environmentName'. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}