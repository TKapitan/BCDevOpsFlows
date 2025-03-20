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
        [PSCustomObject]$feed
    )

    if (!(Get-PackageSource -Name $feed.name -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "Adding Nuget source $($feed.name)"
        if ($feed.token) {
            $secureToken = ConvertTo-SecureString $feed.token -AsPlainText -Force
            $credentials = New-Object System.Management.Automation.PSCredential($feed.token, $secureToken)
            Register-PackageSource -Name $feed.name -Location $feed.url -ProviderName NuGet -Credential $credentials | Out-Null
            return
        }
        Register-PackageSource -Name $feed.name -Location $feed.url -ProviderName NuGet | Out-null
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
        $feedConfig = New-NuGetFeedConfig -name "MSSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
        $requiredTrustedNuGetFeeds += @($feedConfig)
        if (-not $skipSymbolsFeeds) {
            $feedConfig = New-NuGetFeedConfig -name "AppSourceSymbols" -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
            $requiredTrustedNuGetFeeds += @($feedConfig)
        }
    }
    if ($skipSymbolsFeeds) {
        $requiredTrustedNuGetFeeds = @($requiredTrustedNuGetFeeds | Where-Object { $_.url -notlike "*AppSourceSymbols*" })
    }
    return $requiredTrustedNuGetFeeds
}