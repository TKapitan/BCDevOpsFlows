. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

# Create a json object that contains an entry for the workflowstarttime
$scopeJson = @{
    "workflowStartTime" = [DateTime]::UtcNow
} | ConvertTo-Json -Compress

$env:AL_TELEMETRYSCOPE = $scopeJson
Write-Host "##vso[task.setvariable variable=AL_TELEMETRYSCOPE;]$scopeJson"
OutputDebug -Message "Set environment variable AL_TELEMETRYSCOPE to ($env:AL_TELEMETRYSCOPE)"

Install-Module -Name ConvertTo-Hashtable -Force -Verbose -Scope CurrentUser
Import-Module powershell-yaml