Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

try {
    # Clean Containers
    if ($ENV:AL_CONTAINERNAME) {
        Write-Host "Cleaning container $ENV:AL_CONTAINERNAME"
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\Build\WithBCContainerHelper\BuildWithBCContainerHelper.Helper.ps1" -Resolve)

        DownloadAndImportBcContainerHelper
        Write-Host "Removing container $ENV:AL_CONTAINERNAME"
        Remove-Bccontainer GetContainerName
    }
    # Clean Nuget only if AL_NUGETINITIALIZED is set and true
    if ($ENV:AL_NUGETINITIALIZED -and [bool]::Parse($ENV:AL_NUGETINITIALIZED)) {
        Write-Host "Cleaning Nuget packages"
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)

        $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
        $cleanUpPath = "$baseRepoFolder\.buildpackages"
        if (Test-Path $cleanUpPath) {
            Write-Host "Removing Nuget packages from $cleanUpPath"
            Remove-Item $cleanUpPath -Recurse -Include *.*
        }
        $cleanUpPath = "$baseRepoFolder\.buildartifacts\Dependencies"
        if (Test-Path $cleanUpPath) {
            Write-Host "Removing Nuget packages from $cleanUpPath"
            Remove-Item $cleanUpPath -Recurse -Include *.*
        }
    }
    
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\CustomLogic\RunCustomCleanup.ps1" -Resolve)
    RunCustomCleanup
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