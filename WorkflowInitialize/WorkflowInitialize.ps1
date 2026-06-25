Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

try {
    # Clean up leftover build folders before the build in case a previous run left non-expected files behind
    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $cleanUpPaths = @(
        "$baseRepoFolder\.buildpackages"
        "$baseRepoFolder\.buildartifacts\Dependencies"
        "$baseRepoFolder\.buildartifacts\TestApps"
        "$baseRepoFolder\.buildartifacts\Apps"
        "$baseRepoFolder\.output"
    )
    foreach ($cleanUpPath in $cleanUpPaths) {
        if (Test-Path $cleanUpPath) {
            Write-Host "Removing leftover files from $cleanUpPath"
            Remove-Item $cleanUpPath -Recurse -Force
        }
    }
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
