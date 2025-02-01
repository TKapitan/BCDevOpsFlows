. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

# Install BCContainerHelper
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

# Determine artifacts to use
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\AnalyzeRepository.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "DetermineArtifactUrl.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings
$artifactUrl = DetermineArtifactUrl -settings $settings
$artifactCacheKey = ''
if ($settings.useCompilerFolder) {
    $artifactCacheKey = $artifactUrl.Split('?')[0]
    OutputMessage "Using artifactCacheKey $artifactCacheKey"
}

# Set output variables
$ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
OutputMessage "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
OutputMessage "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"

$ENV:AL_ARTIFACT = $artifactUrl
OutputMessage "##vso[task.setvariable variable=artifact;]$artifactUrl"
OutputMessage "Set environment variable artifact to ($ENV:AL_ARTIFACT)"

$ENV:AL_ARTIFACTCACHEKEY = $artifactCacheKey
OutputMessage "##vso[task.setvariable variable=artifactCacheKey;]$artifactCacheKey"
OutputMessage "Set environment variable artifactCacheKey to ($ENV:AL_ARTIFACTCACHEKEY)"
