# Clean Containers
if ($ENV:AL_CONTAINERNAME) {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\RunPipeline\RunPipeline.Helper.ps1" -Resolve)

    DownloadAndImportBcContainerHelper
    Remove-Bccontainer GetContainerName
}

# Clean Nuget
if ($ENV:AL_NUGETINITIALIZED) {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
    
    $packageCachePath = "$ENV:PIPELINE_WORKSPACE\App\.alpackages"
    Remove-Item $packageCachePath -Recurse -Include *.*
}