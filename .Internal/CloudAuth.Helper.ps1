. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "Common\Invoke-HttpWithRetry.ps1" -Resolve)

# Container-free replacements for the BcContainerHelper auth functionality used by cloud-only steps.
# Steps that talk to Business Central online only need an OAuth token and the public base URL;
# importing the full BcContainerHelper module for that costs 10-30 seconds per pipeline step.

function Get-BCDevOpsFlowsBaseUrl {
    Param()

    return "https://businesscentral.dynamics.com"
}

function Get-BCDevOpsFlowsAuthToken {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $tenantID,
        [Parameter(Mandatory = $true)]
        [string] $clientID,
        [Parameter(Mandatory = $true)]
        [string] $clientSecret,
        [Parameter(Mandatory = $false)]
        [string] $scopes = "https://api.businesscentral.dynamics.com/.default"
    )

    $body = @{
        "grant_type"    = "client_credentials"
        "client_id"     = $clientID
        "client_secret" = $clientSecret
        "scope"         = $scopes
    }
    OutputDebug -Message "Requesting client credentials token for client $clientID in tenant $tenantID with scope $scopes"
    $response = Invoke-RestMethodWithRetry -parameters @{ "Method" = 'Post'; "Uri" = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"; "Body" = $body }
    return $response.access_token
}

function New-BCDevOpsFlowsAuthContext {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $tenantID,
        [Parameter(Mandatory = $true)]
        [string] $clientID,
        [Parameter(Mandatory = $true)]
        [string] $clientSecret,
        [Parameter(Mandatory = $false)]
        [string] $scopes = "https://api.businesscentral.dynamics.com/.default"
    )

    $authContext = @{
        "tenantID"     = $tenantID
        "clientID"     = $clientID
        "clientSecret" = $clientSecret
        "scopes"       = $scopes
        "AccessToken"  = $null
        "UtcExpiresOn" = [DateTime]::MinValue
    }
    Update-BCDevOpsFlowsAuthContext -authContext $authContext | Out-Null
    return $authContext
}

function Update-BCDevOpsFlowsAuthContext {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext
    )

    # Tokens live ~60-75 minutes; renew when less than 5 minutes remain so long deployments
    # never run into an expired token mid-operation
    if ($authContext.AccessToken -and $authContext.UtcExpiresOn -gt [DateTime]::UtcNow.AddMinutes(5)) {
        return $authContext
    }
    $body = @{
        "grant_type"    = "client_credentials"
        "client_id"     = $authContext.clientID
        "client_secret" = $authContext.clientSecret
        "scope"         = $authContext.scopes
    }
    OutputDebug -Message "Requesting client credentials token for client $($authContext.clientID) in tenant $($authContext.tenantID) with scope $($authContext.scopes)"
    $response = Invoke-RestMethodWithRetry -parameters @{ "Method" = 'Post'; "Uri" = "https://login.microsoftonline.com/$($authContext.tenantID)/oauth2/v2.0/token"; "Body" = $body }
    $authContext.AccessToken = $response.access_token
    $authContext.UtcExpiresOn = [DateTime]::UtcNow.AddSeconds([int]$response.expires_in)
    return $authContext
}

function Get-BCDevOpsFlowsAuthHeaders {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext
    )

    Update-BCDevOpsFlowsAuthContext -authContext $authContext | Out-Null
    return @{ "Authorization" = "Bearer $($authContext.AccessToken)" }
}
