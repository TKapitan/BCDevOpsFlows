# Install BCContainerHelper
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

# Remove container
. (Join-Path -Path $PSScriptRoot -ChildPath "..\RunPipeline\RunPipeline.Helper.ps1" -Resolve)
$containerName = GetContainerName
Remove-Bccontainer $containerName

# Clean Nuget
if ($ENV:AL_NUGETINITIALIZED) {
    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $packageCachePath = "$baseRepoFolder\App\.alpackages"
    Remove-Item $packageCachePath -Recurse -Include *.*

    RemoveNugetPackageSource -sourceName "MSSymbols"
    RemoveNugetPackageSource -sourceName "AppSourceSymbols"
}