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
        [Parameter(Mandatory = $true)]
        [string]$fromTrustedNuGetFeeds,
        [Parameter(Mandatory = $false)]
        [bool]$trustMicrosoftNuGetFeeds = $true,
        [switch] $skipSymbolsFeeds
    )

    $requiredTrustedNuGetFeeds = @()
    if ($fromTrustedNuGetFeeds) {
        $trustedNuGetFeeds = $fromTrustedNuGetFeeds | ConvertFrom-Json
        if ($trustedNuGetFeeds -and $trustedNuGetFeeds.Count -gt 0) {
            Write-Host "Adding trusted NuGet feeds from environment variable"
            $requiredTrustedNuGetFeeds = @($trustedNuGetFeeds | ForEach-Object {
                    New-NuGetFeedConfig -name $_.Name -url $_.Url -token $_.Token
                })
        }
    }
    if ($trustMicrosoftNuGetFeeds) {
        $feedConfig = New-NuGetFeedConfig -name "MSApps" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json"
        $requiredTrustedNuGetFeeds += @($feedConfig)
        if (-not $skipSymbolsFeeds) {
            $feedConfig = New-NuGetFeedConfig -name "MSSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
            $requiredTrustedNuGetFeeds += @($feedConfig)
            $feedConfig = New-NuGetFeedConfig -name "AppSourceSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
            $requiredTrustedNuGetFeeds += @($feedConfig)
        }
    }
    if ($skipSymbolsFeeds) {
        $requiredTrustedNuGetFeeds = @($requiredTrustedNuGetFeeds | Where-Object { $_.url -notlike "*AppSourceSymbols*" -and $_.url -notlike "*MSSymbols*" })
    }
    return $requiredTrustedNuGetFeeds
}
Function Publish-BcNuGetPackageToBCContainer {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $nuGetServerUrl = "",
        [Parameter(Mandatory=$false)]
        [string] $nuGetToken = "",
        [Parameter(Mandatory=$true)]
        [string] $packageName,
        [Parameter(Mandatory=$false)]
        [string] $version = '0.0.0.0',
        [Parameter(Mandatory=$false)]
        [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
        [string] $select = 'Latest',
        [string] $containerName = "",
        [Hashtable] $bcAuthContext,
        [string] $environment,
        [Parameter(Mandatory=$false)]
        [string] $tenant = "default",
        [string] $appSymbolsFolder = "",
        [string] $copyInstalledAppsToFolder = "",
        [switch] $allowPrerelease,
        [switch] $skipVerification
    )

    if ($containerName -eq "" -and (!($bcAuthContext -and $environment))) {
        $containerName = $bcContainerHelperConfig.defaultContainerName
    }

    $installedApps = @()
    if ($bcAuthContext -and $environment) {
        $envInfo = Get-BcEnvironments -bcAuthContext $bcAuthContext -environment $environment
        $installedPlatform = [System.Version]$envInfo.platformVersion
        $installedCountry = $envInfo.countryCode.ToLowerInvariant()
        $installedApps = @(Get-BcEnvironmentInstalledExtensions -bcAuthContext $authContext -environment $environment | ForEach-Object { @{ "Publisher" = $_.Publisher; "Name" = $_.displayName; "Id" = $_.Id; "Version" = [System.Version]::new($_.VersionMajor, $_.VersionMinor, $_.VersionBuild, $_.VersionRevision) } })
    }
    else {
        $installedApps = @(Get-BcContainerAppInfo -containerName $containerName -installedOnly | ForEach-Object { @{ "Publisher" = $_.Publisher; "Name" = $_.Name; "Id" = "$($_.AppId)"; "Version" = $_.Version } } )
        $installedPlatform = [System.Version](Get-BcContainerPlatformVersion -containerOrImageName $containerName)
        $installedCountry = (Get-BcContainerCountry -containerOrImageName $containerName).ToLowerInvariant()
    }
    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
    New-Item $tmpFolder -ItemType Directory | Out-Null
    try {
        if (Download-BcNuGetPackageToFolder -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageName -version $version -appSymbolsFolder $tmpFolder -installedApps $installedApps -installedPlatform $installedPlatform -installedCountry $installedCountry -verbose:($VerbosePreference -eq 'Continue') -select $select -allowPrerelease:$allowPrerelease ) {
            $appFiles = Get-Item -Path (Join-Path $tmpFolder '*.app') | ForEach-Object {
                if ($appSymbolsFolder) {
                    Copy-Item -Path $_.FullName -Destination $appSymbolsFolder -Force
                }
                $_.FullName
            }
            Publish-BcContainerApp -containerName $containerName -bcAuthContext $bcAuthContext -environment $environment -tenant $tenant -appFile $appFiles -sync -install -upgrade -checkAlreadyInstalled -skipVerification -copyInstalledAppsToFolder $copyInstalledAppsToFolder
        }
        elseif ($ErrorActionPreference -eq 'Stop') {
            throw "No apps to publish"
        }
        else {
            Write-Host "No apps to publish"
        }
    }
    finally {
        Remove-Item -Path $tmpFolder -Recurse -Force
    }
}