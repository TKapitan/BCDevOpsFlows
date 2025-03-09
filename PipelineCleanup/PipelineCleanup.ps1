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

    if (Test-Path -Path "$ENV:PIPELINE_WORKSPACE\App\.alpackages") {
        Write-Host "Removing Nuget packages from $ENV:PIPELINE_WORKSPACE\App\.alpackages"
        $packageCachePath = "$ENV:PIPELINE_WORKSPACE\App\.alpackages"
        Remove-Item $packageCachePath -Recurse -Include *.*
    }
}