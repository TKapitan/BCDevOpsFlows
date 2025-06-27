Param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject] $appJsonContent,
    [Parameter(Mandatory = $false)]
    [string] $mainAppId,
    [switch] $isTestApp
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_NUGETINITIALIZED) {
    throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
}

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json
$baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
$artifact = $settings.artifact

# Init application/platform parameters
$isAppJsonArtifact = $artifact.ToLower() -eq "////appjson"
$trustedNuGetFeedsMicrosoft = Get-BCCTrustedNuGetFeeds -includeMicrosoftNuGetFeeds -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
$versionParts = $appJsonContent.application.Split('.')
$versionParts[1] = ([int]$versionParts[1] + 1).ToString()
$applicationVersionFilter = "[$($appJsonContent.application),$($versionParts[0]).$($versionParts[1]).$($versionParts[2]).$($versionParts[3]))"

if ($isTestApp) {
    Write-Host "Skipping Microsoft package determination for test app."
}
else {
    $applicationPackage = "Microsoft.Application.symbols"
    if ($settings.country) {
        $applicationPackage = "Microsoft.Application.$($settings.country.ToUpper()).symbols"
    }
    Write-Host "Getting application package $applicationPackage for artifact $artifact"
 
    $buildCacheFolder = "$baseRepoFolder\.buildpackages"
    if (!(Test-Path $buildCacheFolder)) {
        New-Item -Path $buildCacheFolder -ItemType Directory | Out-Null
    }
    
    if ($ENV:AL_RUNWITH -eq "NuGet") {
        $parameters = @{
            "trustedNugetFeeds"    = $trustedNuGetFeedsMicrosoft
            "packageName"          = $applicationPackage
            "appSymbolsFolder"     = $buildCacheFolder
            "downloadDependencies" = "Microsoft"
            "select"               = "Latest"
        }

        $downloadedPackage = @()
        if ($artifact.ToLower() -eq "////latest") {
            $downloadedPackage = Get-BCDevOpsFlowsNuGetPackageToFolder @parameters
        } 
        elseif ($isAppJsonArtifact) {
            $parameters += @{
                "version" = $applicationVersionFilter
            }
            OutputDebug -Message "Using application version filter '$applicationVersionFilter' for application package."
            $downloadedPackage = Get-BCDevOpsFlowsNuGetPackageToFolder @parameters
        }
        else {
            throw "Invalid artifact setting ($artifact) in app.json. The artifact can only be '////latest' or '////appJson'."
        }

        if (!$downloadedPackage -or $downloadedPackage.Count -eq 0) {
            throw "No application package found for artifact $artifact with version filter $applicationVersionFilter."
        }

        $ENV:AL_APPJSONARTIFACT = $isAppJsonArtifact
        Write-Host "##vso[task.setvariable variable=AL_APPJSONARTIFACT;]$isAppJsonArtifact"
        OutputDebug -Message "Set environment variable AL_APPJSONARTIFACT to ($ENV:AL_APPJSONARTIFACT)"
    }
}

# Init dependency parameters
$dependenciesPackageCachePath = "$baseRepoFolder\.buildartifacts\Dependencies"
if (!(Test-Path $dependenciesPackageCachePath)) {
    New-Item -Path $dependenciesPackageCachePath -ItemType Directory | Out-Null
}
$trustedNuGetFeedsThirdParties = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
foreach ($dependency in $appJsonContent.dependencies) {
    if ($dependency.id -eq $mainAppId) {
        Write-Host "Skipping dependency $($dependency.name) with id $($dependency.id) as it is the main app"
        continue
    }
    $downloadDependencies = 'allButMicrosoft'
    $trustedNuGetFeedsDependencies = $trustedNuGetFeedsThirdParties
    if ($dependency.publisher -eq "Microsoft") {
        if ($ENV:AL_RUNWITH -ne "NuGet") {
            continue
        }
        $downloadDependencies = 'Microsoft'
        $trustedNuGetFeedsDependencies = $trustedNuGetFeedsMicrosoft
    }
    $parameters = @{
        "trustedNugetFeeds"    = $trustedNuGetFeedsDependencies
        "appSymbolsFolder"     = $dependenciesPackageCachePath
        "downloadDependencies" = $downloadDependencies
    }
    if ($ENV:AL_ALLOWPRERELEASE -eq "true") {
        # If enabled, we allow pre-release versions of dependencies.
        OutputDebug -Message "Allowing pre-release versions of dependencies."
        $parameters += @{
            "allowPrerelease" = $true
        }
    }    
    if ($isAppJsonArtifact -and $dependency.publisher -eq "Microsoft") {
        # For Microsoft dependencies with appjson artifact, we use the same version as the application package.
        OutputDebug -Message "Using application version filter '$applicationVersionFilter' for Microsoft dependency $($dependency.name)."
        $parameters += @{
            "version" = $applicationVersionFilter
        }
    }
    else {
        # For all other use cases, we use the version specified in the dependency (or newer).
        $dependencyVersionFilter = "[$($dependency.version),)"
        OutputDebug -Message "Using dependency version filter '$dependencyVersionFilter' for dependency $($dependency.name)."
        $parameters += @{
            "version" = $dependencyVersionFilter
        }
    }

    $packageName = Get-BCDevOpsFlowsNuGetPackageId -id $dependency.id -name $dependency.name -publisher $dependency.publisher
    Write-Host "Getting $($dependency.name) using name $($dependency.id)"
    $downloadedPackage = Get-BCDevOpsFlowsNuGetPackageToFolder -packageName $packageName @parameters

    if (!$downloadedPackage -or $downloadedPackage.Count -eq 0) {
        throw "No package found for dependency $($dependency.name) with id $($dependency.id) and version $($dependency.version)."
    }
}
    
# XXX this is temporary workaround to merge BCContainerHelper and NuGet build steps.
$artifact = $settings.artifact
$ENV:AL_ARTIFACT = $artifact
Write-Host "##vso[task.setvariable variable=AL_ARTIFACT;]$artifact"
OutputDebug -Message "Set environment variable AL_ARTIFACT to ($ENV:AL_ARTIFACT)"
