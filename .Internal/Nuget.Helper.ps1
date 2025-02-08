function GetNugetPackagePath() {
    Param(
        [string] $packageName,
        [string] $packageVersion
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $nugetPackageBasePath = $settings.nugetSharedFolder
    if (!$nugetPackageBasePath) {
        $nugetPackageBasePath = $settings.appArtifactSharedFolder
        if (!$nugetPackageBasePath) {
            $nugetPackageBasePath = $ENV:PIPELINE_WORKSPACE
        }    
    }
    $nugetPackagePath = Join-Path -Path $nugetPackageBasePath -ChildPath "/.nuget/packages/$packageName/$packageVersion/"
    return $nugetPackagePath
}
function AddNugetPackageSource() {
    Param(
        [string] $sourceName,
        [string] $sourceUrl
    )

    Write-Host "Adding Nuget source $sourceName"
    Register-PackageSource -Name $sourceName -Location $sourceUrl -ProviderName NuGet
}
function RemoveNugetPackageSource() {
    Param(
        [string] $sourceName
    )

    Write-Host "Removing Nuget source $sourceName"
    Unregister-PackageSource -Source $sourceName
}