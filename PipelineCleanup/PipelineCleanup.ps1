# Clean Containers
if ($ENV:AL_CONTAINERNAME) {
    Write-Host "Cleaning container $ENV:AL_CONTAINERNAME"
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\RunPipeline\RunPipeline.Helper.ps1" -Resolve)

    DownloadAndImportBcContainerHelper
    Write-Host "Removing container $ENV:AL_CONTAINERNAME"
    Remove-Bccontainer GetContainerName
}

# Clean Nuget
if ($ENV:AL_NUGETINITIALIZED) {
    Write-Host "Cleaning Nuget packages"
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)

    $cleanUpPath = "$ENV:PIPELINE_WORKSPACE\App\.alpackages"
    if (Test-Path $cleanUpPath) {
        Write-Host "Removing Nuget packages from $cleanUpPath"
        Remove-Item $cleanUpPath -Recurse -Include *.*
    }
    $cleanUpPath = "$ENV:PIPELINE_WORKSPACE\App\.buildartifacts\Dependencies"
    if (Test-Path $cleanUpPath) {
        Write-Host "Removing Nuget packages from $cleanUpPath"
        Remove-Item $cleanUpPath -Recurse -Include *.*
    }
}