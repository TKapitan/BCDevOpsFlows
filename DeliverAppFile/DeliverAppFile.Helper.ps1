. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Import-NuGet.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)

function Push-AppToNuGetFeed {
    Param(
        [Parameter(HelpMessage = "The name of the folder containing the app file.", Mandatory = $true)]
        [string] $folderName,
        [Parameter(HelpMessage = "The URL of the NuGet server to push the app to.", Mandatory = $true)]
        [string] $url,
        [Parameter(HelpMessage = "The NuGet token to use for authentication.", Mandatory = $true)]
        [string] $token,
        [Parameter(HelpMessage = "Specifies suffix for the version of the app such as preview or tests.", Mandatory = $false)]
        [string] $versionSuffix
    )

    Write-Host "Delivering apps from folder: $folderName"

    $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "$folderName\app.json"
    $appJsonContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
    $appFilePath = Get-AppSourceFileLocation -appFile $appJsonContent

    if (-not (Test-Path -Path $appFilePath) -and $versionSuffix -eq 'tests') {
        Write-Host "Test App file not found at path: $appFilePath, skipping..."
        return
    }

    Write-Host "Saving '$($appJsonContent.name)' app from '$appFilePath' to NuGet feed '$url'"

    # Create NuGet package
    $parameters = @{
        "preReleaseTag" = $versionSuffix
        "appFile"       = $appFilePath
    }
    $package = New-BCDevOpsFlowsNuGetPackage @parameters
    Push-BCDevOpsFlowsNuGetPackage -nuGetServerUrl $url -nuGetToken $token -bcNuGetPackage $package
}
