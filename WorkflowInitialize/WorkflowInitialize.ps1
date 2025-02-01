# Create a json object that contains an entry for the workflowstarttime
$scopeJson = @{
    "workflowStartTime" = [DateTime]::UtcNow
} | ConvertTo-Json -Compress

$env:AL_TELEMETRYSCOPE = $scopeJson
Write-Host "##vso[task.setvariable variable=AL_TELEMETRYSCOPE;]$scopeJson"
Write-Host "Set environment variable AL_TELEMETRYSCOPE to ($env:AL_TELEMETRYSCOPE)"