Param()
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)

try {
    # Push commited changes to DevOps
    Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    Invoke-GitPush
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    throw "Pushing changes to DevOps failed. Please check the error message above."
}