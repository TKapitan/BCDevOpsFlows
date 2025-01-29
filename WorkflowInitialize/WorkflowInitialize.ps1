# Create a json object that contains an entry for the workflowstarttime
$scopeJson = @{
    "workflowStartTime" = [DateTime]::UtcNow
} | ConvertTo-Json -Compress

$env:telemetryScopeJson = $scopeJson
Write-Host "##vso[task.setvariable variable=telemetryScopeJson;]$scopeJson"
Write-Host "Set environment variable telemetryScopeJson to ($env:telemetryScopeJson)"