. (Join-Path -Path $PSScriptRoot -ChildPath "..\FindDependencies\FindDependencies.Helper.ps1" -Resolve)

function Get-AppTargetFilePathForNewApp {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string] $appArtifactSharedFolder,
        [Parameter(Mandatory)]
        $appFileJson,
        [switch] $isPreview
    )

    $releaseTypeFolderParam = @{}
    if ($isPreview -eq $true) {
        $releaseTypeFolderParam = @{ "isPreview" = $true }
    }
    
    $releaseTypeFolder = Get-ReleaseTypeFolderName @releaseTypeFolderParam
    $targetFilePath = "$appArtifactSharedFolder\apps\$releaseTypeFolder\$($appFileJson.id)\$($appFileJson.version)-BC$($appFileJson.application)\"
    Write-Host "Using '$targetFilePath' regardless if the extension exists or not"
    return $targetFilePath
}