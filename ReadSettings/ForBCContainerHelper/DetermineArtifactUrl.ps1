Param(
    [Parameter(HelpMessage = "Specifies whether to skip preview apps as dependencies.", Mandatory = $false)]
    [switch] $skipAppsInPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper

# Determine artifacts to use
. (Join-Path -Path $PSScriptRoot -ChildPath "DetermineArtifactUrl.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
if ($settings.artifact -notlike "https://*") {
    $artifactUrl = DetermineArtifactUrl -settings $settings
    $settings.artifact = $artifactUrl
}
else {
    $artifactUrl = $settings.artifact
}

# Set output variables
$ENV:AL_ARTIFACT = $artifactUrl
Write-Host "##vso[task.setvariable variable=AL_ARTIFACT;]$artifactUrl"
OutputDebug -Message "Set environment variable AL_ARTIFACT to ($ENV:AL_ARTIFACT)"
$ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
OutputDebug -Message "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"
