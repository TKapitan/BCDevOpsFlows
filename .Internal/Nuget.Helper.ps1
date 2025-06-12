. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath ".\NuGet\Import-NuGet.ps1" -Resolve)

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
function Remove-AllNugetPackageSources() {
    Param()

    OutputDebug -Message "Removing all existing NuGet package sources"
    $sources = Get-PackageSource -ProviderName NuGet -WarningAction SilentlyContinue | Out-Null
    if (!$sources) {
        OutputDebug -Message "No NuGet package sources found"
        return
    }
    foreach ($source in $sources) {
        Remove-NugetPackageSource -sourceName $source.Name
    }
}
function Add-NugetPackageSource() {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$feed
    )

    if (!(Get-PackageSource -Name $feed.name -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "Adding Nuget source $($feed.name)"
        nuget sources add -Name $feed.name -Source $feed.url
    }
    else {
        OutputDebug -Message "Nuget source $($feed.name) already exists"
    }
}
function Remove-NugetPackageSource() {
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
        [string]$name,
        [Parameter(Mandatory = $true)]
        [string]$url,
        [Parameter(Mandatory = $false)]
        [string]$token = ''
    )
    OutputDebug -Message "Adding trusted NuGet feed $name ($url)"
    return [PSCustomObject]@{
        "name"  = $name
        "url"   = $url
        "token" = $token
    }
}
function Get-BCCTrustedNuGetFeeds {
    param(
        [Parameter(Mandatory = $false)]
        [string]$fromTrustedNuGetFeeds,
        [Parameter(Mandatory = $false)]
        [bool]$trustMicrosoftNuGetFeeds = $true,
        [switch] $includeMicrosoftNuGetFeeds,
        [switch] $skipSymbolsFeeds
    )

    Remove-AllNugetPackageSources

    $requiredTrustedNuGetFeeds = @()
    if ($fromTrustedNuGetFeeds) {
        OutputDebug -Message "Getting trusted NuGet feeds from trustedNuGetFeeds variable"
        $trustedNuGetFeeds = $fromTrustedNuGetFeeds | ConvertFrom-Json
        if ($trustedNuGetFeeds -and $trustedNuGetFeeds.Count -gt 0) {
            Write-Host "Adding trusted NuGet feeds from environment variable"
            $requiredTrustedNuGetFeeds = @($trustedNuGetFeeds | ForEach-Object {
                    New-NuGetFeedConfig -name $_.Name -url $_.Url -token $_.Token
                })
        }
    }
    if ($includeMicrosoftNuGetFeeds) {
        OutputDebug -Message "Getting Microsoft NuGet feeds"
        if (-not $trustMicrosoftNuGetFeeds) {
            throw "Microsoft NuGet feeds are required but not trusted. Set trustMicrosoftNuGetFeeds to true."
        }
        $feedConfig = New-NuGetFeedConfig -name "MSApps" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json"
        $requiredTrustedNuGetFeeds += @($feedConfig)
        if (-not $skipSymbolsFeeds) {
            $feedConfig = New-NuGetFeedConfig -name "MSSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
            $requiredTrustedNuGetFeeds += @($feedConfig)
            $feedConfig = New-NuGetFeedConfig -name "AppSourceSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
            $requiredTrustedNuGetFeeds += @($feedConfig)
        }
    }
    return $requiredTrustedNuGetFeeds
}
function ValidateNuGetParameters {
    Param(
        [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
        [string] $artifact,
        [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
        [string] $buildMode = "Default"
    )

    $validArtifacts = @("////latest", "////appjson")
    $validBuildModes = @("Default")
    if ($artifact.ToLower() -notin $validArtifacts) {
        throw "Invalid artifact setting ($artifact) in BuildWithNuget. Valid artifacts are: $($validArtifacts -join ', ')."
    }
    if ($buildMode.ToLower() -notin $validBuildModes) {
        throw "Invalid build mode ($buildMode) in BuildWithNuget. Valid build modes are: $($validBuildModes -join ', ')."
    }
}