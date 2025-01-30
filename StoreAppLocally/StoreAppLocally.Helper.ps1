. (Join-Path -Path $PSScriptRoot -ChildPath "..\FindDependencies\FindDependencies.Helper.ps1" -Resolve)

function Save-AppLocally {
    Param(
        [string] $appArtifactSharedFolder,
        [string] $appJsonFilePath,
        [version] $forBcVersion,
        [switch] $isPreview
    )

    $appJsonFilePath = (Join-Path $ENV:BUILD_REPOSITORY_LOCALPATH $appJsonFilePath);
    Write-Host "Using local path '$appJsonFilePath'"

    # Find app.json & target path
    $appFile = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
    $targetPath = Get-AppTargetFilePath -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $appFile.id -extensionVersion $appFile.version -minBcVersion $forBcVersion -includeAppsInPreview $isPreview -findExisting $false

    # Copy application file & app.json file to our shared folder
    $newAppFileLocation = $targetPath + (Get-AppFileName -publisher $appFile.publisher -name $appFile.name -version $appFile.version);
    New-Item -ItemType File -Path $newAppFileLocation -Force -Verbose
    Copy-Item (Get-AppSourceFileLocation -appFile $appFile) $newAppFileLocation
    Copy-Item $appJsonFilePath ($targetPath + 'app.json')
}