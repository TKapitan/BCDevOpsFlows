Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    # Create a json object that contains an entry for the workflowstarttime
    $scopeJson = @{
        "workflowStartTime" = [DateTime]::UtcNow
    } | ConvertTo-Json -Compress

    $env:AL_TELEMETRYSCOPE = $scopeJson
    Write-Host "##vso[task.setvariable variable=AL_TELEMETRYSCOPE;]$scopeJson"
    OutputDebug -Message "Set environment variable AL_TELEMETRYSCOPE to ($env:AL_TELEMETRYSCOPE)"
}
catch {
    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
