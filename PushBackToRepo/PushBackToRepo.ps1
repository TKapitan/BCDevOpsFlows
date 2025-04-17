Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)

try {
    # Push commited changes to DevOps
    Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    Invoke-GitPush
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while pushing changes back to repo. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
finally {
    Pop-Location
}