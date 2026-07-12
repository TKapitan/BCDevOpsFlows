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
