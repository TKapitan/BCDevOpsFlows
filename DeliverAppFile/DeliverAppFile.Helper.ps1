. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)

function Push-AppToNuGetFeed {
    Param(
        [Parameter(HelpMessage = "The name of the folder containing the app file.", Mandatory = $true)]
        [string] $folderName,
        [Parameter(HelpMessage = "The URL of the NuGet server to push the app to.", Mandatory = $true)]
        [string] $serverUrl,
        [Parameter(HelpMessage = "The NuGet token to use for authentication.", Mandatory = $true)]
        [string] $accessToken,
        [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
        [switch] $isPreview
    )

    Write-Host "Delivering apps from folder: $folderName"

    $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "$folderName\app.json"
    $appJsonContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
    $appFilePath = Get-AppSourceFileLocation -appFile $appJsonContent

    Write-Host "Saving '$($appJsonContent.name)' app to ($serverUrl)"

    $preReleaseTag = @{}
    if ($isPreview -eq $true) {
        $preReleaseTag = 'preview'
    }

    # Create NuGet package
    $parameters = @{
        "preReleaseTag" = $preReleaseTag
        "appFile"       = $appFilePath
    }
    $package = New-BcNuGetPackage @parameters
    Push-BcNuGetPackage -nuGetServerUrl $serverUrl -nuGetToken $accessToken -bcNuGetPackage $package
}

function Get-AppTargetFilePathForNewApp {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string] $writableFolderPath,
        [Parameter(Mandatory)]
        $appFileJson,
        [switch] $isPreview
    )

    $releaseTypeFolderParam = @{}
    if ($isPreview -eq $true) {
        $releaseTypeFolderParam = @{ "isPreview" = $true }
    }
    
    $releaseTypeFolder = Get-ReleaseTypeFolderName @releaseTypeFolderParam
    $targetFilePath = "$writableFolderPath\apps\$releaseTypeFolder\$($appFileJson.id)\$($appFileJson.version)-BC$($appFileJson.application)\"
    Write-Host "Using '$targetFilePath' regardless if the extension exists or not"
    return $targetFilePath
}