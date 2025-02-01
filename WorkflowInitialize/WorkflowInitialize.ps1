. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

# Create a json object that contains an entry for the workflowstarttime
$scopeJson = @{
    "workflowStartTime" = [DateTime]::UtcNow
} | ConvertTo-Json -Compress

$env:AL_TELEMETRYSCOPE = $scopeJson
OutputMessage "##vso[task.setvariable variable=AL_TELEMETRYSCOPE;]$scopeJson"
OutputMessage "Set environment variable AL_TELEMETRYSCOPE to ($env:AL_TELEMETRYSCOPE)"