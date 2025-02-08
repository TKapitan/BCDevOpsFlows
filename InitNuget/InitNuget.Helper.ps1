function DownloadNugetPackage() {
    Param(
        [string] $packageName,
        [string] $packageVersion
    )

    $settings = $ENV:AL_SETTINGS
    $nugetPackageBasePath = $settings.nugetSharedFolder
    if ($nugetPackageBasePath -eq '') {
        $nugetPackageBasePath = $settings.appArtifactSharedFolder
        if ($nugetPackageBasePath -eq '') {
            $nugetPackageBasePath = $ENV:PIPELINE_WORKSPACE
        }    
    }
    $nugetPackagePath = Join-Path -Path $nugetPackagePath -ChildPath "/.nuget/packages/$packageName/$packageVersion/"
    if (-not (Test-Path -Path $nugetPackagePath)) {
        $nugetUrl = "https://www.nuget.org/api/v2/package/$packageName/$packageVersion"

        Write-Host "Downloading Nuget package $packageName $packageVersion..."
        New-Item -ItemType Directory -Path $nugetPackagePath | Out-Null
        Invoke-WebRequest -Uri $nugetUrl -OutFile "$nugetPackagePath/$packageName.$packageVersion.zip"

        # Unzip the package
        Expand-Archive -Path "$nugetPackagePath/$packageName.$packageVersion.zip" -DestinationPath "$nugetPackagePath"
        # Remove the zip file
        Remove-Item -Path "$nugetPackagePath/$packageName.$packageVersion.zip"
    }
    return $nugetPackagePath
}
