# Shared retry-with-backoff wrapper for outbound HTTP calls.
# Transient failures (HTTP 408/429/5xx and network-level errors such as timeouts, DNS failures
# and dropped connections) are retried with exponential backoff; every other failure (401/403/
# 404/409, malformed requests) surfaces immediately. A default timeout is applied so a hung
# connection cannot stall a pipeline step indefinitely.
# This file is self-contained and safe to dot-source multiple times.

$script:RetryableHttpStatusCodes = @(408, 429, 500, 502, 503, 504)
$script:RetryableHttpExceptionTypes = @(
    'System.Net.WebException'
    'System.Net.Http.HttpRequestException'
    'System.Net.Sockets.SocketException'
    'System.IO.IOException'
    'System.TimeoutException'
    'System.Threading.Tasks.TaskCanceledException'
    'System.OperationCanceledException'
)

function Get-BCDevOpsFlowsHttpStatusCode {
    Param(
        [Parameter(Mandatory = $true)]
        $errorRecord
    )

    # Windows PowerShell raises System.Net.WebException, PowerShell 7+ raises
    # Microsoft.PowerShell.Commands.HttpResponseException; both expose the HTTP status
    # through $errorRecord.Exception.Response.StatusCode
    try {
        if ($errorRecord.Exception.Response) {
            return [int]$errorRecord.Exception.Response.StatusCode
        }
    }
    catch {
        return $null
    }
    return $null
}

function Test-BCDevOpsFlowsRetryableHttpError {
    Param(
        [Parameter(Mandatory = $true)]
        $errorRecord
    )

    $statusCode = Get-BCDevOpsFlowsHttpStatusCode -errorRecord $errorRecord
    if ($null -ne $statusCode) {
        return $script:RetryableHttpStatusCodes -contains $statusCode
    }
    # No HTTP status available - retry only network-level failures, never programming errors.
    # Type names are compared as strings because System.Net.Http may not be loaded on
    # Windows PowerShell.
    $exception = $errorRecord.Exception
    while ($exception) {
        if ($script:RetryableHttpExceptionTypes -contains $exception.GetType().FullName) {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function Get-BCDevOpsFlowsRetryAfterSeconds {
    Param(
        [Parameter(Mandatory = $true)]
        $errorRecord
    )

    try {
        $response = $errorRecord.Exception.Response
        if (!$response) {
            return $null
        }
        $headers = $response.Headers
        if ($headers -is [System.Net.WebHeaderCollection]) {
            # Windows PowerShell (WebException response)
            $value = $headers['Retry-After']
            if ($value) {
                return [double]$value
            }
        }
        elseif ($headers -and $headers.RetryAfter -and $headers.RetryAfter.Delta) {
            # PowerShell 7+ (HttpResponseMessage)
            return $headers.RetryAfter.Delta.Value.TotalSeconds
        }
    }
    catch {
        return $null
    }
    return $null
}

function Invoke-BCDevOpsFlowsHttpWithRetry {
    Param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $invocation,
        [Parameter(Mandatory = $true)]
        [hashtable] $parameters,
        [int] $maxRetries = 3,
        [double] $initialDelaySeconds = 2.0
    )

    $parameters = $parameters.Clone()
    if (-not $parameters.ContainsKey('TimeoutSec')) {
        # Invoke-RestMethod/Invoke-WebRequest otherwise wait indefinitely on a hung connection
        $parameters['TimeoutSec'] = 300
    }
    $delaySeconds = $initialDelaySeconds
    for ($attempt = 1; $attempt -le ($maxRetries + 1); $attempt++) {
        try {
            return & $invocation $parameters
        }
        catch {
            if ($attempt -gt $maxRetries -or -not (Test-BCDevOpsFlowsRetryableHttpError -errorRecord $_)) {
                throw
            }
            $waitSeconds = $delaySeconds
            $retryAfter = Get-BCDevOpsFlowsRetryAfterSeconds -errorRecord $_
            if ($retryAfter -and $retryAfter -gt $waitSeconds) {
                # Honor the server's Retry-After, bounded so a pipeline cannot stall for minutes
                $waitSeconds = [Math]::Min($retryAfter, 60)
            }
            Write-Host "HTTP request to $($parameters['Uri']) failed ($($_.Exception.Message)). Retrying in $waitSeconds seconds (attempt $attempt of $maxRetries)..."
            Start-Sleep -Seconds $waitSeconds
            $delaySeconds *= 2
        }
    }
}

function Invoke-RestMethodWithRetry {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $parameters,
        [int] $maxRetries = 3,
        [double] $initialDelaySeconds = 2.0
    )

    return Invoke-BCDevOpsFlowsHttpWithRetry -invocation { Param($p) Invoke-RestMethod @p } -parameters $parameters -maxRetries $maxRetries -initialDelaySeconds $initialDelaySeconds
}

function Invoke-WebRequestWithRetry {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $parameters,
        [int] $maxRetries = 3,
        [double] $initialDelaySeconds = 2.0
    )

    return Invoke-BCDevOpsFlowsHttpWithRetry -invocation { Param($p) Invoke-WebRequest @p } -parameters $parameters -maxRetries $maxRetries -initialDelaySeconds $initialDelaySeconds
}
