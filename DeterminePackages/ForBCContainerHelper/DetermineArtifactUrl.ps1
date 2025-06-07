Param(
    [Parameter(HelpMessage = "Specifies whether to skip preview apps as dependencies.", Mandatory = $false)]
    [switch] $skipAppsInPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)

try {
    DownloadAndImportBcContainerHelper

    # Determine artifacts to use
    . (Join-Path -Path $PSScriptRoot -ChildPath "DetermineArtifactUrl.Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\AnalyzeRepository.Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    $artifactUrl = DetermineArtifactUrl -settings $settings

    # Set output variables
    $ENV:AL_ARTIFACT = $artifactUrl
    Write-Host "##vso[task.setvariable variable=AL_ARTIFACT;]$artifactUrl"
    OutputDebug -Message "Set environment variable AL_ARTIFACT to ($ENV:AL_ARTIFACT)"
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
