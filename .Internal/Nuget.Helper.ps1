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
        try {
            Expand-Archive -Path "$nugetPackagePath/$packageName.$packageVersion.zip" -DestinationPath "$nugetPackagePath" -Force
        }
        catch {
            # Fallback for any compatibility issues
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$nugetPackagePath/$packageName.$packageVersion.zip", "$nugetPackagePath")
        }
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
function New-NuGetFeedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$url,
        [Parameter(Mandatory = $false)]
        [string]$token = ''
    )
    OutputDebug -Message "Adding trusted NuGet feed $url"
    return [PSCustomObject]@{
        "url"   = $url
        "token" = $token
    }
}
function Initialize-BCCTrustedNuGetFeeds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$fromTrustedNuGetFeeds,
        [Parameter(Mandatory = $false)]
        [bool]$trustMicrosoftNuGetFeeds = $true
    )

    $bcContainerHelperConfig.TrustedNuGetFeeds = @()
    if ($fromTrustedNuGetFeeds) {
        $trustedNuGetFeeds = $fromTrustedNuGetFeeds | ConvertFrom-Json
        if ($trustedNuGetFeeds -and $trustedNuGetFeeds.Count -gt 0) {
            Write-Host "Adding trusted NuGet feeds from environment variable"
            $trustedNuGetFeeds = @($trustedNuGetFeeds | ForEach-Object {
                $feedConfig = New-NuGetFeedConfig -url $_.Url -token $_.Token
                $bcContainerHelperConfig.TrustedNuGetFeeds += @($feedConfig)
            })
        }
    }
    if ($trustMicrosoftNuGetFeeds) {
        $feedConfig = New-NuGetFeedConfig -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
        $bcContainerHelperConfig.TrustedNuGetFeeds += @($feedConfig)
    }
}