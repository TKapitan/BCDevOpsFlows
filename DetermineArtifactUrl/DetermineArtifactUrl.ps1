# Install BCContainerHelper
. (Join-Path -Path $PSScriptRoot -ChildPath "..\BCContainerHelper.Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper

# Determine artifacts to use
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AnalyzeRepository\AnalyzeRepository.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "DetermineArtifactUrl.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings
$artifactUrl = DetermineArtifactUrl -settings $settings
$artifactCacheKey = ''
if ($settings.useCompilerFolder) {
    $artifactCacheKey = $artifactUrl.Split('?')[0]
    Write-Host "Using artifactCacheKey $artifactCacheKey"
}

# Set output variables
$ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
Write-Host "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"

$ENV:AL_ARTIFACT = $artifactUrl
Write-Host "##vso[task.setvariable variable=artifact;]$artifactUrl"
Write-Host "Set environment variable artifact to ($ENV:AL_ARTIFACT)"

$ENV:AL_ARTIFACTCACHEKEY = $artifactCacheKey
Write-Host "##vso[task.setvariable variable=artifactCacheKey;]$artifactCacheKey"
Write-Host "Set environment variable artifactCacheKey to ($ENV:AL_ARTIFACTCACHEKEY)"