. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function DownloadNugetPackage() {
    Param(
        [string] $packageName,
        [string] $packageVersion
    )

    $nugetPackagePath = GetNugetPackagePath -packageName $packageName -packageVersion $packageVersion
    OutputDebug -Message "Using Nuget package path: $nugetPackagePath"
    if (-not (Test-Path -Path $nugetPackagePath)) {
        $nugetUrl = "https://www.nuget.org/api/v2/package/$packageName/$packageVersion"

        Write-Host "Downloading Nuget package $packageName $packageVersion from $nugetUrl..."
        New-Item -ItemType Directory -Path $nugetPackagePath | Out-Null
        OutputDebug -Message "Downloading Nuget package $nugetUrl to $nugetPackagePath/$packageName.$packageVersion.zip"
        Invoke-WebRequest -Uri $nugetUrl -OutFile "$nugetPackagePath/$packageName.$packageVersion.zip"

        # Unzip the package
        Expand-Archive -Path "$nugetPackagePath/$packageName.$packageVersion.zip" -DestinationPath "$nugetPackagePath"
        # Remove the zip file
        Remove-Item -Path "$nugetPackagePath/$packageName.$packageVersion.zip"
    }
    return $nugetPackagePath
}

function GetNugetPackagePath() {
    Param(
        [string] $packageName,
        [string] $packageVersion
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $nugetPackageBasePath = $settings.writableFolderPath
    if (!$nugetPackageBasePath) {
        $nugetPackageBasePath = $ENV:PIPELINE_WORKSPACE
    }    
    $nugetPackagePath = Join-Path -Path $nugetPackageBasePath -ChildPath "/.nuget/packages/$packageName/$packageVersion/"
    return $nugetPackagePath
}
function AddNugetPackageSource() {
    Param(
        [string] $sourceName,
        [string] $sourceUrl
    )

    if (!(Get-PackageSource -Name $sourceName -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "Adding Nuget source $sourceName"
        Register-PackageSource -Name $sourceName -Location $sourceUrl -ProviderName NuGet | Out-null
    }
    else {
        OutputDebug -Message "Nuget source $sourceName already exists"
    }
}
function RemoveNugetPackageSource() {
    Param(
        [string] $sourceName
    )

    if (Get-PackageSource -Name $sourceName -ProviderName NuGet -ErrorAction SilentlyContinue) {
        Write-Host "Removing Nuget source $sourceName"
        Unregister-PackageSource -Source $sourceName | Out-null
    }
    else {
        OutputDebug -Message "Nuget source $sourceName not found"
    }
}