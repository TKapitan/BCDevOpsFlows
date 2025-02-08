. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function DownloadNugetPackage() {
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
    OutputDebug -Message "Using Nuget package path: $nugetPackagePath"
    if (-not (Test-Path -Path $nugetPackagePath)) {
        $nugetUrl = "https://www.nuget.org/api/v2/package/$packageName/$packageVersion"

        Write-Host "Downloading Nuget package $packageName $packageVersion from $nugetUrl..."
        New-Item -ItemType Directory -Path $nugetPackagePath | Out-Null
        Invoke-WebRequest -Uri $nugetUrl -OutFile "$nugetPackagePath/$packageName.$packageVersion.zip"

        # Unzip the package
        Expand-Archive -Path "$nugetPackagePath/$packageName.$packageVersion.zip" -DestinationPath "$nugetPackagePath"
        # Remove the zip file
        Remove-Item -Path "$nugetPackagePath/$packageName.$packageVersion.zip"
    }
    return $nugetPackagePath
}
function AddNugetPackageSource() {
    Param(
        [string] $sourceName,
        [string] $sourceUrl
    )

    if (-not $(Get-PackageSource -Name $sourceName -ProviderName NuGet -ErrorAction Ignore)) {
        Write-Host "Adding Nuget source $sourceName"
        nuget source add -Name $sourceName -source $sourceUrl
    }
}