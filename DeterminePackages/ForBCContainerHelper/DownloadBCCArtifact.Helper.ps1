Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable

$artifactUrl = $ENV:AL_ARTIFACT
if ($artifactUrl -notlike "https://*") {
    throw "Environment variable AL_ARTIFACT is not set to a valid URL."
}
$bcContainerHelperConfig | Add-Member -NotePropertyName 'bcartifactsCacheFolder' -NotePropertyValue $settings.cacheFolder -Force
$folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
if (!($folders)) {
    throw "Unable to download artifacts from $($artifactUrl.Split('?')[0])."
}
if ([Version]$settings.applicationDependency -gt [Version]$artifactUrl.Split('/')[4]) {
    $version = $artifactUrl.Split('/')[4]
    throw "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
}
